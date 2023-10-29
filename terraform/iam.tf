resource "aws_iam_user" "interviewee" {
  count = var.interviewee_name != null ? 1 : 0
  name = var.interviewee_name
  path = "/"
}

# Write a policy that lets us get the kubeconfig for the cluster and attach it to our user
resource "aws_iam_user_policy" "kubeconfig" {
  count = var.interviewee_name != null ? 1 : 0
  name = "kubeconfig"
  user = aws_iam_user.interviewee[0].name

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowKubeconfig",
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:updateKubeconfig",
                "eks:ListFargateProfiles",
                "eks:DescribeNodegroup",
                "eks:ListNodegroups",
                "eks:ListUpdates",
                "eks:AccessKubernetesApi",
                "eks:ListAddons",
                "eks:DescribeCluster",
                "eks:DescribeAddonVersions",
                "eks:ListClusters",
                "eks:ListIdentityProviderConfigs",
                "iam:ListRoles"

            ],
            "Resource": "${module.eks.cluster_arn}"
        },
        {
            "Effect": "Allow",
            "Action": "ssm:GetParameter",
            "Resource": "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/*"
        }
    ]
}
EOF
}

# Add an IAM keypair for the interviewee
resource "aws_iam_access_key" "interviewee_key" {
  count = var.interviewee_name != null ? 1 : 0
  user = aws_iam_user.interviewee[0].name
}