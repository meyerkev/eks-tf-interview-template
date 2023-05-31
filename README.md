# eks-tf-interview-template
EKS takes forever to come up, so here's a module to make EKS 

## Install the cluster
```
cd terraform/
terraform init
terraform apply -var "interviewee_name=<you>"
```

That will give you a cluster namne and a keypair for the interviewee.  

The key pair will give then the ability to describe the cluster and update their local kubeconfig

## Install helm

This module will install the Helm charts

```
cd helm/
terraform init
terraform apply
```
