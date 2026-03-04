# =============================================================================
# MODULE: kind-cluster -- versions.tf
# =============================================================================
# This file declares the provider dependencies for this child module.
#
# TERRAFORM CONCEPT: Provider Requirements in Modules
# Child modules should declare which providers they need but should NOT
# configure them (no `provider "kind" { ... }` block). Provider configuration
# is the responsibility of the ROOT module. The child module just says
# "I need the kind provider version >= 0.7.0" and the root module supplies
# the configured provider instance.
#
# WHY ">= 0.7.0"?
# This module uses features available since Kind provider v0.7.0:
#   - kind_cluster resource with full kind_config support
#   - Node labels support
#   - Runtime config and feature gates
# Using ">=" allows the root module to pin a specific version while this
# module just declares the minimum it needs to function.
# =============================================================================

terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = ">= 0.7.0"
    }
  }
}
