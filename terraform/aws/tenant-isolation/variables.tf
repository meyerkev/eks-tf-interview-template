# --- Identity --------------------------------------------------------------

variable "tenant_id" {
  description = <<-EOT
    Stable, lowercase, DNS-safe identifier for this tenant. Used for:
      - Resource name prefix ("tenant-<id>-...").
      - The required `tenant` tag on every resource the module creates.
      - The `aws:ResourceTag/tenant` allow-condition in the IAM
        permissions boundary.
    Must match: 3-32 chars, [a-z][a-z0-9-]*[a-z0-9].
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.tenant_id))
    error_message = "tenant_id must be 3-32 chars, lowercase a-z / 0-9 / hyphen, starting with a letter and ending with a letter or digit."
  }
}

# --- Network --------------------------------------------------------------

variable "vpc_cidr" {
  description = <<-EOT
    CIDR for this tenant's VPC. The caller is responsible for ensuring no
    overlap with other tenants' VPCs - this module has no global view of
    address allocations. Must be /20 or larger to fit two subnet tiers
    across multiple AZs with reasonable headroom.
  EOT
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid CIDR block of /20 or larger (e.g. 10.0.0.0/16, 10.0.0.0/20)."
  }
}

variable "availability_zone_count" {
  description = "Number of AZs to spread subnets across. Minimum 2 for HA; AWS regions have between 3 and 6 AZs."
  type        = number
  default     = 3

  validation {
    condition     = var.availability_zone_count >= 2 && var.availability_zone_count <= 6
    error_message = "availability_zone_count must be between 2 and 6."
  }
}

variable "connectivity" {
  description = <<-EOT
    Outbound connectivity mode for tenant workloads:
      - `isolated`    : no NAT, no internet access. Workloads can only
                        reach AWS services via VPC endpoints (which are
                        intentionally not provisioned by this module).
      - `egress_only` : single NAT gateway provisioned; workloads attach
                        the egress security group to reach the internet.

    Wider modes (shared egress through Transit Gateway, peered
    tenant-to-tenant, etc.) are intentionally out of scope for this
    code sample - those would warrant a separate connectivity module
    that this one composes with.
  EOT
  type        = string
  default     = "egress_only"

  validation {
    condition     = contains(["isolated", "egress_only"], var.connectivity)
    error_message = "connectivity must be one of: isolated, egress_only."
  }
}

# --- Tagging --------------------------------------------------------------

variable "extra_tags" {
  description = <<-EOT
    Additional tags merged onto every resource the module creates. The
    module's required tags (tenant, managed_by, module) WIN on conflict
    by design - the caller cannot override them, because the IAM boundary
    is keyed off the `tenant` tag and silent override would silently
    break isolation.
  EOT
  type        = map(string)
  default     = {}
}
