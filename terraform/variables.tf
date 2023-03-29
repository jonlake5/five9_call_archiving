variable "days_until_tiering" {
    type = number
    default = 90
}

variable "my_region" {
    type = string
    default = "us-east-1"
}

variable "base_domain_name" {
    type = string
}

variable "auth_domain_name" {
    type = string
    default = "auth"
}

variable "app_domain_name" { 
    type = string
    default = "app"
}

variable "route53_zone_name" {
    type = string
}

variable "cognito_user_password" {
    type = string
}

variable "database_username" {
    description = "Database username"
    type = string
    # sensitive = true
}

variable "database_password" {
    description = "Database password"
    type = string
    sensitive = true
}

variable "aws_profile" {
    description = "AWS CLI profile to use"
    type = string
}

variable "iam_user" {
    description = "username of IAM user to upload S3 files"
    type = string
}