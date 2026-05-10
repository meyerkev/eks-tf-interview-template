variable "vpc_name" {
  description = "Name tag for the VPC. Required."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

# --- AZ selection ---------------------------------------------------------
#
# Three mutually-exclusive ways to pick AZs (precedence in this order):
#
#   1. var.availability_zones      - explicit list of full AZ names
#   2. var.availability_zone_letters + var.region - letters expanded into
#      "${region}${letter}", e.g. ["a","c"] in us-east-2 -> us-east-2a, us-east-2c
#   3. var.availability_zone_count + var.region   - first N letters
#      (a, b, c, d, e, f) expanded the same way
#
# If all three are null, defaults to letters = ["a", "b", "c"] (3 AZs).
# A `terraform_data` precondition enforces the mutual exclusivity at plan
# time so misconfigurations fail fast.

variable "availability_zones" {
  description = "Explicit list of full AZ names, e.g. ['us-east-2a','us-east-2b','us-east-2c']. Mutually exclusive with letters/count. Set this when you know exactly which AZs you want and they don't follow the simple a/b/c pattern."
  type        = list(string)
  default     = null

  validation {
    condition     = var.availability_zones == null || length(var.availability_zones) >= 2
    error_message = "Need at least 2 AZs (EKS requires multi-AZ for the control plane)."
  }
}

variable "availability_zone_letters" {
  description = "AZ suffix letters to spin up; will be prefixed with var.region. Mutually exclusive with availability_zones / availability_zone_count."
  type        = list(string)
  default     = null

  validation {
    condition     = var.availability_zone_letters == null || length(var.availability_zone_letters) >= 2
    error_message = "Need at least 2 AZ letters."
  }
}

variable "availability_zone_count" {
  description = "Number of AZs to use; takes the first N letters from a, b, c, d, e, f. Mutually exclusive with availability_zones / availability_zone_letters."
  type        = number
  default     = null

  validation {
    condition     = var.availability_zone_count == null || (var.availability_zone_count >= 2 && var.availability_zone_count <= 6)
    error_message = "AZ count must be between 2 and 6 (no AWS region currently has more than 6 AZs)."
  }
}

variable "region" {
  description = "AWS region. Required when using availability_zone_letters or availability_zone_count (so letters can be expanded to full AZ names). Ignored when availability_zones is set explicitly."
  type        = string
  default     = null
}

# --- NAT / DNS / VPN options ----------------------------------------------

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
