terraform {
  # 1.5.7 is the floor for `validation` blocks referencing the variable
  # they live on, plus stable support for `optional()` defaults. The
  # mutual-exclusivity preconditions below need 1.5+ as well.
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
