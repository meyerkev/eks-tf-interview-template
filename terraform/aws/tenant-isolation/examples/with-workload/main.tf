# Producer/consumer example: provision one tenant AND demonstrate what
# "good consumption" of the module's outputs looks like from downstream
# Terraform.
#
# The point of this example is to make the producer/consumer contract
# concrete - the module README describes it in prose; this code shows it.
#
# A "good consumer" of tenant-isolation:
#   1. Attaches `permissions_boundary_arn` on every IAM principal it
#      creates in the tenant's scope.
#   2. Tags every resource with at least the `tenant` key from
#      `required_resource_tags` (so the boundary's tag-conditioned
#      ALLOW takes effect).
#   3. Places workloads in `private_subnet_ids` and attaches
#      `internal_security_group_id` (+ optionally egress) by default.
#
# In a real platform, the tenant-team Terraform lives in a different repo
# and reads the boundary ARN via terraform_remote_state, AWS SSM, or a
# data source on the IAM policy by name. Here we put both halves in one
# file for clarity.

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

# ===========================================================================
# PRODUCER: the tenant-isolation module.
# ===========================================================================

module "tenant_acme" {
  source = "../.."

  tenant_id = "acme"
  vpc_cidr  = "10.10.0.0/16"

  extra_tags = {
    cost_center = "eng-platform"
    environment = "shared-dev"
  }
}

# ===========================================================================
# CONSUMER: a sample workload IAM role created by tenant-team Terraform.
# ===========================================================================

# The role's trust policy: who can assume it. Locked to EC2 here as a
# minimal example; in a real deployment this would also be tagged with
# the tenant's principal-tag for cross-account assumption guards.
data "aws_iam_policy_document" "workload_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "tenant_workload" {
  # Name carries the tenant_id so the boundary's allow-condition isn't
  # the only signal in the AWS console of "this role belongs to acme".
  name = "${module.tenant_acme.required_resource_tags["tenant"]}-workload"

  # ----- THE LOAD-BEARING LINES OF THIS EXAMPLE ----------------------------
  permissions_boundary = module.tenant_acme.permissions_boundary_arn
  tags                 = module.tenant_acme.required_resource_tags
  # -------------------------------------------------------------------------

  assume_role_policy = data.aws_iam_policy_document.workload_assume.json
}

# An identity policy that GRANTS broad permissions; the boundary CAPS the
# effective set. In other words: even though this policy says "do anything
# on any resource", the role can only actually act on resources tagged
# tenant=acme (per the boundary's first statement) and cannot do
# IAM-self-escalation or org-wide actions (per the boundary's deny
# statements).
#
# This is the punch line of permissions boundaries: identity policies can
# be overly broad without consequence, because the boundary is the cap.
data "aws_iam_policy_document" "workload_admin" {
  statement {
    sid       = "DeliberatelyBroad"
    actions   = ["*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "tenant_workload_admin" {
  name   = "tenant-admin-within-boundary"
  role   = aws_iam_role.tenant_workload.id
  policy = data.aws_iam_policy_document.workload_admin.json
}
