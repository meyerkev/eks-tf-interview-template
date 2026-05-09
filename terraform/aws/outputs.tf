# All cluster-side outputs are re-exported verbatim from the cluster
# submodule so smoke-test.sh, zero_to_hero.sh, and humans don't have to care
# that there's a wrapper.

output "interviewee_access_key" {
  value = module.cluster.interviewee_access_key
}

output "interviewee_secret_key" {
  value     = module.cluster.interviewee_secret_key
  sensitive = true
}

output "cluster_name" {
  value = module.cluster.cluster_name
}

output "kubeconfig_command" {
  value = module.cluster.kubeconfig_command
}

output "oidc_provider_arn" {
  value = module.cluster.oidc_provider_arn
}

output "aws_default_region" {
  value = var.region
}

# VPC outputs - handy for callers who want to layer their own resources on
# top of the wrapper-provisioned VPC.
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}
