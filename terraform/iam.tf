resource "iam_user" "interviewee" {
    name = var.interviewee_name
    path = "/"
}

resource "iam_user_policy" "interviewee_policy" {
    name = "interviewee_policy"
    user = iam_user.interviewee.name

    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowAllActions",
            "Effect": "Allow",
            "Action": "*",
            "Resource": "*"
        }
    ]
}

EOF
}

# Add an IAM keypair for the interviewee
resource "aws_iam_access_key" "interviewee_key" {
    user = iam_user.interviewee.name
}