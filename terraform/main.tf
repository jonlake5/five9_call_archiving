terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.58.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}


### VPC, subnets, and security groups
resource "aws_vpc" "db_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = "true"
  enable_dns_hostnames = "true"
}

resource "aws_vpc_endpoint" "endpoint_secrets" {
  vpc_id = aws_vpc.db_vpc.id
  service_name = "com.amazonaws.us-east-1.secretsmanager"
  private_dns_enabled = true
  security_group_ids = [aws_security_group.security_group_endpoint.id]
  vpc_endpoint_type = "Interface"
  subnet_ids = [ aws_subnet.lambda_private_1.id, aws_subnet.lambda_private_2.id]
}
resource "aws_subnet" "db_private_1" {
  vpc_id = aws_vpc.db_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "db_private"
  }

}

resource "aws_subnet" "db_private_2" {
  vpc_id = aws_vpc.db_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1c"
}

resource "aws_db_subnet_group" "db_subnet_group" {
    name        = "db-subnet-group"
    subnet_ids  = [ aws_subnet.db_private_1.id, aws_subnet.db_private_2.id]
    tags = {
        Name = "DB Subnet Group"
    }
}

resource "aws_subnet" "lambda_private_1" {
  vpc_id = aws_vpc.db_vpc.id
  cidr_block = "10.0.11.0/24"
  availability_zone = "us-east-1a"  
}

resource "aws_subnet" "lambda_private_2" {
  vpc_id = aws_vpc.db_vpc.id
  cidr_block = "10.0.12.0/24"
  availability_zone = "us-east-1c"  
}


resource "aws_security_group" "security_group_lambda" {
  name    = "security-group-lambda"
  description = "allow lambda outbound"
  vpc_id = aws_vpc.db_vpc.id

}

resource "aws_security_group" "security_group_database" {
  name    = "security-group-database"
  description = "allow postgres inbound"
  vpc_id = aws_vpc.db_vpc.id

}

resource "aws_security_group" "security_group_endpoint" {
  name    = "security-group-endpoint"
  description = "allow https inbound"
  vpc_id = aws_vpc.db_vpc.id

}

resource "aws_vpc_security_group_ingress_rule" "allow_https_in" {
  security_group_id = aws_security_group.security_group_endpoint.id
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = -1
}

resource "aws_vpc_security_group_egress_rule" "allow_all_outbound" {
  security_group_id = aws_security_group.security_group_lambda.id
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = -1
}

resource "aws_vpc_security_group_ingress_rule" "allow_postgres_inbound" {
  security_group_id = aws_security_group.security_group_database.id
  ip_protocol = "tcp"
  from_port = 5432
  to_port = 5432
  referenced_security_group_id = aws_security_group.security_group_lambda.id
}

### S3 recording bucket, notifications and policies

resource "aws_s3_bucket_intelligent_tiering_configuration" "recording_bucket_tiering" {
  bucket = aws_s3_bucket.recording_bucket.id
  name   = "EntireBucket"
  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = var.days_until_tiering
  }
}

resource "aws_s3_bucket" "recording_bucket" { 

}

resource "aws_s3_bucket_notification" "recording_bucket_notification" {
  bucket = aws_s3_bucket.recording_bucket.id
  topic {
    topic_arn     = aws_sns_topic.new_object_topic.arn
    events        = ["s3:ObjectCreated:*"]
  }
}

resource "aws_sns_topic" "new_object_topic" {
  name = "new_object_topic"
}

