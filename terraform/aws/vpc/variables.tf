variable "vpc_name" {
  description = "Name tag for the VPC. Required."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to spread subnets across. Required (caller picks)."
  type        = list(string)
}

variable "enable_nat_gateway" {
  type    = bool
  default = true
}

variable "single_nat_gateway" {
  description = "Run a single NAT gateway for all private subnets (cheap, single-AZ failure domain)."
  type        = bool
  default     = true
}

variable "one_nat_gateway_per_az" {
  type    = bool
  default = false
}

variable "enable_vpn_gateway" {
  type    = bool
  default = true
}

variable "map_public_ip_on_launch" {
  type    = bool
  default = true
}
