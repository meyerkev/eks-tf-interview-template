resource "aws_iam_user" "interviewee" {
    name = var.interviewee_name
    path = "/"
}

# Write a policy that lets us get the kubeconfig for the cluster and attach it to our user
resource "aws_iam_user_policy" "kubeconfig" {
    name = "kubeconfig"
    user = aws_iam_user.interviewee.name

    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowKubeconfig",
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:updateKubeconfig"

            ],
            "Resource": "${module.eks.cluster_arn}"
        }
    ]
}
EOF
}

# Add an IAM keypair for the interviewee
resource "aws_iam_access_key" "interviewee_key" {
    user = aws_iam_user.interviewee.name
}