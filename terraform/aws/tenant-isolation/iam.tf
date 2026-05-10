# Permissions boundary for IAM principals operating within this tenant's
# scope. The module is the PRODUCER; tenant-team Terraform (or an org-level
# SCP) is the CONSUMER and is responsible for ATTACHING this boundary to
# every role/user it creates in the tenant's name.
#
# Permissions boundary != identity policy != SCP:
#   - An identity policy GRANTS permissions to one principal.
#   - A permissions boundary CAPS what a principal can do, regardless of
#     identity policies. Effective = identity policy AND boundary.
#   - An SCP CAPS permissions for an entire account / OU.
#
# This boundary is layered as three statements (read top-down):
#
#   1. ALLOW * IF the resource carries the `tenant=<id>` tag.
#      Combined with mandatory tagging on resource CREATION (typically
#      enforced at the org level via SCP, or via a separate IAM policy
#      that denies `*Create*` calls without `aws:RequestTag/tenant`),
#      this means tenant principals can only act on tenant-scoped
#      resources.
#
#   2. DENY a curated list of IAM actions that would let a compromised
#      principal escape its boundary (escalation defense). This is
#      defense-in-depth: even if statement 1 somehow allows them.
#
#   3. DENY org / billing / account-wide actions that have no per-resource
#      condition keys. Without this, statement 1 would technically allow
#      `organizations:LeaveOrganization` because the "resource" is the
#      account itself which doesn't have a `tenant` tag, BUT some
#      services don't enforce tag-conditioning correctly - belt and
#      suspenders.
#
# Known limits (intentionally NOT addressed in this code sample, but
# called out in the README's "production additions" section):
#
#   - Some AWS services don't fully support `aws:ResourceTag` in their
#     condition keys (parts of KMS, S3 object operations, RDS, etc.). A
#     real-world boundary needs ARN-allowlist statements for those.
#   - This boundary defends against IAM-based escape, NOT against data
#     exfiltration through services the tenant is legitimately allowed
#     to use (e.g. PutObject to a tenant-tagged bucket whose bucket
#     policy doesn't restrict downloaders).
#   - Cross-account assume-role from a tenant-tagged role into another
#     account's role is allowed by this boundary (sts:AssumeRole on
#     ANY resource matches statement 1 because the role being assumed
#     is the principal's own tagged role per IAM evaluation). A real
#     boundary would restrict sts:AssumeRole resources explicitly.

data "aws_iam_policy_document" "tenant_boundary" {
  statement {
    sid       = "AllowAnyOnTenantTaggedResources"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/tenant"
      values   = [var.tenant_id]
    }
  }

  statement {
    sid    = "DenyIamSelfEscalation"
    effect = "Deny"

    actions = [
      # Creating new principals
      "iam:CreateUser",
      "iam:CreateRole",
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",

      # Modifying policies attached to existing principals
      "iam:PutRolePolicy",
      "iam:PutUserPolicy",
      "iam:AttachRolePolicy",
      "iam:AttachUserPolicy",

      # Removing or overwriting the boundary itself - this is the
      # critical one; without these denies, a compromised principal
      # could simply delete its boundary.
      "iam:DeleteRolePermissionsBoundary",
      "iam:DeleteUserPermissionsBoundary",
      "iam:PutRolePermissionsBoundary",
      "iam:PutUserPermissionsBoundary",

      # Trust-policy mutation = privilege escalation surface
      "iam:UpdateAssumeRolePolicy",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "DenyAccountWideOperations"
    effect = "Deny"

    actions = [
      "organizations:*",
      "account:*",
      "billing:*",
      "aws-portal:*",
      "ce:*",      # Cost Explorer
      "cur:*",     # Cost & Usage Reports
      "support:*", # Premium Support tickets
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "tenant_boundary" {
  name_prefix = "${local.name_prefix}-boundary-"
  path        = "/tenant/"
  description = "Permissions boundary for tenant ${var.tenant_id}. ATTACH this to every IAM role/user created in this tenant's scope. See module README."
  policy      = data.aws_iam_policy_document.tenant_boundary.json

  tags = local.tags
}
