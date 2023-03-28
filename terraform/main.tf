terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.59.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
  profile = var.aws_profile
}

### Setup
data "aws_caller_identity" "current" {}
locals {
  account-id = data.aws_caller_identity.current.account_id
}

### VPC, subnets, and security groups
resource "aws_vpc" "db_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
  tags = {
    "Name" = "callsearch-vpc"
  }
}

resource "aws_vpc_endpoint" "endpoint_secrets" {
  vpc_id              = aws_vpc.db_vpc.id
  service_name        = "com.amazonaws.us-east-1.secretsmanager"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.security_group_endpoint.id]
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.lambda_private_1.id, aws_subnet.lambda_private_2.id]
}

resource "aws_subnet" "db_private_1" {
  vpc_id            = aws_vpc.db_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "db_private_1"
  }

}

resource "aws_subnet" "db_private_2" {
  vpc_id            = aws_vpc.db_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1c"
  tags = {
    "Name" = "db_private_2"
  }
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db-subnet-group"
  subnet_ids = [aws_subnet.db_private_1.id, aws_subnet.db_private_2.id]
  tags = {
    Name = "DB Subnet Group"
  }
}

resource "aws_subnet" "lambda_private_1" {
  vpc_id            = aws_vpc.db_vpc.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "us-east-1a"
  tags = {
    "Name" = "lambda_private_1"
  }
}

resource "aws_subnet" "lambda_private_2" {
  vpc_id            = aws_vpc.db_vpc.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "us-east-1c"
  tags = {
    "Name" = "lambda_private_2"
  }
}

resource "aws_security_group" "security_group_lambda" {
  name        = "security-group-lambda"
  description = "allow lambda outbound"
  vpc_id      = aws_vpc.db_vpc.id

}

resource "aws_security_group" "security_group_database" {
  name        = "security-group-database"
  description = "allow postgres inbound"
  vpc_id      = aws_vpc.db_vpc.id

}

resource "aws_security_group" "security_group_endpoint" {
  name        = "security-group-endpoint"
  description = "allow https inbound"
  vpc_id      = aws_vpc.db_vpc.id

}

resource "aws_vpc_security_group_ingress_rule" "allow_https_in" {
  security_group_id = aws_security_group.security_group_endpoint.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = -1
}

resource "aws_vpc_security_group_egress_rule" "allow_all_outbound" {
  security_group_id = aws_security_group.security_group_lambda.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = -1
}

resource "aws_vpc_security_group_ingress_rule" "allow_postgres_inbound" {
  security_group_id            = aws_security_group.security_group_database.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
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
  bucket_prefix = "recording-bucket"
}

resource "aws_s3_bucket_notification" "recording_bucket_notification" {
  bucket = aws_s3_bucket.recording_bucket.id
  topic {
    topic_arn = aws_sns_topic.new_object_topic.arn
    events    = ["s3:ObjectCreated:*"]
  }
}


resource "aws_sns_topic" "new_object_topic" {
  name = "new_object_topic"
}

resource "aws_sns_topic_policy" "topic_allow_s3_publish" {
  arn    = aws_sns_topic.new_object_topic.arn
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
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    effect = "Allow"
    resources = [
      aws_sns_topic.new_object_topic.arn
    ]
  }
}


### Lambda Query Database
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowSNSExecute"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_update_database.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.new_object_topic.arn
}

data "aws_iam_policy_document" "data_lambda_execution_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
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
  type        = "zip"
  source_dir  = "../lambda_db_update"
  output_path = "../lambda_update_db.zip"
}

