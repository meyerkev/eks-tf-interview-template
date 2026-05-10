# Minimal example: provision isolation for one tenant.
#
# In a real multi-tenant deployment, you would typically iterate:
#
#   module "tenants" {
#     source   = "../.."
#     for_each = {
#       acme    = { vpc_cidr = "10.10.0.0/16" }
#       globex  = { vpc_cidr = "10.20.0.0/16" }
#       initech = { vpc_cidr = "10.30.0.0/16", connectivity = "isolated" }
#     }
#
#     tenant_id    = each.key
#     vpc_cidr     = each.value.vpc_cidr
#     connectivity = lookup(each.value, "connectivity", "egress_only")
#   }

terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

module "tenant_acme" {
  source = "../.."

  tenant_id = "acme"
  vpc_cidr  = "10.10.0.0/16"

  extra_tags = {
    cost_center = "eng-platform"
    environment = "shared-dev"
    owner       = "platform-team@example.com"
  }
}

# Sample of how a downstream consumer (e.g. the tenant team's own
# Terraform) would use the boundary:
#
#   resource "aws_iam_role" "tenant_workload" {
#     name                 = "acme-workload"
#     permissions_boundary = module.tenant_acme.permissions_boundary_arn
#     tags                 = module.tenant_acme.required_resource_tags
#     assume_role_policy   = data.aws_iam_policy_document.assume.json
#   }
