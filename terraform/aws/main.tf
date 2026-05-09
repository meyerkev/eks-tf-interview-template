# Single-cluster wrapper around the vpc/ + cluster/ submodules.
#
# This composition preserves the original "one apply, one cluster, one VPC,
# one state file" workflow that scripts/zero_to_hero.sh expects. For
# multi-cluster setups (N clusters in one VPC, separate state files), skip
# this wrapper and call vpc/ + cluster/ directly from your own root module
# - see README.md "Multi-cluster usage" for an example.

locals {
  availability_zones = ["${var.region}a", "${var.region}b", "${var.region}c"]
}

module "vpc" {
  source = "./vpc"

  vpc_name           = var.vpc_name == null ? "${var.cluster_name}-eks-vpc" : var.vpc_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = local.availability_zones
}

module "cluster" {
  source = "./cluster"

  cluster_name        = var.cluster_name
  cluster_k8s_version = var.cluster_k8s_version
  region              = var.region

  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  public_nodes       = var.public_nodes

  interviewee_name       = var.interviewee_name
  eks_node_instance_type = var.eks_node_instance_type
  target_architecture    = var.target_architecture
  min_nodes              = var.min_nodes
  max_nodes              = var.max_nodes
  desired_nodes          = var.desired_nodes
}
