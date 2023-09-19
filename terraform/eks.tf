locals {
  availability_zones = ["${var.region}a", "${var.region}b", "${var.region}c"]
  # This is sort of weird and I could see myself rewriting it in the future
  # If you set an instance type, it will use that and then look up the architecture
  # BUT if you set a target architecture, it will use that and then look up the instance type of that architecture and then re-lookup the architecture
  #
  # Laptop -> Architecture lookup -> default instance type lookup -> Architecture lookup
  #
  # And if you don't set either, it will look up the architecture of the machine you're running on so that local Docker builds work by default
  # But what this means is that you can totally say "ARM.  I am ARM", pick an x64 instance type, and get an x64 cluster
  # By accident
  target_architecture    = var.target_architecture == null ? data.external.architecture[0].result.architecture : var.target_architecture
  eks_node_instance_type = var.eks_node_instance_type != null ? var.eks_node_instance_type : local.target_architecture == "arm64" ? "m6g.large" : "m6i.large"
}

# This is a wee bit of a hack and requires being on something Linuxy
# But that's why I let you override it.  
data "external" "architecture" {
  count   = var.target_architecture == null ? 1 : 0
  program = ["./scripts/architecture_check.sh"]
}

data "aws_ec2_instance_type" "eks_node_instance_type" {
  instance_type = local.eks_node_instance_type
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "4"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs = local.availability_zones

  # TODO: Some regions have more than 4 AZ's
  public_subnets   = [for i, az in local.availability_zones : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets  = [for i, az in local.availability_zones : cidrsubnet(var.vpc_cidr, 8, i + 4)]
  database_subnets = [for i, az in local.availability_zones : cidrsubnet(var.vpc_cidr, 8, i + 8)]

  enable_dns_hostnames = true

  # Enable NAT Gateway
  # Expensive, but a requirement 
  enable_nat_gateway      = true
  single_nat_gateway      = true
  one_nat_gateway_per_az  = false
  enable_vpn_gateway      = true
  map_public_ip_on_launch = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" : 1
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" : 1
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
  }
}

//*
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_k8s_version

  cluster_endpoint_public_access = true
  create_iam_role                = true

  aws_auth_users = [
    # Once again, this might not be ideal except in an interview setting
    {
      userarn  = aws_iam_user.interviewee.arn
      username = aws_iam_user.interviewee.name
      groups   = ["system:masters"]
    }
  ]

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
    # I make exactly zero promises that this is complete, but basically pick an instance type that matches your architecture
    # I would love to have some weird locals thingy that figures out if you're ARM or x64 or whatever, but I'm not sure how to do that
    # Known valid strings (I tested them on my laptop) are: arm64, x86_64
    ami_type                   = contains(data.aws_ec2_instance_type.eks_node_instance_type.supported_architectures, "arm64") ? "AL2_ARM_64" : "AL2_x86_64"
    instance_types             = [local.eks_node_instance_type]
    iam_role_attach_cni_policy = true
  }

  eks_managed_node_groups = {
    # Default node group - as provided by AWS EKS
    default_node_group = {
      min_size     = var.min_nodes
      max_size     = var.max_nodes
      desired_size = var.desired_nodes
      # By default, the module creates a launch template to ensure tags are propagated to instances, etc.,
      # so we need to disable it to use the default template provided by the AWS EKS managed node group service
      use_custom_launch_template = false

      disk_size = 50 # Large enough to work with by default when under time pressure

      # Remote access cannot be specified with a launch template
      remote_access = {
        ec2_ssh_key               = module.key_pair.key_pair_name
        source_security_group_ids = [aws_security_group.remote_access.id]
      }
    }
  }
  cluster_security_group_additional_rules = {
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

resource "aws_ssm_parameter" "oidc_provider" {
  name  = "/eks/${var.cluster_name}/oidc_provider"
  type  = "String"
  value = module.eks.oidc_provider_arn
}