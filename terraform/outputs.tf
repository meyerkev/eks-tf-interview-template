output "interviewee_access_key" {
    value = aws_iam_access_key.interviewee_key.id
}

output "interviewee_secret_key" {
    value = aws_iam_access_key.interviewee_key.secret
}