output "interviewee_access_key" {
  value = aws_iam_access_key.interviewee_key.id
}

output "interviewee_secret_key" {
  value = nonsensitive(aws_iam_access_key.interviewee_key.secret)
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}