resource "aws_lambda_function" "lambda_update_database" {
  filename      = data.archive_file.lambda_update_database.output_path
  handler       = "lambda_update_db.lambda_handler"
  function_name = "lambda_update_database"
  runtime       = "python3.9"
  timeout       = 30
  memory_size   = 1024
  source_code_hash = data.archive_file.lambda_update_database.output_base64sha256
  vpc_config {
    subnet_ids         = [aws_subnet.lambda_private_1.id, aws_subnet.lambda_private_2.id]
    security_group_ids = [aws_security_group.security_group_lambda.id]
  }
  environment {
    variables = {
      "DATABASE_HOST" = aws_rds_cluster.postgresql.endpoint,
      "DATABASE_PORT" = aws_rds_cluster.postgresql.port,
      "DATABASE_NAME" = aws_rds_cluster.postgresql.database_name
    }
  }
  role = aws_iam_role.lambda_execution_role.arn

}

data "archive_file" "lambda_create_tables" {
  type        = "zip"
  source_dir  = "../lambda_create_tables"
  output_path = "../lambda_create_tables.zip"
}

resource "aws_lambda_function" "lambda_create_tables" {
  filename      = data.archive_file.lambda_create_tables.output_path
  handler       = "createTable.lambda_handler"
  function_name = "lambda_create_tables"
  runtime       = "python3.9"
  memory_size   = 1024
  timeout       = 30
  vpc_config {
    subnet_ids         = [aws_subnet.lambda_private_1.id, aws_subnet.lambda_private_2.id]
    security_group_ids = [aws_security_group.security_group_lambda.id]
  }
  role = aws_iam_role.lambda_execution_role.arn
  source_code_hash = data.archive_file.lambda_create_tables.output_base64sha256  
}

resource "aws_lambda_invocation" "create_tables" {
  ##This should only run once after the database is created.
  ##If it needs to be run again, change one of the key values. 
  ##The key values have no affect on the function but will trigger it to run.
  function_name = aws_lambda_function.lambda_create_tables.function_name

  input = jsonencode({
    key1 = "value2"
    key2 = "value2"
  })
  depends_on = [
    aws_rds_cluster.postgresql,
    aws_rds_cluster_instance.instance1,
    aws_secretsmanager_secret_version.database_name_value,
    aws_secretsmanager_secret_version.database_password_value,
    aws_secretsmanager_secret_version.database_endpoint_value,
    aws_secretsmanager_secret_version.database_creds_value,
    aws_secretsmanager_secret_version.database_user_value
  ]
}

locals {
  lambda_create_tables_result = jsondecode(aws_lambda_invocation.create_tables.result)
  lambda_create_tables_message = jsondecode(aws_lambda_invocation.create_tables.result)
}

output "create_table_result_entry" {
  value = "${local.lambda_create_tables_result.statusCode}: ${local.lambda_create_tables_message.body}"
}

data "archive_file" "lambda_get_agents" {
  type        = "zip"
  source_dir  = "../lambda_get_agents"
  output_path = "../lambda_get_agents.zip"
}

resource "aws_lambda_function" "lambda_get_agents" {
  filename      = data.archive_file.lambda_get_agents.output_path
  handler       = "lambda_get_agents.lambda_handler"
  function_name = "lambda_get_agents"
  runtime       = "python3.9"
  timeout       = 30
  memory_size   = 1024
    source_code_hash = data.archive_file.lambda_get_agents.output_base64sha256
  vpc_config {
    subnet_ids         = [aws_subnet.lambda_private_1.id, aws_subnet.lambda_private_2.id]
    security_group_ids = [aws_security_group.security_group_lambda.id]
  }
    environment {
      variables = {
        "DATABASE_HOST" = aws_rds_cluster.postgresql.endpoint,
        "DATABASE_PORT" = aws_rds_cluster.postgresql.port,
        "DATABASE_NAME" = aws_rds_cluster.postgresql.database_name
      }
  }
  role = aws_iam_role.lambda_execution_role.arn
}

