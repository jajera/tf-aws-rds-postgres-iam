module "db" {
  source = "terraform-aws-modules/rds/aws"

  identifier = local.name

  engine            = local.db_engine
  engine_version    = local.db_engine_version
  instance_class    = local.db_instance_class
  allocated_storage = 5

  db_name             = local.db_name
  username            = local.db_username
  port                = local.db_port
  publicly_accessible = local.db_publicly_accessible

  iam_database_authentication_enabled = local.db_iam_enabled

  backup_window      = local.db_backup_window
  maintenance_window = local.db_maintenance_window

  # Setting manage_master_user_password_rotation to false after it
  # has previously been set to true disables automatic rotation
  # however using an initial value of false (default) does not disable
  # automatic rotation and rotation will be handled by RDS.
  # manage_master_user_password_rotation allows users to configure
  # a non-default schedule and is not meant to disable rotation
  # when initially creating / enabling the password management feature
  manage_master_user_password_rotation              = local.db_manage_master_user_password_rotation
  master_user_password_rotate_immediately           = local.db_master_user_password_rotate_immediately
  master_user_password_rotation_schedule_expression = local.db_master_user_password_rotation_schedule_expression

  multi_az               = local.db_multi_az
  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = local.db_vpc_security_group_ids

  enabled_cloudwatch_logs_exports = local.db_enabled_cloudwatch_logs_exports
  create_cloudwatch_log_group     = local.db_create_cloudwatch_log_group

  backup_retention_period = local.db_backup_retention_period
  skip_final_snapshot     = local.db_skip_final_snapshot

  performance_insights_enabled          = local.db_performance_insights_enabled
  performance_insights_retention_period = local.db_performance_insights_retention_period

  monitoring_role_use_name_prefix = local.db_monitoring_role_use_name_prefix
  monitoring_role_description     = local.db_monitoring_role_description

  # Enhanced Monitoring - see example for details on how to create the role
  # by yourself, in case you don't want to create it automatically
  monitoring_interval    = local.db_monitoring_interval
  monitoring_role_name   = local.db_monitoring_role_name
  create_monitoring_role = local.db_create_monitoring_role

  tags = local.tags

  # DB subnet group
  create_db_subnet_group = local.create_db_subnet_group
  subnet_ids             = module.vpc.database_subnets

  # DB parameter group
  family = local.db_family

  # Database Deletion Protection
  deletion_protection = local.db_deletion_protection

  parameters = [
    {
      name  = "autovacuum"
      value = 1
    },
    {
      name  = "client_encoding"
      value = "utf8"
    }
  ]
}
