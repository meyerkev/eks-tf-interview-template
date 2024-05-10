# eks-tf-interview-template
EKS takes forever to come up, so here's a module to make EKS 

## Install prerequisites

1. On OSX or Linux with brew: 

```
brew install aws-cli tfenv
cd terraform/
tfenv install
```

On Linux, I still recommend [tfenv](https://github.com/tfutils/tfenv)

2. configure aws with an IAM keypair

```
aws configure
```

## Initialize Terraform

1. Make an S3 bucket in the console
2. Follow these instructions
```
TFSTATE_BUCKET=<My bucket>

# Optional

# The statefile path inside your bucket
TFSTATE_KEY=<something>.tfvars

# The region your S3 bucket is in (Default: us-east-2)
TFSTATE_REGION=us-east-1

cd terraform/

# Only set the variables you set as env vars
terraform init \
-backend-config="bucket=${TFSTATE_BUCKET}" \
-backend-config="key=${TFSTATE_KEY}" \
-backend-config="region=${TFSTATE_REGION}" 
```

## Install the cluster
```
terraform apply -var "interviewee_name=<you>"
```

## Install helm (In-progress)

This module will install the Helm charts

```
cd terraform/helm/
terraform init
terraform apply
```

## Setup the interviewee
In the cluster module, there will be a variety of outputs.  If you lost them, no worries; Just run `terraform apply` again or `terraform outputs` to get a print-out of the outputs.  

Your outputs will be something like this: 

```
Apply complete! Resources: 68 added, 0 changed, 0 destroyed.

Outputs:

aws_default_region="us-east-1"
cluster_name = "eks-cluster"
interviewee_access_key = "AKIA...."
interviewee_secret_key = "Your Secret Key goes here"
kubeconfig_command = "aws eks update-kubeconfig --name eks-cluster --region us-east-1"
oidc_provider_arn = "arn:aws:iam::386145735201:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/24B3F62A211B955CD69B411037E3F470"
```

### Interviewee Prerequisites
- AWS CLI
- Kubectl
- Possibly [Helm](https://helm.sh/docs/intro/install/) if you want it

### Enable AWS
1. Configure their account

```
aws configure --profile=ik-interview

# Fill out this form accordingly
AWS Access Key ID [None]: <outputs.interviewee_access_key>
AWS Secret Access Key [None]: <outputs.interviewee_secret_key>
Default region name [None]: us-east-1
Default output format [None]: json


# Run this in every new terminal you open
export AWS_PROFILE=ik-interview
```

2. Run `aws sts get-caller-identity` to ensure that they are who they think they are

```
# Not all values will be the same, but if they can run it, good enough.  
aws sts get-caller-identity
{
    "UserId": "AIDAVT2AUKIQU7UZDIMP3",
    "Account": "386145735201",
    "Arn": "arn:aws:iam::386145735201:user/ik-session"
}
```

### Enable the kubeconfig

One of your Terraform outputs was `kubeconfig_command`.  Copy-paste that output to chat

```
# DO NOT USE THIS!!!! Copy-paste from output.  DO NOT USE THIS!!!!
aws eks update-kubeconfig --name eks-cluster --region us-east-1
```

then run any command you want to run.  Personally, `kubectl get pods -A` gives me a lot of output from many namespaces.  

If that works, congratulations, your user now has admin-ish powers on the k8s cluster.  

## Cleaning up when done

Either use 

```
terraform destroy -var 'interviewee_name=destroy'

# Alt, if you customized your cluster
terraform destroy -var-file tfvars/<my_cluster>.yaml 
```

or if it's an account you really really do not want to get charged for:

```
# Validate that your access key is in the aws-nuke ignorelist
brew install aws-nuke
aws-nuke --config aws-nuke.yaml
```
