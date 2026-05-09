# VPC submodule.
#
# Owns ONLY VPC infrastructure - no cluster-specific tags. The
# `kubernetes.io/cluster/<name>: shared` tag is added by the `cluster`
# submodule, so multiple clusters can share one VPC by adding their own copy
# of that tag without stepping on each other.

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs = var.availability_zones

  # 8-bit subnets per AZ, three tiers offset to leave room.
  public_subnets   = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets  = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 8, i + 4)]
  database_subnets = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 8, i + 8)]

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
}
