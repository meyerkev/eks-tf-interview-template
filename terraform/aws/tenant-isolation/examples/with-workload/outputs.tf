output "tenant_vpc_id" {
  value = module.tenant_acme.vpc_id
}

output "tenant_permissions_boundary_arn" {
  value = module.tenant_acme.permissions_boundary_arn
}

output "workload_role_arn" {
  description = "ARN of the consumer's workload role. Notice the boundary is attached - try `aws iam get-role --role-name <name>` to confirm the PermissionsBoundary field on the response."
  value       = aws_iam_role.tenant_workload.arn
}

output "workload_role_boundary_check" {
  description = "Wires the producer's boundary ARN to the consumer's role's boundary attribute as a single output, so a reviewer can verify the contract held."
  value = {
    producer_supplied_boundary = module.tenant_acme.permissions_boundary_arn
    consumer_attached_boundary = aws_iam_role.tenant_workload.permissions_boundary
    matches                    = module.tenant_acme.permissions_boundary_arn == aws_iam_role.tenant_workload.permissions_boundary
  }
}
