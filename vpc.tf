module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.14.0"

  name = local.name
  cidr = local.vpc_cidr

  azs              = local.azs
  database_subnets = local.database_subnets
  private_subnets  = local.private_subnets
  public_subnets   = local.public_subnets

  enable_dns_hostnames = local.enable_dns_hostnames
  enable_dns_support   = local.enable_dns_support
  enable_nat_gateway   = true
  single_nat_gateway   = true

  tags = local.tags
}

module "security_group_rdspsqlserver" {
  source  = "tfstack/security-group/aws"
  version = "1.0.6"


  name        = "rdspsqlserver-${random_string.suffix.result}"
  description = "Security group for an RDS PostgreSQL server, allowing inbound PostgreSQL traffic on port 5432 and all outbound traffic."
  vpc_id      = module.vpc.vpc_id

  advance_ingress_rules = [
    {
      from_port   = 5432
      to_port     = 5432
      ip_protocol = "tcp"
      cidr_ipv4   = local.vpc_cidr
      description = "Allow inbound PostgreSQL traffic (TCP) on port 5432 from the ${local.vpc_cidr} subnet"
      tags = {
        Role        = "Database"
        Environment = "Production"
        Service     = "RDS"
      }
    }
  ]

  advance_egress_rules = [
    {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound traffic"
      tags = {
        Role        = "Database"
        Environment = "Production"
        Service     = "RDS"
      }
    }
  ]

  tags = {
    Name = "rdspsqlserver-${random_string.suffix.result}"
  }
}

data "http" "my_public_ip" {
  url = "http://ifconfig.me/ip"
}

module "security_group_instance_connect" {
  source  = "tfstack/security-group/aws"
  version = "1.0.7"

  name        = "${local.name}-instance-connect"
  description = "Instance connect security group"
  vpc_id      = module.vpc.vpc_id

  custom_ingress_rules = [
    {
      rule_name   = "ssh-22-tcp"
      cidr_ipv4   = "${data.http.my_public_ip.response_body}/32"
      description = "Allow SSH from specific public IP for administrative access"
      tags = {
        Purpose  = "Admin Access"
        Protocol = "TCP"
        Port     = "22"
        Access   = "Inbound"
      }
    }
  ]

  advance_egress_rules = [
    {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound traffic"
      tags = {
        Purpose  = "Any to any"
        Protocol = "-1"
        Port     = "0"
        Access   = "Outbound"
      }
    }
  ]

  tags = {
    Name = "instance-connect-${random_string.suffix.result}"
  }
}

module "security_group_jumphost" {
  source  = "tfstack/security-group/aws"
  version = "1.0.7"

  name        = "${local.name}-jumphost"
  description = "Security group for Jumphost"
  vpc_id      = module.vpc.vpc_id

  custom_ingress_rules = [
    {
      rule_name   = "ssh-22-tcp"
      cidr_ipv4   = "${data.http.my_public_ip.response_body}/32"
      description = "Allow SSH from specific public IP for administrative access"
      tags = {
        Purpose  = "Admin Access"
        Protocol = "TCP"
        Port     = "22"
        Access   = "Inbound"
      }
    },
    {
      rule_name   = "http-80-tcp"
      cidr_ipv4   = "${data.http.my_public_ip.response_body}/32"
      description = "Allow HTTP traffic on port 80 for web access"
      tags = {
        Purpose  = "Web Access"
        Protocol = "TCP"
        Port     = "80"
        Access   = "Inbound"
      }
    }
  ]

  custom_egress_rules = [
    {
      rule_name   = "ping-icmp"
      cidr_ipv4   = local.vpc_cidr
      description = "Allow outbound ICMP (Ping) to any"
      tags = {
        Purpose  = "Internal Communication"
        Protocol = "ICMP"
        Access   = "Outbound"
      }
    },
    {
      rule_name   = "ssh-22-tcp"
      cidr_ipv4   = local.vpc_cidr
      description = "Allow outbound SSH to internal network range"
      tags = {
        Purpose  = "Internal Communication"
        Protocol = "TCP"
        Port     = "22"
        Access   = "Outbound"
      }
    }
  ]

  advance_egress_rules = [
    {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound traffic"
      tags = {
        Purpose  = "Any to any"
        Protocol = "-1"
        Port     = "0"
        Access   = "Outbound"
      }
    }
  ]

  tags = {
    Name = "jumphost-${random_string.suffix.result}"
  }
}


module "security_group_client" {
  source  = "tfstack/security-group/aws"
  version = "1.0.7"

  name        = "${local.name}-client"
  description = "Security group for Client"
  vpc_id      = module.vpc.vpc_id

  custom_ingress_rules = [
    {
      rule_name   = "ssh-22-tcp"
      cidr_ipv4   = "${data.http.my_public_ip.response_body}/32"
      description = "Allow SSH from specific public IP for administrative access"
      tags = {
        Purpose  = "Admin Access"
        Protocol = "TCP"
        Port     = "22"
        Access   = "Inbound"
      }
    },
    {
      rule_name   = "ssh-22-tcp"
      cidr_ipv4   = local.vpc_cidr
      description = "Allow SSH from internal network"
      tags = {
        Purpose  = "Admin Access Internal"
        Protocol = "TCP"
        Port     = "22"
        Access   = "Inbound"
      }
    }
  ]

  advance_egress_rules = [
    {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound traffic"
      tags = {
        Purpose  = "Any to any"
        Protocol = "-1"
        Port     = "0"
        Access   = "Outbound"
      }
    }
  ]

  tags = {
    Name = "client-${random_string.suffix.result}"
  }
}

resource "aws_ec2_instance_connect_endpoint" "example" {
  subnet_id          = module.vpc.public_subnets[0]
  security_group_ids = [module.security_group_instance_connect.security_group_id]
  tags               = local.tags
}