resource "aws_sns_topic_policy" "topic_allow_s3_publish" {
  arn = aws_sns_topic.new_object_topic.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

resource "aws_sns_topic_subscription" "new_object_lambda_target" {
  topic_arn = aws_sns_topic.new_object_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.lambda_update_database.arn
}

data "aws_iam_policy_document" "sns_topic_policy" {
  policy_id = "__default_policy_ID"
  statement {
    actions = [
      "SNS:Publish"
    ]
    principals {
      type  = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
      effect =  "Allow"
    resources = [
      aws_sns_topic.new_object_topic.arn
    ]
  }
}


### Lambda Query Database
resource "aws_lambda_permission" "allow_sns" {
  statement_id = "AllowSNSExecute"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_update_database.function_name
  principal = "sns.amazonaws.com"
  source_arn = aws_sns_topic.new_object_topic.arn
}

data "aws_iam_policy_document" "data_lambda_execution_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect = "Allow"
    principals {
      type= "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }   
}

resource "aws_iam_role" "lambda_execution_role" {
  name               = "lambda_execution_role"
  assume_role_policy = data.aws_iam_policy_document.data_lambda_execution_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_execution_role.id
  policy_arn = aws_iam_policy.lambda_logging.arn
}


data "aws_iam_policy_document" "lambda_logging" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:AttachNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeInstances"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"
  policy      = data.aws_iam_policy_document.lambda_logging.json
}

data "archive_file" "lambda_update_database" {
  type = "zip"
  source_dir = "../lambda_db_update"
  output_path = "../lambda_update_db.zip"
}

resource "aws_lambda_function" "lambda_update_database" {
  filename = data.archive_file.lambda_update_database.output_path
  handler = "lambda_db_query.lambda_handler"
  function_name = "lambda_update_database"
  runtime =   "python3.9"
    vpc_config {
    subnet_ids         = [aws_subnet.lambda_private_1.id, aws_subnet.lambda_private_2.id]
    security_group_ids = [aws_security_group.security_group_lambda.id]
  }
  role = aws_iam_role.lambda_execution_role.arn

}


### Database
resource "aws_rds_cluster" "postgresql" {
  cluster_identifier                  = "aurora-cluster-demo"
  engine                              = "aurora-postgresql"
  database_name                       = "callsearch"
  master_username                     = "callsearch"
  master_password                     = "password"
  backup_retention_period             = 5
  preferred_backup_window             = "07:00-09:00"
  db_subnet_group_name                = aws_db_subnet_group.db_subnet_group.id
  vpc_security_group_ids              = [aws_security_group.security_group_database.id]
  skip_final_snapshot                 = true
  iam_database_authentication_enabled = false
  backtrack_window                    = 0
  deletion_protection                 = false
  enabled_cloudwatch_logs_exports     = []
  iops                                = 0
  tags                                =  null
}

resource "aws_rds_cluster_instance" "instance1" {
  cluster_identifier = aws_rds_cluster.postgresql.id
  instance_class     = "db.t3.medium"
  engine             = aws_rds_cluster.postgresql.engine
  engine_version     = aws_rds_cluster.postgresql.engine_version
}

resource "aws_secretsmanager_secret" "database_endpoint" {
  description = "Connection Endpoint of Database"
  name = "DatabaseEndpoint"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_endpoint_value" {
  secret_id     = aws_secretsmanager_secret.database_endpoint.id
  secret_string = aws_rds_cluster.postgresql.endpoint
}

resource "aws_secretsmanager_secret" "database_port" {
  description = "Connection Endpoint of Database"
  name = "DatabasePort"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_port_value" {
  secret_id     = aws_secretsmanager_secret.database_port.id
  secret_string = aws_rds_cluster.postgresql.port
}

resource "aws_secretsmanager_secret" "database_user" {
  description = "Database user name"
  name = "DatabaseUser"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_user_value" {
  secret_id     = aws_secretsmanager_secret.database_user.id
  secret_string = aws_rds_cluster.postgresql.master_username
}

resource "aws_secretsmanager_secret" "database_password" {
  description = "Database password"
  name = "DatabaseMasterPassword"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_password_value" {
  secret_id     = aws_secretsmanager_secret.database_password.id
  secret_string = aws_rds_cluster.postgresql.master_password
}

resource "aws_secretsmanager_secret" "database_name" {
  description = "Database name"
  name = "DatabaseName"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_name_value" {
  secret_id     = aws_secretsmanager_secret.database_name.id
  secret_string = aws_rds_cluster.postgresql.database_name
}


### Web Bucket
resource "aws_s3_bucket" "web_bucket" {

}
resource "aws_s3_bucket_website_configuration" "example" {
  bucket = aws_s3_bucket.web_bucket.id
  index_document {
    suffix = "search.html"
  }
  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_policy" "allow_access_from_internet" {
  bucket = aws_s3_bucket.web_bucket.id
  policy = data.aws_iam_policy_document.allow_public_access.json
}

data "aws_iam_policy_document" "allow_public_access" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      "${aws_s3_bucket.web_bucket.arn}/*",
    ]
  }
}


