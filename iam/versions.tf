terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project     = "tochallenge-belo"
      managed_by  = "terraform"
      module      = "users-managment-aws"
      environment = var.environment
    }
  }
}
