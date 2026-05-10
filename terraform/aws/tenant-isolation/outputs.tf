output "vpc_id" {
  description = "VPC ID for the tenant. Use as the `vpc_id` input on downstream modules (clusters, RDS, etc.) running in this tenant's scope."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the tenant VPC, echoed back from the input. Useful for downstream modules computing peering / route entries."
  value       = module.vpc.vpc_cidr_block
}

output "availability_zones" {
  description = "Resolved AZ names this tenant's subnets are spread across."
  value       = local.availability_zones
}

output "public_subnet_ids" {
  description = "Public subnet IDs (one per AZ). Use SPARINGLY - intended for internet-facing load balancers only, NOT for workloads."
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "Private subnet IDs (one per AZ). Default placement for tenant workloads."
  value       = module.vpc.private_subnets
}

output "internal_security_group_id" {
  description = "Tenant-internal mesh SG. Workloads should attach this BY DEFAULT - it is what prevents cross-tenant SG-level reachability."
  value       = aws_security_group.internal.id
}

output "egress_security_group_id" {
  description = "Outbound-internet SG. Only present when connectivity = egress_only; null otherwise. Attach IN ADDITION to internal_security_group_id for workloads needing NAT egress."
  value       = try(aws_security_group.egress[0].id, null)
}

output "permissions_boundary_arn" {
  description = "ATTACH this as the `permissions_boundary` on EVERY IAM role/user created in this tenant's scope. Without it, the tenant has no boundary - the producer/consumer contract collapses."
  value       = aws_iam_policy.tenant_boundary.arn
}

output "required_resource_tags" {
  description = "Caller-managed resources (everything outside this module) MUST include `tenant = <id>` in their tags for the IAM boundary's tag-conditioned ALLOW to apply. Other tags here are nice-to-have for cost allocation / blast-radius traceback."
  value       = local.required_tags
}
