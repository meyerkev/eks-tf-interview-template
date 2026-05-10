data "aws_availability_zones" "available" {
  state = "available"

  # Skip opt-in zones (Local Zones, Wavelength). They have weird latency
  # and pricing characteristics; tenant workloads should land in standard
  # AZs by default and opt into Local Zones via a separate workflow.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  # Single source of truth for resource names so module-managed resources
  # are easy to find via the AWS console / CLI by tenant.
  name_prefix = "tenant-${var.tenant_id}"

  availability_zones = slice(
    data.aws_availability_zones.available.names,
    0,
    var.availability_zone_count,
  )

  # Required tags - the IAM boundary keys off `tenant`; the others are for
  # operability (cost allocation, blast-radius traceback). Caller's
  # `extra_tags` is merged underneath so they cannot silently override.
  required_tags = {
    tenant     = var.tenant_id
    managed_by = "terraform"
    module     = "tenant-isolation"
  }

  tags = merge(var.extra_tags, local.required_tags)
}
