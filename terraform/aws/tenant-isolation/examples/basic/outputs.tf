output "vpc_id" {
  value = module.tenant_acme.vpc_id
}

output "private_subnet_ids" {
  value = module.tenant_acme.private_subnet_ids
}

output "internal_security_group_id" {
  value = module.tenant_acme.internal_security_group_id
}

output "permissions_boundary_arn" {
  value = module.tenant_acme.permissions_boundary_arn
}

output "required_resource_tags" {
  value = module.tenant_acme.required_resource_tags
}
