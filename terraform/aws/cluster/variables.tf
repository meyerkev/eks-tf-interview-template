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