resource "aws_lambda_permission" "allow_api_gateway_get_agent" {
  statement_id  = "AllowApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_get_agents.function_name
  principal     = "apigateway.amazonaws.com"
  # source_arn    = "${aws_api_gateway_rest_api.api_gateway.arn}/*/*"
  source_arn = "${aws_api_gateway_deployment.api_gateway_deployment.execution_arn}*/${local.get_agent_api_method}/${local.get_agent_api_resource}"
  depends_on = [
    aws_api_gateway_method.api_method,
    aws_api_gateway_method.get_agents_method,
    aws_api_gateway_method.get_url_method,
    aws_api_gateway_deployment.api_gateway_deployment
  ]
}

locals {
  get_agent_api_method = aws_api_gateway_method.get_agents_method.http_method
  get_agent_api_resource = aws_api_gateway_resource.get_agents_resource.path_part
}

### Lambda create presigned URL
data "aws_iam_policy_document" "lambda_execution_role_s3_data" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_s3_policy_data" {
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
      "s3:GetObject"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "lambda_s3_role" {
  name               = "lambda_execution_role_s3"
  assume_role_policy = data.aws_iam_policy_document.lambda_execution_role_s3_data.json
}

resource "aws_iam_policy" "lambda_s3_policy" {
  name        = "lambda_s3_getObject"
  path        = "/"
  description = "IAM policy for lambda accessing s3"
  policy      = data.aws_iam_policy_document.lambda_s3_policy_data.json
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.lambda_s3_role.id
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

data "archive_file" "lambda_s3" {
  type        = "zip"
  source_dir  = "../lambda_get_url"
  output_path = "../lambda_get_url.zip"
}

resource "aws_lambda_function" "lambda_s3" {
  filename      = data.archive_file.lambda_s3.output_path
  handler       = "get_url.lambda_handler"
  function_name = "lambda_get_url"
  runtime       = "python3.9"
  timeout       = 30
  environment {
    variables = {
      "BUCKET_NAME" = aws_s3_bucket.recording_bucket.id
    }
  }
  role = aws_iam_role.lambda_s3_role.arn
}

resource "aws_lambda_permission" "allow_api_gateway_get_url" {
  statement_id  = "AllowApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_s3.function_name
  principal     = "apigateway.amazonaws.com"
  # source_arn    = "${aws_api_gateway_rest_api.api_gateway.arn}/*/*"
  source_arn = "${aws_api_gateway_deployment.api_gateway_deployment.execution_arn}*/${aws_api_gateway_method.get_url_method.http_method}/${aws_api_gateway_resource.get_url_resource.path_part}"
  depends_on = [
    aws_api_gateway_method.api_method,
    aws_api_gateway_method.get_agents_method,
    aws_api_gateway_method.get_url_method
  ]
}


### Database
resource "aws_rds_cluster" "postgresql" {
  cluster_identifier                  = "aurora-cluster-demo"
  engine                              = "aurora-postgresql"
  database_name                       = "callsearch"
  master_username                     = var.database_username
  master_password                     = var.database_password
  backup_retention_period             = 5
  preferred_backup_window             = "07:00-09:00"
  db_subnet_group_name                = aws_db_subnet_group.db_subnet_group.id
  vpc_security_group_ids              = [aws_security_group.security_group_database.id]
  skip_final_snapshot                 = true
  iam_database_authentication_enabled = false
  backtrack_window                    = 0
  deletion_protection                 = false
  enabled_cloudwatch_logs_exports     = []
  # iops                                = 0
  tags                                = null
}

resource "aws_rds_cluster_instance" "instance1" {
  cluster_identifier = aws_rds_cluster.postgresql.id
  instance_class     = "db.t3.medium"
  engine             = aws_rds_cluster.postgresql.engine
  engine_version     = aws_rds_cluster.postgresql.engine_version
}


resource "aws_secretsmanager_secret" "database_creds" {
  description             = "User and password of Database"
  name                    = "DatabaseCreds"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_creds_value" {
  secret_id     = aws_secretsmanager_secret.database_creds.id
  secret_string = jsonencode({username="${aws_rds_cluster.postgresql.master_username}",password="${aws_rds_cluster.postgresql.master_password}"})
}


resource "aws_secretsmanager_secret" "database_endpoint" {
  description             = "Connection Endpoint of Database"
  name                    = "DatabaseEndpoint"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_endpoint_value" {
  secret_id     = aws_secretsmanager_secret.database_endpoint.id
  secret_string = aws_rds_cluster.postgresql.endpoint
}

resource "aws_secretsmanager_secret" "database_port" {
  description             = "Connection Endpoint of Database"
  name                    = "DatabasePort"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_port_value" {
  secret_id     = aws_secretsmanager_secret.database_port.id
  secret_string = aws_rds_cluster.postgresql.port
}

resource "aws_secretsmanager_secret" "database_user" {
  description             = "Database user name"
  name                    = "DatabaseUser"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_user_value" {
  secret_id     = aws_secretsmanager_secret.database_user.id
  secret_string = aws_rds_cluster.postgresql.master_username
}

resource "aws_secretsmanager_secret" "database_password" {
  description             = "Database password"
  name                    = "DatabaseMasterPassword"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_password_value" {
  secret_id     = aws_secretsmanager_secret.database_password.id
  secret_string = aws_rds_cluster.postgresql.master_password
}

resource "aws_secretsmanager_secret" "database_name" {
  description             = "Database name"
  name                    = "DatabaseName"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "database_name_value" {
  secret_id     = aws_secretsmanager_secret.database_name.id
  secret_string = aws_rds_cluster.postgresql.database_name
}


### Web Bucket
resource "aws_s3_bucket" "web_bucket" {
  bucket_prefix = "web-bucket"
}

resource "aws_s3_bucket_website_configuration" "web_config" {
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

# Upload files to web bucket
resource "aws_s3_object" "search" {

  bucket = aws_s3_bucket.web_bucket.id
  key    = "search.html"
  acl    = "public-read"
  source = "../www_root/search.html"
  etag = filemd5("../www_root/search.html")
  content_type = "text/html"
}

resource "aws_s3_object" "download_icon" {

  bucket = aws_s3_bucket.web_bucket.id
  key    = "file_download.png"
  acl    = "public-read"
  source = "../www_root/file_download.png"
  etag = filemd5("../www_root/file_download.png")
  content_type = "image/png"
}

resource "aws_s3_object" "script" {

  bucket = aws_s3_bucket.web_bucket.id
  key    = "main.js"
  acl    = "public-read"
  source = "../www_root/main.js"
  etag = filemd5("../www_root/main.js")
  content_type = "application/javascript"
}

resource "aws_s3_object" "css" {

  bucket = aws_s3_bucket.web_bucket.id
  key    = "main.css"
  acl    = "public-read"
  source = "../www_root/main.css"
  etag = filemd5("../www_root/main.css")
  content_type = "text/css"
}

##Cloudfront
resource "aws_acm_certificate" "app" {
  domain_name       = var.base_domain_name
  subject_alternative_names = ["${var.app_domain_name}.${var.base_domain_name}","${var.auth_domain_name}.${var.base_domain_name}"]
  validation_method = "DNS"
}

data "aws_route53_zone" "my_zone" {
  name         = var.route53_zone_name
  private_zone = false
}

resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.my_zone.zone_id
}

resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}

locals {
  s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.web_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
    origin_id                = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = false
  comment             = "Origin for call search"
  default_root_object = "search.html"

  # logging_config {
  #   include_cookies = false
  #   bucket          = "mylogs.s3.amazonaws.com"
  #   prefix          = "myprefix"
  # }
  depends_on = [
    aws_acm_certificate.app,
    aws_acm_certificate_validation.cert_validation
  ]

  aliases = ["${var.app_domain_name}.${var.base_domain_name}"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn = aws_acm_certificate.app.arn
    ssl_support_method = "sni-only"
  }
}

resource "aws_cloudfront_origin_access_control" "default" {
  name                              = "example"
  description                       = "Example Policy"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_route53_record" "app_cname" {
  zone_id = data.aws_route53_zone.my_zone.zone_id
  name = "${var.app_domain_name}.${var.base_domain_name}"
  type = "CNAME"
  ttl = 300
  records = [aws_cloudfront_distribution.s3_distribution.domain_name]
  
}


### Transfer Server
resource "aws_transfer_server" "call_upload" {
  endpoint_type          = "PUBLIC"
  protocols              = ["SFTP"]
  identity_provider_type = "SERVICE_MANAGED"
  tags = {
    Name = "Call Upload"
  }
}

resource "aws_transfer_user" "upload_user" {
  server_id           = aws_transfer_server.call_upload.id
  user_name           = "upload_user"
  home_directory      = "/${aws_s3_bucket.recording_bucket.id}"
  home_directory_type = "PATH"
  role                = aws_iam_role.S3TransferUser.arn
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
    sid    = "HomeDirAccess"
    effect = "Allow"
    actions = [
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
  name   = "S3TransferRole"
  role   = aws_iam_role.S3TransferUser.id
  policy = data.aws_iam_policy_document.S3PutObject.json
}


### Lambda Query Database
data "archive_file" "lambda_query_database" {
  type        = "zip"
  source_dir  = "../lambda_db_query"
  output_path = "../lambda_db_query.zip"
}

resource "aws_lambda_function" "lambda_query_database" {
  filename      = data.archive_file.lambda_query_database.output_path
  handler       = "lambda_db_query.lambda_handler"
  function_name = "lambda_query_database"
  runtime       = "python3.9"
  vpc_config {
    subnet_ids         = [aws_subnet.lambda_private_1.id, aws_subnet.lambda_private_2.id]
    security_group_ids = [aws_security_group.security_group_lambda.id]
  }
  environment {
    variables = {
      "DATABASE_HOST" = aws_rds_cluster.postgresql.endpoint,
      "DATABASE_PORT" = aws_rds_cluster.postgresql.port,
      "DATABASE_NAME" = aws_rds_cluster.postgresql.database_name
    }
  }
  role    = aws_iam_role.lambda_execution_role.arn
  timeout = 30
  memory_size = 1024
    source_code_hash = data.archive_file.lambda_query_database.output_base64sha256
}

locals {
  api_method = aws_api_gateway_method.api_method.http_method
  api_resource = aws_api_gateway_resource.query_resource.path_part
}

resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_query_database.function_name
  principal     = "apigateway.amazonaws.com"
  # source_arn    = "${aws_api_gateway_rest_api.api_gateway.arn}/*/*"
  source_arn = "${aws_api_gateway_deployment.api_gateway_deployment.execution_arn}*/${local.api_method}/${local.api_resource}"
}

### API Gateway Settings
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "ApiQueryDatabase"
  description = "API Gateway to query database"
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name = "cognito_authorizer"
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  type = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  depends_on = [
    aws_cognito_user_pool.user_pool
  ]
}

