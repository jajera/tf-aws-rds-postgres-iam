data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "user_r" {
  name               = "${local.name}-user_r"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_policy" "rds_readonly_policy" {
  name        = "rds-readonly-policy"
  description = "Allows RDS read-only access"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds-db:connect"
      ],
      "Resource": "arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${module.db.db_instance_resource_id}/user_r"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "user1_role_policy" {
  role       = aws_iam_role.user_r.name
  policy_arn = aws_iam_policy.rds_readonly_policy.arn
}

resource "aws_iam_role" "user_rw" {
  name               = "${local.name}-user_rw"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_policy" "rds_readwrite_policy" {
  name        = "rds-readwrite-policy"
  description = "Allows RDS read-write access"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds-db:connect"
      ],
      "Resource": "arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${module.db.db_instance_resource_id}/user_rw"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "user2_role_policy" {
  role       = aws_iam_role.user_rw.name
  policy_arn = aws_iam_policy.rds_readwrite_policy.arn
}

resource "aws_iam_instance_profile" "user_r" {
  name = "user_r-instance-profile"
  role = aws_iam_role.user_r.name
}

resource "aws_iam_instance_profile" "user_rw" {
  name = "user_rw-instance-profile"
  role = aws_iam_role.user_rw.name
}
