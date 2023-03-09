terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 2.70.3"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}


#VPC, subnets, and security groups
resource "aws_vpc" "db_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = "true"
  enable_dns_hostnames = "true"
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

resource "aws_subnet" "lambda_private" {
  vpc_id = aws_vpc.db_vpc.id
  cidr_block = "10.0.12.0/24"
  availability_zone = "us-east-1a"  
}




#recording bucket, notifications and policies

resource "aws_s3_bucket_intelligent_tiering_configuration" "recording_bucket_tiering" {
  bucket = aws_s3_bucket.example.id
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

resource "aws_sns_topic_subscription" "new_object_lambda_target" {
  topic_arn = aws_sns_topic.new_object_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.update_database.arn
}

resource "aws_lambda_function" "new_object_lambda_function" {
  
}



#database
resource "aws_rds_cluster" "postgresql" {
  cluster_identifier      = "aurora-cluster-demo"
  engine                  = "aurora-postgresql"
  availability_zones      = ["us-east-1a", "us-east-1c"]
  database_name           = "callsearch"
  master_username         = "callsearch"
  master_password         = "password"
  backup_retention_period = 5
  preferred_backup_window = "07:00-09:00"
  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.id
}

resource "aws_rds_cluster_instance" "instance1" {
  cluster_identifier = aws_rds_cluster.postgresql.id
  instance_class     = "db.t3.medium"
  engine             = aws_rds_cluster.postgresql.engine
  engine_version     = aws_rds_cluster.postgresql.engine_version
}