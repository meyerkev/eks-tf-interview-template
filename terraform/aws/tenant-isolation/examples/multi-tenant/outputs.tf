output "vpc_ids" {
  description = "Map of tenant_id -> VPC ID."
  value       = { for k, m in module.tenants : k => m.vpc_id }
}

output "private_subnet_ids" {
  description = "Map of tenant_id -> list of private subnet IDs."
  value       = { for k, m in module.tenants : k => m.private_subnet_ids }
}

output "permissions_boundary_arns" {
  description = "Map of tenant_id -> permissions boundary ARN. Each tenant's downstream Terraform attaches its own."
  value       = { for k, m in module.tenants : k => m.permissions_boundary_arn }
}

output "egress_security_group_ids" {
  description = "Map of tenant_id -> egress SG ID (null for tenants in `isolated` mode)."
  value       = { for k, m in module.tenants : k => m.egress_security_group_id }
}
