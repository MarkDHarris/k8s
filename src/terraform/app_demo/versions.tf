# =============================================================================
# APP DEMO: versions.tf
# =============================================================================
# Provider versions for application deployment.
#
# This module only needs the kubernetes and helm providers -- it does NOT
# need the Kind provider because it doesn't manage the cluster lifecycle.
# The cluster is created by the sibling ../cluster/ terraform.
#
# TERRAFORM CONCEPT: Minimal Provider Dependencies
# Each root module should only declare the providers it actually uses.
# This keeps `terraform init` fast, reduces the attack surface, and makes
# the dependency graph clear. The cluster module uses `tehcyx/kind`; this
# module uses `hashicorp/helm` and `hashicorp/kubernetes`.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "2.15.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.32.0"
    }
  }
}
