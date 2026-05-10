# tenant-isolation

A Terraform module that provisions the AWS network + IAM scaffolding for **one tenant** in a multi-tenant SaaS environment. Call it once per tenant; outputs feed downstream tenant-team Terraform that creates the actual workloads.

> This is a **code sample**, not production infrastructure. The README's "Production additions deliberately omitted" section spells out the gap.

## Usage

```hcl
module "tenant_acme" {
  source = "./modules/tenant-isolation"

  tenant_id    = "acme"
  vpc_cidr     = "10.10.0.0/16"
  connectivity = "egress_only"

  extra_tags = {
    cost_center = "eng-platform"
    owner       = "platform-team@example.com"
  }
}
```

A `for_each` example covering multiple tenants is in [`examples/basic/main.tf`](examples/basic/main.tf).

## What this creates

| Layer | Resource | Purpose |
|---|---|---|
| Network | 1× VPC sized to `var.vpc_cidr` | L3 boundary - hardest isolation AWS gives short of separate accounts |
| Network | N× public + N× private subnets across AZs | Two-tier; workloads default to private |
| Network | NAT gateway (when `connectivity = egress_only`) | Outbound-only internet for private workloads |
| Security | `internal` security group, self-referenced | Tenant-internal mesh - the actual SG-level isolation primitive |
| Security | `egress` security group | Compose with `internal` for workloads needing internet egress |
| IAM | Permissions boundary policy | Caps every tenant principal's effective permissions to tenant-tagged resources |
| Tags | `tenant`, `managed_by`, `module` on every resource | Tag-based ABAC for the boundary; cost allocation; blast-radius traceback |

## Producer / consumer contract

This module deliberately splits responsibilities. **Read this section before reading the code.**

### What this module produces

- The VPC, subnets, NAT, security groups (the network boundary).
- The **permissions boundary policy** itself - exposed via `output.permissions_boundary_arn`.
- The **required tag map** - exposed via `output.required_resource_tags`.

### What the tenant team consumes

When the tenant team writes their own Terraform to create workloads inside the tenant scope:

1. They MUST attach `module.tenant_X.permissions_boundary_arn` as the `permissions_boundary` on every `aws_iam_role` and `aws_iam_user` they create.
2. They MUST tag every resource with `module.tenant_X.required_resource_tags` (or at minimum the `tenant` key).
3. They place workloads in `module.tenant_X.private_subnet_ids` and attach `module.tenant_X.internal_security_group_id` as the default SG.

### What the platform team enforces (out of scope for this module)

The producer/consumer contract is voluntary unless **the platform team enforces** it via mechanisms outside this module:

- **SCP** at the org level: `Deny iam:CreateRole/iam:CreateUser` unless `iam:PermissionsBoundary` matches a tenant-boundary ARN.
- **SCP / IAM policy**: `Deny *Create*` unless `aws:RequestTag/tenant` is set and matches the principal's own `aws:PrincipalTag/tenant`.
- **SCP**: `Deny iam:DeleteRolePermissionsBoundary` org-wide as belt-and-suspenders (the boundary itself denies this for tenant principals; the SCP catches platform-admin mistakes).

Without these enforcement mechanisms, this module is *advisory*, not load-bearing. That is intentional - the module is designed to be the **producer half** of a contract that lives larger than itself.

## Threat model

### What this defends against

- **Cross-tenant network reachability via SG misconfiguration** - the `internal` SG self-references rather than allowlisting CIDRs, so members of tenant A's SG cannot accidentally allow tenant B in by editing a CIDR.
- **IAM scope creep** - the boundary's tag-conditioned ALLOW means a tenant principal granted `AdministratorAccess` (by mistake or compromise) still cannot touch resources outside its tenant.
- **IAM self-escalation** - explicit DENY on `iam:Put*PermissionsBoundary`, `iam:UpdateAssumeRolePolicy`, etc., so a compromised principal cannot remove its own boundary.
- **Account-wide actions** that bypass tag conditioning (org / billing / support) - explicit DENY.

### What this DOES NOT defend against

- **Data exfiltration through legitimate channels.** A tenant-tagged S3 bucket whose bucket policy allows public read will leak; the IAM boundary doesn't see bucket policies.
- **Services without tag-based ABAC support.** Parts of KMS, S3 object operations, RDS, Secrets Manager, etc. don't fully support `aws:ResourceTag` in their condition keys. A real boundary would also need ARN-allowlist statements for those.
- **Cross-tenant connectivity at higher layers.** SGs prevent IP-level reachability; they don't prevent a tenant workload from calling a public API run by another tenant.
- **Resource enumeration via list operations.** Many `*:Describe*` and `*:List*` actions don't take per-resource conditions; they return the whole account's view.
- **Compromise of the tenant-team Terraform itself.** If the tenant team's CI/CD principal is breached, the boundary still applies, but the attacker can do anything that boundary allows (which is broad - "AdministratorAccess scoped to tenant tag").

