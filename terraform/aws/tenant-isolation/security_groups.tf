# Two layered security groups, demonstrating the "compose, don't anticipate"
# pattern:
#
#   - `internal` : workloads ALWAYS attach this. Allows traffic between
#                  members (SG self-reference, NOT a CIDR allowlist - the
#                  self-reference IS the cross-tenant isolation primitive).
#                  Egress is also self-referential, so workloads can talk
#                  amongst themselves but cannot reach the internet just
#                  because they have this SG.
#
#   - `egress`   : workloads ADDITIONALLY attach this if they need
#                  outbound internet (only created when connectivity ==
#                  egress_only). No ingress rules; pure egress vector.
#
# Workloads needing INBOUND from the internet bring their own SG (e.g. a
# tenant-managed ALB SG). This module is about isolation, not exposure.
#
# Inline ingress/egress blocks are used here (rather than the newer
# aws_vpc_security_group_*_rule resources) because it's the only way to
# fully manage the AWS-default allow-all-egress rule that AWS auto-creates
# on every new SG. The newer resources don't take ownership of that
# default rule, which would silently undermine the isolation story.

resource "aws_security_group" "internal" {
  name_prefix = "${local.name_prefix}-internal-"
  vpc_id      = module.vpc.vpc_id
  description = "Tenant-internal mesh SG. Members can talk to each other; no internet access via this SG."

  ingress {
    description = "Mesh: members can talk to each other on any port"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Egress restricted to the same SG. SGs are stateful so reply traffic
  # is automatic; this rule is for INITIATED connections from one tenant
  # workload to another. Workloads that need to reach AWS APIs should
  # also attach `egress` SG (in egress_only mode) or rely on VPC endpoints.
  egress {
    description = "Mesh: members can initiate to each other"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-internal" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "egress" {
  count = var.connectivity == "egress_only" ? 1 : 0

  name_prefix = "${local.name_prefix}-egress-"
  vpc_id      = module.vpc.vpc_id
  description = "Outbound-internet SG. Compose with `internal` for workloads needing both intra-tenant + outbound. No ingress."

  egress {
    description      = "All outbound. PRODUCTION: tighten via prefix lists, AWS-managed prefix lists, or per-destination CIDRs."
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-egress" })

  lifecycle {
    create_before_destroy = true
  }
}
