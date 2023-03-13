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
    "Name" = "lambd_private_2"
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
  handler       = "lambda_function.lambda_handler"
  function_name = "lambda_update_database"
  runtime       = "python3.9"
  timeout       = 30
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
  tags                                = null
}

resource "aws_rds_cluster_instance" "instance1" {
  cluster_identifier = aws_rds_cluster.postgresql.id
  instance_class     = "db.t3.medium"
  engine             = aws_rds_cluster.postgresql.engine
  engine_version     = aws_rds_cluster.postgresql.engine_version
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

# Upload an object
resource "aws_s3_object" "search" {

  bucket = aws_s3_bucket.web_bucket.id
  key    = "search.html"
  acl    = "public-read"
  source = "../www_root/search.html"
  etag = filemd5("../www_root/search.html")
  content_type = "text/html"
}

resource "aws_s3_object" "script" {

  bucket = aws_s3_bucket.web_bucket.id
  key    = "main.js"
  acl    = "public-read"
  source = "../www_root/main.js"
  etag = filemd5("../www_root/main.js")
  content_type = "application/javascript"
}

##Cloudfront

resource "aws_acm_certificate" "app" {
  domain_name       = "jlake.aws.sentinel.com"
  subject_alternative_names = ["app.jlake.aws.sentinel.com","auth.jlake.aws.sentinel.com"]
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
  filename      = data.archive_file.lambda_update_database.output_path
  handler       = "lambda_function.lambda_handler"
  function_name = "lambda_query_database"
  runtime       = "python3.9"
  vpc_config {
    subnet_ids         = [aws_subnet.lambda_private_1.id, aws_subnet.lambda_private_2.id]
    security_group_ids = [aws_security_group.security_group_lambda.id]
  }
  role    = aws_iam_role.lambda_execution_role.arn
  timeout = 30
}

locals {
  api_method = aws_api_gateway_method.api_method.http_method
  api_resource = aws_api_gateway_resource.cors_resource.path_part
}

resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_query_database.function_name
  principal     = "apigateway.amazonaws.com"
  # source_arn    = "${aws_api_gateway_rest_api.api_gateway.arn}/*/*"
  source_arn = "${aws_api_gateway_deployment.api_gateway_deployment.execution_arn}*/${local.api_method}/${local.api_resource}"
}

### API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "ApiQueryDatabase"
  description = "API Gateway to query database"
}

resource "aws_api_gateway_method" "api_method" {
  authorization   = "NONE"
  http_method     = "POST"
  rest_api_id     = aws_api_gateway_rest_api.api_gateway.id
  resource_id     = aws_api_gateway_resource.cors_resource.id
  request_models  = {"application/json": aws_api_gateway_model.api_gateway_model.name}
}

resource "aws_api_gateway_integration" "api_lambda_integration" {
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_query_database.invoke_arn
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.cors_resource.id
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


resource "aws_api_gateway_stage" "api_gateway_stage" {
  deployment_id = aws_api_gateway_deployment.api_gateway_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  stage_name    = "prod"
}

resource "aws_api_gateway_deployment" "api_gateway_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api_gateway.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}


#cors support
resource "aws_api_gateway_resource" "cors_resource" {
    path_part     = "query"
    parent_id     = "${aws_api_gateway_rest_api.api_gateway.root_resource_id}"
    rest_api_id   = "${aws_api_gateway_rest_api.api_gateway.id}"
}

resource "aws_api_gateway_method" "options_method" {
    rest_api_id   = "${aws_api_gateway_rest_api.api_gateway.id}"
    resource_id   = "${aws_api_gateway_resource.cors_resource.id}"
    http_method   = "OPTIONS"
    authorization = "NONE"
}

resource "aws_api_gateway_method_response" "options_200" {
    rest_api_id   = "${aws_api_gateway_rest_api.api_gateway.id}"
    resource_id   = "${aws_api_gateway_resource.cors_resource.id}"
    http_method   = "${aws_api_gateway_method.options_method.http_method}"
    status_code   = "200"
    response_models = {
        "application/json" = "Empty"
    }
    response_parameters = {
        "method.response.header.Access-Control-Allow-Headers" = true,
        "method.response.header.Access-Control-Allow-Methods" = true,
        "method.response.header.Access-Control-Allow-Origin" = true
    }
    depends_on = [aws_api_gateway_method.options_method]
}

resource "aws_api_gateway_integration" "options_integration" {
    rest_api_id   = "${aws_api_gateway_rest_api.api_gateway.id}"
    resource_id   = "${aws_api_gateway_resource.cors_resource.id}"
    http_method   = "${aws_api_gateway_method.options_method.http_method}"
    type          = "MOCK"
    depends_on = [aws_api_gateway_method.options_method]
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
    rest_api_id   = "${aws_api_gateway_rest_api.api_gateway.id}"
    resource_id   = "${aws_api_gateway_resource.cors_resource.id}"
    http_method   = "${aws_api_gateway_method.options_method.http_method}"
    status_code   = "${aws_api_gateway_method_response.options_200.status_code}"
    response_parameters = {
        "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
        "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
        "method.response.header.Access-Control-Allow-Origin" = "'*'"
    }
    depends_on = [aws_api_gateway_method_response.options_200]
}

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