resource "aws_api_gateway_stage" "api_gateway_stage" {
  deployment_id = aws_api_gateway_deployment.api_gateway_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  stage_name    = "prod"
  description   = "Added url resource"
  depends_on    = [aws_api_gateway_deployment.api_gateway_deployment]
}

resource "aws_api_gateway_deployment" "api_gateway_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  description = "Deployed at ${timestamp()}"
  # stage_name = "prod"
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api_gateway.body))
  }

  lifecycle {
    create_before_destroy = true
  }
  depends_on = [
    aws_api_gateway_method.api_method,
    aws_api_gateway_method.get_agents_method,
    aws_api_gateway_method.get_url_method,
    aws_api_gateway_authorizer.cognito_authorizer,
    aws_api_gateway_integration.api_lambda_integration,
    aws_api_gateway_integration.api_lambda_get_agents,
    aws_api_gateway_integration.api_lambda_integration_s3,
    aws_api_gateway_gateway_response.unauthorized
  ]
}

## Database query resource/method/integration
resource "aws_api_gateway_resource" "query_resource" {
    path_part     = "query"
    parent_id     = "${aws_api_gateway_rest_api.api_gateway.root_resource_id}"
    rest_api_id   = "${aws_api_gateway_rest_api.api_gateway.id}"
}

