# VPC submodule.
#
# Owns ONLY VPC infrastructure - no cluster-specific tags. The
# `kubernetes.io/cluster/<name>: shared` tag is added by the `cluster`
# submodule, so multiple clusters can share one VPC by adding their own copy
# of that tag without stepping on each other.

locals {
  # Count how many of the three mutually-exclusive AZ inputs are set.
  # The precondition below errors if more than one is supplied.
  _az_inputs_set = (
    (var.availability_zones != null ? 1 : 0)
    + (var.availability_zone_letters != null ? 1 : 0)
    + (var.availability_zone_count != null ? 1 : 0)
  )

  # Precedence: explicit list > letters > count > built-in default (a, b, c).
  _az_letters = (
    var.availability_zone_letters != null ? var.availability_zone_letters :
    var.availability_zone_count != null ? slice(["a", "b", "c", "d", "e", "f"], 0, var.availability_zone_count) :
    var.availability_zones != null ? null :
    ["a", "b", "c"]
  )

  availability_zones = (
    var.availability_zones != null ? var.availability_zones :
    [for l in local._az_letters : "${var.region}${l}"]
  )
}

# Validates the AZ inputs at plan time. terraform_data is a no-op resource
# whose only purpose here is to host preconditions that need to look at
# multiple variables / locals at once (variable validation can't reference
# other variables on Terraform < 1.9).
resource "terraform_data" "az_validation" {
  lifecycle {
    precondition {
      condition     = local._az_inputs_set <= 1
      error_message = "Set at most one of availability_zones, availability_zone_letters, availability_zone_count (got ${local._az_inputs_set})."
    }
    precondition {
      condition     = var.availability_zones != null || var.region != null
      error_message = "var.region is required when availability_zone_letters or availability_zone_count is used (so letters can be expanded into full AZ names)."
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs = local.availability_zones

  # 8-bit subnets per AZ, three tiers offset to leave room.
  public_subnets   = [for i, az in local.availability_zones : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets  = [for i, az in local.availability_zones : cidrsubnet(var.vpc_cidr, 8, i + 4)]
  database_subnets = [for i, az in local.availability_zones : cidrsubnet(var.vpc_cidr, 8, i + 8)]

  enable_dns_hostnames = true

  # NAT - expensive in steady state but required for private nodes to pull
  # images and reach the EKS control plane.
  enable_nat_gateway      = var.enable_nat_gateway
  single_nat_gateway      = var.single_nat_gateway
  one_nat_gateway_per_az  = var.one_nat_gateway_per_az
  enable_vpn_gateway      = var.enable_vpn_gateway
  map_public_ip_on_launch = var.map_public_ip_on_launch

  # Generic LB role tags only - safe to share across clusters. The
  # per-cluster `kubernetes.io/cluster/<name>: shared` tag is added by the
  # `cluster` submodule via `aws_ec2_tag` resources.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  depends_on = [terraform_data.az_validation]
}
