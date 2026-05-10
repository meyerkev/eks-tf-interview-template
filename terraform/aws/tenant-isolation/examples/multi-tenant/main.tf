# Multi-tenant example: provision N isolated tenants in one apply via
# `for_each`. This is the actual deployment shape for a SaaS platform -
# `examples/basic/` is the minimum viable usage; this is closer to what
# real callers do.
#
# Each tenant gets its own VPC + IAM boundary; tenants are network- and
# IAM-isolated from each other by design (different VPCs, different SG
# IDs, different boundaries with different tag values in the allow
# condition).
#
# Things to notice in this example:
#   - The tenants are described as a single map; one source of truth.
#   - Different `connectivity` modes per tenant (initech is air-gapped).
#   - CIDRs are caller-managed and non-overlapping. Production should
#     allocate from VPC IPAM so this isn't an error-prone manual job.
#   - Outputs aggregate across tenants for convenience.

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

locals {
  tenants = {
    acme = {
      vpc_cidr     = "10.10.0.0/16"
      connectivity = "egress_only"
      cost_center  = "eng-platform"
    }
    globex = {
      vpc_cidr     = "10.20.0.0/16"
      connectivity = "egress_only"
      cost_center  = "eng-data"
    }
    initech = {
      # Air-gapped tenant - no NAT, no internet egress. Workloads here
      # can only reach AWS services via VPC endpoints (which a real
      # deployment would provision via a sibling module).
      vpc_cidr     = "10.30.0.0/16"
      connectivity = "isolated"
      cost_center  = "eng-compliance"
    }
  }
}

module "tenants" {
  source   = "../.."
  for_each = local.tenants

  tenant_id    = each.key
  vpc_cidr     = each.value.vpc_cidr
  connectivity = each.value.connectivity

  extra_tags = {
    cost_center = each.value.cost_center
    environment = "shared-dev"
  }
}
