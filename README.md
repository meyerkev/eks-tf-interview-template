# eks-tf-interview-template
EKS takes forever to come up, so here's a module to make EKS 

## Install the cluster
```
cd terraform/
terraform init
terraform apply -var "interviewee_name=<you>"
```

That will give you a cluster name and a keypair for the interviewee.  

The key pair will give then the ability to describe the cluster and update their local kubeconfig

## Install helm

This module will install the Helm charts

```
cd terraform/helm/
terraform init
terraform apply
```

## Cleaning up when done

```
# Validate that your access key is in the aws-nuke ignorelist
aws-nuke --config aws-nuke.yaml
```
