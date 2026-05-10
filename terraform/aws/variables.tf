variable "region" {
  type    = string
  default = "us-east-2"
}

variable "cluster_name" {
  type    = string
  default = "eks-cluster"
}

variable "vpc_name" {
  type    = string
  default = null
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

# --- AZ selection ---------------------------------------------------------
# Set at most one of these. If both are null, defaults to 3 AZs (a, b, c).
# See terraform/aws/vpc/variables.tf for the full description.

variable "availability_zone_letters" {
  description = "AZ suffix letters (e.g. ['a','c','d']) prepended with var.region. Mutually exclusive with availability_zone_count."
  type        = list(string)
  default     = null
}

variable "availability_zone_count" {
  description = "Number of AZs to spin up across (2-6); takes the first N letters from a, b, c, d, e, f. Mutually exclusive with availability_zone_letters."
  type        = number
  default     = null
}

variable "interviewee_name" {
  description = "If set, create an IAM user with this name and grant it cluster-admin via an EKS access entry. Leave null to skip."
  type        = string
  default     = null
}

variable "cluster_k8s_version" {
  type    = string
  default = "1.35"
}

variable "public_nodes" {
  type        = bool
  default     = true
  description = "If true (default), put cluster ENIs + nodes in public subnets (interview-friendly: direct SSM/SSH from outside the VPC). If false, use private subnets (production-style; needs NAT egress, which the VPC submodule provides by default)."
}

variable "eks_node_instance_type" {
  type    = string
  default = null # "m6g.large"
}

variable "target_architecture" {
  type    = string
  default = null
}

variable "min_nodes" {
  type    = number
  default = 1
}

variable "max_nodes" {
  type    = number
  default = 10
}

variable "desired_nodes" {
  type    = number
  default = 3
}

# --- Production-knob passthroughs ------------------------------------------
# These all forward to the cluster submodule. Defaults here preserve the
# interview-mode behavior (wide-open cluster SG, public API). Override them
# from -var / -var-file when you want a tighter setup.

variable "endpoint_public_access" {
  description = "Whether the EKS API is reachable from outside the VPC. Default true; set false for VPN-only."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "Restrict the public EKS API endpoint to these CIDRs. Default null = AWS default 0.0.0.0/0. Pin to office/jumpbox CIDRs in production."
  type        = list(string)
  default     = null
}

variable "cluster_security_group_additional_rules" {
  description = "Extra rules on the cluster control-plane SG. Default = the interview wide-open rule. Override with `{}` (or your own scoped rules) for production."
  type        = map(any)
  default = {
    eks_cluster = {
      type        = "ingress"
      description = "Never do this in production"
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}

variable "node_security_group_additional_rules" {
  description = "Extra rules on the node SG. Default empty (the EKS module already adds kubelet/CNI/etc. defaults)."
  type        = map(any)
  default     = {}
}

variable "additional_access_entries" {
  description = "Extra EKS access entries to merge with the interviewee one - additional admins, CI principals, etc."
  type        = any
  default     = {}
}

variable "additional_addons" {
  description = "Extra EKS managed addons on top of vpc-cni / kube-proxy / coredns. e.g. eks-pod-identity-agent, aws-ebs-csi-driver."
  type        = any
  default     = {}
}