resource "aws_api_gateway_method" "api_method" {
  authorization   = "COGNITO_USER_POOLS"
  authorizer_id   = aws_api_gateway_authorizer.cognito_authorizer.id
  http_method     = "POST"
  rest_api_id     = aws_api_gateway_rest_api.api_gateway.id
  resource_id     = aws_api_gateway_resource.query_resource.id
  request_models  = {"application/json": aws_api_gateway_model.api_gateway_model.name}
}

resource "aws_api_gateway_integration" "api_lambda_integration" {
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_query_database.invoke_arn
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.query_resource.id
  http_method             = aws_api_gateway_method.api_method.http_method
}

resource "aws_api_gateway_model" "api_gateway_model" {
  rest_api_id  = aws_api_gateway_rest_api.api_gateway.id
  name         = "myModel"
  description  = "My Schema"
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

### API Gateway Get Agents resource/method/integration
resource "aws_api_gateway_integration" "api_lambda_get_agents" {
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_get_agents.invoke_arn
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.get_agents_resource.id
  http_method             = aws_api_gateway_method.get_agents_method.http_method
}

resource "aws_api_gateway_resource" "get_agents_resource" {
  path_part     = "agents"
  parent_id     = "${aws_api_gateway_rest_api.api_gateway.root_resource_id}"
  rest_api_id   = "${aws_api_gateway_rest_api.api_gateway.id}"
}

resource "aws_api_gateway_method" "get_agents_method" {
  authorization   = "COGNITO_USER_POOLS"
  authorizer_id   = aws_api_gateway_authorizer.cognito_authorizer.id
  http_method     = "GET"
  rest_api_id     = aws_api_gateway_rest_api.api_gateway.id
  resource_id     = aws_api_gateway_resource.get_agents_resource.id
}

resource "aws_api_gateway_gateway_response" "unauthorized" {
  rest_api_id     = aws_api_gateway_rest_api.api_gateway.id
  status_code     = "401"
  response_type   = "UNAUTHORIZED"
  response_templates = {
    "application/json" = "{\"message\":$context.error.messageString}"
  }
  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin" = "'*'"
  }
}

