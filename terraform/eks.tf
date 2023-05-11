locals {
  vpc_cidr = "10.0.0.0/16"
  availability_zones = ["${var.region}a", "${var.region}b", "${var.region}c"]
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "4"

  name = var.vpc_name
  cidr = local.vpc_cidr

  azs             = local.availability_zones

  # TODO: Some regions have more than 4 AZ's
  public_subnets = [for i, az in local.availability_zones : cidrsubnet(local.vpc_cidr, 8, i)]
  private_subnets = [for i, az in local.availability_zones : cidrsubnet(local.vpc_cidr, 8, i + 4)]
  database_subnets = [for i, az in local.availability_zones : cidrsubnet(local.vpc_cidr, 8, i + 8)]

  enable_dns_hostnames = true

  # Enable NAT Gateway
  # Expensive, but a requirement 
  enable_nat_gateway = true
  single_nat_gateway = true
  one_nat_gateway_per_az = false
  enable_vpn_gateway = true
  map_public_ip_on_launch = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

//*
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.26"

  cluster_endpoint_public_access  = true
  create_iam_role = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  vpc_id = module.vpc.vpc_id
  # In production, it is strongly preferred to use private subnets, but this reduces friction in the interview
  # No VPN required!
  subnet_ids = module.vpc.public_subnets

  eks_managed_node_group_defaults = {
    # I develop on ARM mostly these days (huzzah for the M1), so I'm going to use ARM instances
    ami_type       = /*"AL2_ARM_64"  # */ "AL2_x86_64"
    instance_types = /* ["m6g.large"]  # */ ["m6i.large"]
    iam_role_attach_cni_policy = true
  }

  eks_managed_node_groups = {
    # Default node group - as provided by AWS EKS
    default_node_group = {
      # By default, the module creates a launch template to ensure tags are propagated to instances, etc.,
      # so we need to disable it to use the default template provided by the AWS EKS managed node group service
      use_custom_launch_template = false

      disk_size = 50   # Large enough to work with by default when under time pressure

      # Remote access cannot be specified with a launch template
      remote_access = {
        ec2_ssh_key               = module.key_pair.key_pair_name
        source_security_group_ids = [aws_security_group.remote_access.id]
      }
    }
  }
  cluster_security_group_additional_rules = {
    eks_cluster = {
      type = "ingress"
      description              = "Never do this in production"
      from_port                = 0
      to_port                  = 65535
      protocol                 = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}
//*/

module "key_pair" {
  source  = "terraform-aws-modules/key-pair/aws"
  version = "~> 2.0"

  key_name_prefix    = "meyerkev-local"
  create_private_key = true
}

resource "aws_security_group" "remote_access" {
  name_prefix = "eks-remote-access"
  description = "Allow remote SSH access"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "All access"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    # TODO: This is also bad and I would never do this in production
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    # TODO: This is also bad and I would never do this in production
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Name = "eks-remote" }
}