### Transfer Server
resource "aws_transfer_server" "call_upload" {
  endpoint_type           = "PUBLIC"
  protocols               = ["SFTP"]
  identity_provider_type  = "SERVICE_MANAGED"
  tags = {
    Name = "Call Upload"
  }
}

resource "aws_transfer_user" "upload_user" {
  server_id = aws_transfer_server.call_upload.id
  user_name = "upload_user"
  home_directory = "/${aws_s3_bucket.recording_bucket.id}"
  home_directory_type = "PATH"
  role = aws_iam_role.S3TransferUser.arn
}

resource "aws_iam_role" "S3TransferUser" {
  name               = "S3TransferUser"
  assume_role_policy = data.aws_iam_policy_document.assume_role_transfer.json
}

data "aws_iam_policy_document" "assume_role_transfer" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["transfer.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "S3PutObject" {
  statement {
    sid       = "AllowAccesstoS3"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.recording_bucket.arn}"]
  }
  statement {
    sid       = "HomeDirAccess"
    effect    =  "Allow"
    actions   = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObjectVersion",
      "s3:GetObjectACL",
      "s3:PutObjectAcl"
    ]
    resources = ["${aws_s3_bucket.recording_bucket.arn}*"]
  }   
}

resource "aws_iam_role_policy" "role_S3_upload" {
  name = "S3TransferRole"
  role = aws_iam_role.S3TransferUser.id
  policy = data.aws_iam_policy_document.S3PutObject.json
}


### Lambda Query Database
data "archive_file" "lambda_query_database" {
  type = "zip"
  source_dir = "../lambda_db_query"
  output_path = "../lambda_db_query.zip"
}

resource "aws_lambda_function" "lambda_query_database" {
  filename = data.archive_file.lambda_update_database.output_path
  handler = "lambda_function.lambda_handler"
  function_name = "lambda_query_database"
  runtime =   "python3.9"
    vpc_config {
    subnet_ids         = [aws_subnet.lambda_private_1.id, aws_subnet.lambda_private_2.id]
    security_group_ids = [aws_security_group.security_group_lambda.id]
  }
  role = aws_iam_role.lambda_execution_role.arn

}

resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id = "AllowApiGateway"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_query_database.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = aws_api_gateway_rest_api.api_gateway.arn
}

### API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name = "ApiQueryDatabase"
  description = "API Gateway to query database"
}

resource "aws_api_gateway_method" "api_method" {
  authorization = "NONE"
  http_method = "POST"
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_rest_api.api_gateway.root_resource_id
}

resource "aws_api_gateway_integration" "api_lambda_integration" {
  integration_http_method = "POST"
  type = "AWS_PROXY"
  uri = aws_lambda_function.lambda_query_database.invoke_arn
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_rest_api.api_gateway.root_resource_id
  http_method = aws_api_gateway_method.api_method.http_method
}

resource "aws_api_gateway_model" "api_gateway_model" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  name = "myModel"
  description = "My Schema"
  content_type = "application/json"
  schema = jsonencode({
    "type" : "object",
    "properties" : {
      "agent_name" : {
        "type" : "string"
      },
      "consumer_number" : {
        "type" : "string"
      },
      "date_from" : {
        "type" : "string"
      },
      "date_to" : {
        "type" : "string"
      }
    }
  })
}