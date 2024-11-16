data "aws_ami" "amzn2023" {
  most_recent = true

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }
}

data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat's official AWS owner ID

  filter {
    name   = "name"
    values = ["RHEL-9*_HVM-*-x86_64-*"] # Pattern to match RHEL 9 AMIs
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "random_password" "pgadmin" {
  length  = 16
  lower   = true
  numeric = true
  special = false
  upper   = true
}

resource "aws_instance" "jumphost" {
  ami                         = data.aws_ami.rhel9.id
  associate_public_ip_address = true
  instance_type               = "m5.xlarge"
  subnet_id                   = module.vpc.public_subnets[0]

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname jumphost

    dnf install -y nmap-ncat mtr

    # ec2 instance connect
    mkdir /tmp/ec2-instance-connect
    curl https://amazon-ec2-instance-connect-us-west-2.s3.us-west-2.amazonaws.com/latest/linux_amd64/ec2-instance-connect.rpm -o /tmp/ec2-instance-connect/ec2-instance-connect.rpm
    curl https://amazon-ec2-instance-connect-us-west-2.s3.us-west-2.amazonaws.com/latest/linux_amd64/ec2-instance-connect-selinux.noarch.rpm -o /tmp/ec2-instance-connect/ec2-instance-connect-selinux.rpm
    dnf install -y /tmp/ec2-instance-connect/ec2-instance-connect.rpm /tmp/ec2-instance-connect/ec2-instance-connect-selinux.rpm

    # pgadmin
    dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
    dnf install -y https://ftp.postgresql.org/pub/pgadmin/pgadmin4/yum/pgadmin4-redhat-repo-2-1.noarch.rpm
    dnf -q -y makecache --refresh
    dnf install -y pgadmin4
    systemctl start httpd
    systemctl enable httpd
    export PGADMIN_SETUP_EMAIL="pgadmin@example.com"
    export PGADMIN_SETUP_PASSWORD="${random_password.pgadmin.result}"
    /usr/pgadmin4/bin/setup-web.sh --yes
  EOF

  vpc_security_group_ids = [
    module.security_group_jumphost.security_group_id
  ]

  tags = {
    Name    = "${local.name}-jumphost"
    UseCase = local.name
  }
}

resource "aws_instance" "permissions" {
  ami                         = data.aws_ami.amzn2023.id
  associate_public_ip_address = false
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc.private_subnets[0]

  user_data = <<-EOF
    #!/bin/bash -xe
    hostnamectl set-hostname permissions
    yum update -y
    yum install -y nc mtr postgresql16

    export PGPASSWORD="${jsondecode(data.aws_secretsmanager_secret_version.dbadmin.secret_string)["password"]}"
    export PGDATABASE="${module.db.db_instance_name}"
    export DBADMIN="${module.db.db_instance_username}"
    export RDSHOST="${module.db.db_instance_address}"

    for DBUSER in "user_r" "user_rw"; do
      psql -h $RDSHOST -U $DBADMIN -d $PGDATABASE -c "
        DO \$\$
        BEGIN
          -- Create the role if it does not exist
          IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$DBUSER') THEN
            CREATE ROLE "$DBUSER" WITH LOGIN;
          END IF;

          -- Grant permissions on the public schema and tables
          GRANT CONNECT ON DATABASE "$PGDATABASE" TO "$DBUSER";
          GRANT USAGE ON SCHEMA public TO "$DBUSER";

          -- Grant specific table permissions based on user type
          IF '$DBUSER' = 'user_r' THEN
            RAISE NOTICE 'Granting SELECT privileges to user % on all tables in schema public.', '$DBUSER';
            GRANT SELECT ON ALL TABLES IN SCHEMA public TO "$DBUSER";
          ELSIF '$DBUSER' = 'user_rw' THEN
            RAISE NOTICE 'Granting schema-level privileges to user %', '$DBUSER';
            GRANT USAGE, CREATE ON SCHEMA public TO "$DBUSER";
            GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "$DBUSER";
          ELSE
            RAISE NOTICE 'No specific permissions defined for user %.', '$DBUSER';
          END IF;

          -- Grant rds_iam role
          GRANT rds_iam TO "$DBUSER";
        END;
        \$\$;
      "
    done
  EOF

  vpc_security_group_ids = [
    module.security_group_client.security_group_id
  ]

  tags = {
    Name    = "${local.name}-permissions"
    UseCase = local.name
  }
}

resource "aws_instance" "user_rw" {
  ami                         = data.aws_ami.amzn2023.id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.user_rw.name
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc.private_subnets[0]

  user_data = <<-EOF
    #!/bin/bash -xe
    hostnamectl set-hostname userrw
    yum update -y
    yum install -y nc mtr postgresql16

    # Download the RDS CA certificate
    curl -o /tmp/rds-ca-cert.pem "https://truststore.pki.rds.amazonaws.com/${data.aws_region.current.name}/${data.aws_region.current.name}-bundle.pem"

    # Set environment variables
    export PGSSLROOTCERT=/tmp/rds-ca-cert.pem
    export PGDATABASE="${module.db.db_instance_name}"
    export RDSHOST="${module.db.db_instance_address}"
    export DBUSER="user_rw"

    # Generate the RDS auth token
    export TOKEN=$(aws rds generate-db-auth-token --hostname "$RDSHOST" --port 5432 --region "${data.aws_region.current.name}" --username "$DBUSER")

    # Run query
    export PGPASSWORD=$TOKEN
    result=$(psql "sslmode=verify-full sslrootcert=$PGSSLROOTCERT host=$RDSHOST port=5432 dbname=$PGDATABASE user=$DBUSER" -At -c "
      DO \$\$
      BEGIN
        IF NOT EXISTS (
          SELECT 1
          FROM information_schema.tables
          WHERE table_schema = 'public' AND table_name = 'employees'
        ) THEN
          -- Create table
          CREATE TABLE public.employees (
            id SERIAL PRIMARY KEY,
            first_name VARCHAR(50),
            last_name VARCHAR(50),
            hire_date DATE,
            salary DECIMAL(10, 2),
            department_id INT
          );
          -- Insert row
          INSERT INTO public.employees (first_name, last_name, hire_date, salary, department_id)
          VALUES ('John', 'Doe', '2024-01-15', 60000.00, 1);
          RAISE NOTICE 'Table employees has been created.';
        ELSE
          RAISE NOTICE 'Table employees already exists, skipping creation.';
        END IF;
      END;
      \$\$;
    ")
    echo "Query result: $result"
  EOF

  vpc_security_group_ids = [
    module.security_group_client.security_group_id
  ]

  tags = {
    Name    = "${local.name}-userrw"
    UseCase = local.name
  }

  depends_on = [
    aws_instance.permissions
  ]
}

resource "aws_instance" "user_r" {
  ami                         = data.aws_ami.amzn2023.id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.user_r.name
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc.private_subnets[0]

  user_data = <<-EOF
    #!/bin/bash -xe
    hostnamectl set-hostname userr
    yum update -y
    yum install -y nc mtr postgresql16

    # Download the RDS CA certificate
    curl -o /tmp/rds-ca-cert.pem "https://truststore.pki.rds.amazonaws.com/${data.aws_region.current.name}/${data.aws_region.current.name}-bundle.pem"

    # Set environment variables
    export PGSSLROOTCERT=/tmp/rds-ca-cert.pem
    export PGDATABASE="${module.db.db_instance_name}"
    export RDSHOST="${module.db.db_instance_address}"
    export DBUSER="user_r"

    # Generate the RDS auth token
    export TOKEN=$(aws rds generate-db-auth-token --hostname "$RDSHOST" --port 5432 --region "${data.aws_region.current.name}" --username "$DBUSER")

    # Run query
    export PGPASSWORD=$TOKEN
    result=$(psql "sslmode=verify-full sslrootcert=$PGSSLROOTCERT host=$RDSHOST port=5432 dbname=$PGDATABASE user=$DBUSER" -At -c "
      SELECT
        *
      FROM
        public.employees;
    ")
    echo "Query result: $result"
  EOF

  vpc_security_group_ids = [
    module.security_group_client.security_group_id
  ]

  tags = {
    Name    = "${local.name}-userr"
    UseCase = local.name
  }

  depends_on = [
    aws_instance.user_rw
  ]
}
