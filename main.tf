resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  name = "rds-postgres-iam-${random_string.suffix.result}"

  tags = {
    UseCase = local.name
  }

  # vpc
  region               = "ap-southeast-2"
  vpc_cidr             = "10.0.0.0/16"
  azs                  = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnets       = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets      = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  database_subnets     = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
  enable_dns_support   = true
  enable_dns_hostnames = true

  # rds postgres
  db_name                                              = "iam"
  db_username                                          = "dbadmin"
  db_iam_enabled                                       = true
  db_manage_master_user_password_rotation              = true
  db_master_user_password_rotate_immediately           = false
  db_master_user_password_rotation_schedule_expression = "rate(15 days)"

  create_db_subnet_group    = true
  db_port                   = "5432"
  db_publicly_accessible    = false
  db_subnet_group_name      = module.vpc.database_subnet_group
  db_subnet_ids             = module.vpc.database_subnets
  db_vpc_security_group_ids = [module.security_group_rdspsqlserver.security_group_id]

  db_allocated_storage = 5
  db_engine            = "postgres"
  db_engine_version    = "16"
  db_family            = "postgres16"
  db_instance_class    = "db.t3.micro"
  db_multi_az          = true

  db_deletion_protection = false
  db_skip_final_snapshot = true
  db_apply_immediately   = true

  db_enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  db_create_cloudwatch_log_group     = true

  db_create_monitoring_role          = true
  db_monitoring_interval             = "30"
  db_monitoring_role_description     = "Role to monitor DB"
  db_monitoring_role_name            = "RDSMonitoringRole"
  db_monitoring_role_use_name_prefix = true

  db_backup_retention_period = 1
  db_backup_window           = "03:00-06:00"
  db_maintenance_window      = "Mon:00:00-Mon:03:00"

  db_performance_insights_enabled          = true
  db_performance_insights_retention_period = 7
}

# used for testing and shouldn't be done in production
resource "null_resource" "example" {
  triggers = {
    jumphost_ip  = "${aws_instance.jumphost.public_ip}"
    pgadmin_pass = "${random_password.pgadmin.result}"
    pg_dbadmin   = "${module.db.db_instance_username}"
    pg_pass      = "${jsondecode(data.aws_secretsmanager_secret_version.dbadmin.secret_string)["password"]}"
    rds_host     = "${module.db.db_instance_address}"
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "DBADMIN=${module.db.db_instance_username}" > terraform.tmp
      echo "PGADMIN_SETUP_EMAIL=pgadmin@example.com" >> terraform.tmp
      echo "PGADMIN_SETUP_PASSWORD=${random_password.pgadmin.result}" >> terraform.tmp
      echo "PGADMIN_URL=http://${aws_instance.jumphost.public_ip}/pgadmin4" >> terraform.tmp
      echo "PGDATABASE=${module.db.db_instance_name}" >> terraform.tmp
      echo "PGPASSWORD=${jsondecode(data.aws_secretsmanager_secret_version.dbadmin.secret_string)["password"]}" >> terraform.tmp
      echo "RDSHOST=${module.db.db_instance_address}" >> terraform.tmp
      chmod +x terraform.tmp
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      rm -f terraform.tmp
    EOT
  }
}

# retrieve dbadmin credentials
data "aws_secretsmanager_secret" "dbadmin" {
  arn = module.db.db_instance_master_user_secret_arn
}

data "aws_secretsmanager_secret_version" "dbadmin" {
  secret_id = data.aws_secretsmanager_secret.dbadmin.id
}
