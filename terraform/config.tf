
# Would I do this under any circumstances if I had more than 3 hours?  
## No
terraform {
  required_version = "1.4.6"
  backend "local" {
    path = "test-interview.tfstate"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
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
