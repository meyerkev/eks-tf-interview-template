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

variable "interviewee_name" {
  type = string
}

variable "cluster_k8s_version" {
  type    = string
  default = "1.29"
}

variable "public_nodes" {
  type        = bool
  default     = true
  description = "If true, we put our nodes in public subnets for easier access"
}

variable "eks_node_instance_type" {
  type    = string
  default = null  # "m6g.large"
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
