
# Would I do this under any circumstances if I had more than 3 hours?  
## No
terraform {
  required_version = "1.6.0"
  # Really you ought to clean this up and use a remote backend, but this is an interview and I spin this up A LOT, then run aws-nuke on the account
  backend "s3" {
    bucket = "meyerkev-terraform-state"
    key = "test.tfstate"
    region = "us-east-2"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = {
      Terraform = "true"
    }
  }
}

data "aws_caller_identity" "current" {}

output "identity" {
  value = data.aws_caller_identity.current
}
