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
    default = "jlake.aws.sentinel.com"
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