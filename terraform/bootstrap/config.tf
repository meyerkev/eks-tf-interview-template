terraform {
  required_version = ">= 1.5.7"

  backend "s3" {
    bucket = "meyerkev-terraform-state"
    key    = "bootstrap-ecr.tfstate"
    region = "us-east-2"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}