## Resource and method for getting presigned URL
resource "aws_api_gateway_resource" "get_url_resource" {
  path_part     = "get_url"
  parent_id     = "${aws_api_gateway_rest_api.api_gateway.root_resource_id}"
  rest_api_id   = "${aws_api_gateway_rest_api.api_gateway.id}"
}

resource "aws_api_gateway_model" "api_gateway_model_s3" {
  rest_api_id  = aws_api_gateway_rest_api.api_gateway.id
  name         = "s3Model"
  description  = "Model to take object_name from api gateway"
  content_type = "application/json"
  schema = jsonencode({
    "type" : "object",
    "properties" : {
      "object_name" : {
        "type" : "string"
      }
    }
  })
}

resource "aws_api_gateway_method" "get_url_method" {
  authorization   = "COGNITO_USER_POOLS"
  authorizer_id   = aws_api_gateway_authorizer.cognito_authorizer.id
  http_method     = "POST"
  rest_api_id     = aws_api_gateway_rest_api.api_gateway.id
  resource_id     = aws_api_gateway_resource.get_url_resource.id
  request_models  = {"application/json": aws_api_gateway_model.api_gateway_model_s3.name}
}

resource "aws_api_gateway_integration" "api_lambda_integration_s3" {
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_s3.invoke_arn
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.get_url_resource.id
  http_method             = aws_api_gateway_method.get_url_method.http_method
}

