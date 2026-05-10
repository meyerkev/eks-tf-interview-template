# --- Cluster identity / version --------------------------------------------

variable "cluster_name" {
  description = "EKS cluster name. Used in the SSM parameter path, the per-cluster subnet tag, etc."
  type        = string
}

variable "cluster_k8s_version" {
  description = "Kubernetes minor version for the EKS control plane."
  type        = string
}

variable "region" {
  description = "AWS region (used in the kubeconfig_command output)."
  type        = string
}

# --- VPC plumbing (passed in by the caller) --------------------------------

variable "vpc_id" {
  description = "VPC to put the cluster in."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs the cluster ENIs and (in this template) nodes will use."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs. Tagged for the cluster regardless; used for node placement only when var.public_nodes = false."
  type        = list(string)
}

variable "public_nodes" {
  description = "If true (default), put the cluster ENIs + node group in public_subnet_ids - nodes get public IPs and SSM/SSH access from outside the VPC works directly. If false, use private_subnet_ids; nodes need NAT egress to pull images and reach the EKS API. kubectl from outside still works either way as long as endpoint_public_access = true (which it is)."
  type        = bool
  default     = true
}

# --- Optional interviewee user --------------------------------------------

variable "interviewee_name" {
  description = "If set, create an IAM user + access key with this name and bind it as a cluster admin via an EKS access entry."
  type        = string
  default     = null
}

# --- Compute --------------------------------------------------------------

variable "eks_node_instance_type" {
  description = "Override the auto-picked instance type. If null, an architecture-appropriate default is chosen."
  type        = string
  default     = null
}

variable "target_architecture" {
  description = "Override the auto-detected architecture (arm64 / x86_64). If null, sniff `uname -m` from the laptop."
  type        = string
  default     = null
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

# --- Production knobs (defaults are production-safe; the wrapper at
# terraform/aws/main.tf overrides these to the interview-friendly values). -

variable "endpoint_public_access" {
  description = "Whether the EKS API server is reachable from outside the VPC. The wrapper module keeps this true; production may want false (kubectl via VPN/bastion only)."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "Restrict public-endpoint access to these CIDRs. Default null = AWS default of 0.0.0.0/0. Production should pin to office/jumpbox CIDRs."
  type        = list(string)
  default     = null
}

variable "cluster_security_group_additional_rules" {
  description = "Extra rules on the EKS-managed cluster (control plane) security group. Shape matches terraform-aws-modules/eks/aws v21. Default empty (production-safe). The wrapper passes the interview-template wide-open rule explicitly."
  type = map(object({
    protocol                   = optional(string, "tcp")
    from_port                  = number
    to_port                    = number
    type                       = optional(string, "ingress")
    description                = optional(string)
    cidr_blocks                = optional(list(string))
    ipv6_cidr_blocks           = optional(list(string))
    prefix_list_ids            = optional(list(string))
    self                       = optional(bool)
    source_node_security_group = optional(bool, false)
    source_security_group_id   = optional(string)
  }))
  default = {}
}

variable "node_security_group_additional_rules" {
  description = "Extra rules on the EKS-managed node security group. Shape matches terraform-aws-modules/eks/aws v21. The module already adds sane defaults (kubelet, CNI ports, etc.); this is for layering on top."
  type = map(object({
    protocol                      = optional(string, "tcp")
    from_port                     = number
    to_port                       = number
    type                          = optional(string, "ingress")
    description                   = optional(string)
    cidr_blocks                   = optional(list(string))
    ipv6_cidr_blocks              = optional(list(string))
    prefix_list_ids               = optional(list(string))
    self                          = optional(bool)
    source_cluster_security_group = optional(bool, false)
    source_security_group_id      = optional(string)
  }))
  default = {}
}

variable "additional_access_entries" {
  description = "EKS access entries to merge with the interviewee one. Use this for additional admins, CI principals, etc. Shape matches the EKS module's `access_entries` input."
  type = map(object({
    kubernetes_groups = optional(list(string))
    principal_arn     = string
    type              = optional(string, "STANDARD")
    user_name         = optional(string)
    tags              = optional(map(string), {})
    policy_associations = optional(map(object({
      policy_arn = string
      access_scope = object({
        namespaces = optional(list(string))
        type       = string
      })
    })), {})
  }))
  default = {}
}

variable "additional_addons" {
  description = "EKS managed addons to install in addition to vpc-cni / kube-proxy / coredns. Common production additions: eks-pod-identity-agent, aws-ebs-csi-driver, aws-mountpoint-s3-csi-driver. Shape matches the EKS module's `addons` input (set `before_compute = true` if a workload depends on the addon being present at first boot)."
  type        = any
  default     = {}
}
