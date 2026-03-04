# =============================================================================
# CLUSTER MODULE: versions.tf
# =============================================================================
# Pins the Terraform CLI version and provider versions for cluster provisioning.
#
# TERRAFORM CONCEPT: Version Constraints
#   - "= X.Y.Z"  : Exact version (most restrictive, most reproducible)
#   - ">= X.Y.Z" : Minimum version (allows upgrades)
#   - "~> X.Y"    : Pessimistic constraint (allows X.Y.* but not X.(Y+1).0)
#   - "~> X.Y.Z"  : Allows X.Y.Z through X.Y.* (patch upgrades only)
#
# TERRAFORM CONCEPT: Lock File (.terraform.lock.hcl)
# After `terraform init`, Terraform creates .terraform.lock.hcl recording
# the exact versions and hashes of downloaded providers. This file SHOULD
# be committed to version control for reproducible builds.
#
# This project only needs the Kind provider -- no kubernetes or helm providers
# are needed since no workloads are deployed here. The cluster is a pure
# infrastructure concern; application deployment lives in ../app_demo/.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "0.7.0"
    }
  }
}
