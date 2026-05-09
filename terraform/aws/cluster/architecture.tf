# Pick the right node instance type and AMI architecture.
#
# Three layers of override (most specific wins):
#   1. var.eks_node_instance_type set      -> use that
#   2. var.target_architecture set         -> pick a default for arm64 vs x86_64
#   3. neither set                         -> sniff `uname -m` from the laptop
#
# The point of layer 3 is so local Docker builds and the cluster default to
# the same architecture without anyone having to think about it.

locals {
  target_architecture    = var.target_architecture == null ? data.external.architecture[0].result.architecture : var.target_architecture
  eks_node_instance_type = var.eks_node_instance_type != null ? var.eks_node_instance_type : (local.target_architecture == "arm64" ? "m7g.large" : "m7a.large")

  is_arm = contains(data.aws_ec2_instance_type.eks_node_instance_type.supported_architectures, "arm64")
  # AL2023 is the v21 EKS module default; AL2 is approaching EOL and
  # AL2023 also gives us SSM Session Manager out of the box.
  ami_type = local.is_arm ? "AL2023_ARM_64_STANDARD" : "AL2023_x86_64_STANDARD"
}

# `path.module` resolves to this submodule's directory so the script lookup
# works whether we're invoked via the wrapper at terraform/aws/ or
# standalone from someone else's root module.
data "external" "architecture" {
  count   = var.target_architecture == null ? 1 : 0
  program = ["${path.module}/scripts/architecture_check.sh"]
}

data "aws_ec2_instance_type" "eks_node_instance_type" {
  instance_type = local.eks_node_instance_type
}

data "aws_caller_identity" "current" {}
