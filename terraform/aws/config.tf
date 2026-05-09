# Would I do this under any circumstances if I had more than 3 hours?
## No
terraform {
  # EKS module v21 requires >= 1.5.7; pin to current Terraform 1.15 series.
  required_version = ">= 1.5.7"

  backend "s3" {
    bucket = "meyerkev-terraform-state"
    key    = "test-interview.tfstate"
    region = "us-east-2"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.2"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Terraform = "true"
    }
  }
}
