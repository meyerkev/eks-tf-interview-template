# Per-cluster subnet tagging. Each cluster owns its own copy of the
# `kubernetes.io/cluster/<name>: shared` tag, so multiple clusters can share
# one VPC without stepping on each other's tags. When a cluster is destroyed,
# only its tags go away.
#
# Keying for_each by index (not by id) is required when the subnet IDs come
# from a sibling module - terraform can't enumerate `toset(list)` keys when
# the list values are computed at apply time, but it CAN handle a map whose
# keys are derived from the (statically-known) list length.
resource "aws_ec2_tag" "public_subnet_cluster" {
  for_each    = { for i, id in var.public_subnet_ids : tostring(i) => id }
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "shared"
}

resource "aws_ec2_tag" "private_subnet_cluster" {
  for_each    = { for i, id in var.private_subnet_ids : tostring(i) => id }
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "shared"
}

# EKS module v21+:
# - The `aws-auth` submodule was removed; we use access entries (the EKS API
#   native auth) inline below instead.
# - Most variables previously prefixed with `cluster_` had the prefix
#   stripped (cluster_name -> name, cluster_endpoint_public_access ->
#   endpoint_public_access, cluster_addons -> addons, etc.).
# - Default AMI is AL2023; SSM Session Manager replaces SSH for shell access.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.cluster_k8s_version

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

  # `before_compute = true` is critical for vpc-cni and kube-proxy: in v21 the
  # default install order is post-node-group, but managed node groups won't
  # transition to ACTIVE until the kubelets mark Ready, and they can't go
  # Ready without CNI + kube-proxy. CoreDNS can wait until after compute
  # because it just needs a Ready node to schedule on.
  addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    kube-proxy = {
      most_recent    = true
      before_compute = true
    }
    coredns = {
      most_recent = true
    }
  }

  vpc_id = var.vpc_id
  # Place the cluster ENIs and node group in either the public or private
  # subnet set. Public subnets keep the interview cluster friction-free (no
  # VPN required); production should use private subnets, which works as
  # long as the supplied private subnets have NAT egress so nodes can pull
  # images and reach the EKS control plane.
  subnet_ids = var.public_nodes ? var.public_subnet_ids : var.private_subnet_ids

  # Grant the interviewee admin on the cluster via an EKS access entry.
  # This replaces the old aws-auth ConfigMap mapping.
  access_entries = var.interviewee_name != null ? {
    interviewee = {
      principal_arn = aws_iam_user.interviewee[0].arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  } : {}

  # NOTE: v21 dropped `eks_managed_node_group_defaults`; values that used to
  # live there now have to be inlined per node group.
  eks_managed_node_groups = {
    default_node_group = {
      ami_type       = local.ami_type
      instance_types = [local.eks_node_instance_type]

      iam_role_attach_cni_policy = true
      # Allow `aws ssm start-session` on nodes - replaces the SSH path the
      # v20 template carried via remote_access + open SG.
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }

      min_size     = var.min_nodes
      max_size     = var.max_nodes
      desired_size = var.desired_nodes

      disk_size = 50

      tags = {
        "k8s.io/cluster-autoscaler/enabled"             = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      }
    }
  }

  security_group_additional_rules = {
    eks_cluster = {
      type        = "ingress"
      description = "Never do this in production"
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}

resource "aws_ssm_parameter" "oidc_provider" {
  name  = "/eks/${var.cluster_name}/oidc_provider"
  type  = "String"
  value = module.eks.oidc_provider_arn
}
