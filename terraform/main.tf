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