#cors support

module "api-gateway-enable-cors" {
  source  = "squidfunk/api-gateway-enable-cors/aws"
  version = "0.3.3"
  api_id          = "${aws_api_gateway_rest_api.api_gateway.id}"
  api_resource_id = "${aws_api_gateway_resource.query_resource.id}"
}

module "api-gateway-enable-cors-get-agents" {
  source  = "squidfunk/api-gateway-enable-cors/aws"
  version = "0.3.3"
  api_id          = "${aws_api_gateway_rest_api.api_gateway.id}"
  api_resource_id = "${aws_api_gateway_resource.get_agents_resource.id}"
  # allow_headers = ["cognito-auth-token"]
}

module "api-gateway-enable-cors-get-url" {
  source  = "squidfunk/api-gateway-enable-cors/aws"
  version = "0.3.3"
  api_id          = "${aws_api_gateway_rest_api.api_gateway.id}"
  api_resource_id = "${aws_api_gateway_resource.get_url_resource.id}"
}

### Cognito Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "callsearch_pool"
  mfa_configuration  = "OFF"
  admin_create_user_config {
    allow_admin_create_user_only = true
  }
  depends_on = [
    aws_acm_certificate.app,
    aws_acm_certificate_validation.cert_validation
  ]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain          = "${var.auth_domain_name}.${var.base_domain_name}"
  certificate_arn = aws_acm_certificate.app.arn
  user_pool_id    = aws_cognito_user_pool.user_pool.id
  depends_on = [
    aws_acm_certificate.app,
    aws_acm_certificate_validation.cert_validation
  ]
}

resource "aws_cognito_user_pool_client" "client" {
  name = "web-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret                       = false
  callback_urls                         = ["https://${var.app_domain_name}.${var.base_domain_name}"]
  default_redirect_uri                  = "https://${var.app_domain_name}.${var.base_domain_name}"
  allowed_oauth_flows_user_pool_client  = true
  allowed_oauth_flows                   = ["code", "implicit"]
  allowed_oauth_scopes                  = ["email", "openid"]
  supported_identity_providers          = ["COGNITO"]
  explicit_auth_flows                   = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
  depends_on = [
    aws_acm_certificate.app,
    aws_acm_certificate_validation.cert_validation
  ]  
}

resource "aws_cognito_user" "example" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  username     = "jlake@sentinel.com"
  attributes = {
    email          = "jlake@sentinel.com"
    email_verified = true
  }
  password = var.cognito_user_password
}

resource "aws_route53_record" "auth-cognito-A" {
  name    = aws_cognito_user_pool_domain.main.domain
  type    = "A"
  zone_id = data.aws_route53_zone.my_zone.zone_id
  alias {
    evaluate_target_health = false
    name    = aws_cognito_user_pool_domain.main.cloudfront_distribution
    zone_id = aws_cognito_user_pool_domain.main.cloudfront_distribution_zone_id
  }
}

##Cognito requires an A record at the apex of the domain, even if it points to nothing or is not needed
# resource "aws_route53_record" "domain-apex" {
#   type = "A"
#   name = var.route53_zone_name
#   zone_id = data.aws_route53_zone.my_zone.zone_id
#   records = ["192.168.1.1"]
# }

### Outputs
output "api_url" {
  value = aws_api_gateway_stage.api_gateway_stage.invoke_url
}

output "recording_bucket_name" {
  value = aws_s3_bucket.recording_bucket.id
}

output "web_bucket_name" {
  value = aws_s3_bucket.web_bucket.id
}

output "web_bucket_url" {
  value = aws_s3_bucket_website_configuration.web_config.website_endpoint
}

output "sftp_host" {
  value = aws_transfer_server.call_upload.endpoint
}

output "sftp_id" {
  value = aws_transfer_server.call_upload.id
}