## Module structure

```
tenant-isolation/
├── README.md                   # this file
├── versions.tf                 # provider + Terraform version pins
├── variables.tf                # 5 inputs: tenant_id, vpc_cidr, az_count, connectivity, extra_tags
├── locals.tf                   # AZ data source, name prefix, tag composition
├── vpc.tf                      # delegates to terraform-aws-modules/vpc/aws v6
├── security_groups.tf          # internal + egress SGs
├── iam.tf                      # the permissions boundary - the centerpiece
├── outputs.tf                  # the consumer API
└── examples/                   # see examples/README.md
    ├── README.md               # index of the three examples
    ├── basic/                  # minimum viable: one tenant, defaults
    ├── multi-tenant/           # for_each over a map of tenants with mixed connectivity
    └── with-workload/          # producer/consumer contract made concrete (boundary attached to a role)
```

## Production additions deliberately omitted

All of these would belong in a real-world version of this module. Each is omitted with prejudice for the code sample:

- **VPC Flow Logs** to a centralized log archive in a separate AWS account, with the flow-log IAM role itself wearing the tenant boundary (recursive eat-your-own-dogfood).
- **VPC endpoints** for S3 / ECR / STS / Secrets Manager / SSM so workloads in `isolated` mode can still reach AWS APIs without traversing NAT or the internet.
- **NACLs** as belt-and-suspenders alongside SGs - subnet-level deny for cross-tenant CIDRs in case an SG is misconfigured.
- **KMS CMK per tenant** for envelope encryption, with a key policy that enforces the same tag-conditioning as the IAM boundary.
- **Per-AZ NAT gateways** instead of a single NAT (cost vs availability tradeoff).
- **Cross-tenant connectivity primitives** - Transit Gateway attachment, shared-services VPC peering, Route53 Resolver rules. Belongs in a sibling `tenant-connectivity` module, not here.
- **The org-level SCPs** that enforce the producer/consumer contract.
- **The mandatory-tagging IAM policy** that denies `*Create*` calls without `aws:RequestTag/tenant`.
- **Resource-tag mutation defense** - a separate IAM policy that denies tag changes on existing resources, otherwise a tenant principal could re-tag a resource into a different tenant.
- **VPC IPAM integration** so `vpc_cidr` is allocated rather than caller-supplied (eliminates the cross-tenant CIDR-overlap risk).
- **Stricter `egress` SG** - in production the egress SG would allow specific destination prefix lists (S3, DynamoDB, etc. via AWS-managed prefix lists; explicit egress for known SaaS endpoints) rather than `0.0.0.0/0`.
- **Boundary refinements** - ARN-allowlist statements for the AWS services that don't support `aws:ResourceTag` (KMS, parts of S3 object ops, RDS, Secrets Manager).
- **`sts:AssumeRole` restriction** in the boundary so a compromised tenant principal cannot pivot into a role in another account.

## Design decisions worth defending verbally

These are the choices the interviewer is likely to probe; the code comments call them out, and they are summarized here for ease of reference:

| Decision | Reasoning |
|---|---|
| Use `terraform-aws-modules/vpc/aws` instead of handwritten primitives | The IaC rubric is about *taste*, not reinventing primitives. Reach for vetted modules. |
| Inline `ingress`/`egress` blocks on the SGs (not the newer `aws_vpc_security_group_*_rule` resources) | The newer pattern doesn't take ownership of the AWS-default allow-all-egress that AWS auto-creates on SG creation, which would silently undermine isolation. Inline blocks let me explicitly remove it. |
| `internal` SG self-references rather than CIDR-allowlists | Self-reference IS the isolation primitive. CIDR allowlists drift over time as VPC CIDRs change; SG self-references don't. |
| Three IAM statements instead of one big `Allow * if tenant tag` | Defense in depth. A misconfigured tag (`tenant=*`) shouldn't grant org-wide access. |
| Caller-supplied `extra_tags` is merged UNDER `local.required_tags` | Required tags win on conflict. Allowing a caller to override `tenant` in `extra_tags` would silently break isolation. |
| Module produces the boundary policy but does NOT attach it | Producer/consumer split. The module has no view of *which* roles need it; the tenant team does. SCP enforcement closes the loop. |
| `vpc_cidr` validated `/20` or larger | Smaller blocks can't fit two subnet tiers across multiple AZs with reasonable per-subnet headroom. |
| `availability_zone_count` defaults to 3, capped at 6 | 2 is the EKS / RDS multi-AZ minimum; 6 is the AWS limit. |
| `tenant_id` regex-validated DNS-safe | The id ends up in IAM policy SIDs, resource names, tag values, ARNs, etc. Stricter than necessary on purpose. |
