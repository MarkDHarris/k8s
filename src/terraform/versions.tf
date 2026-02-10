# =============================================================================
# ROOT MODULE: versions.tf
# =============================================================================
# This file pins the exact Terraform CLI version and provider versions used
# by this project. Version pinning ensures reproducible builds -- everyone
# on the team (and CI/CD) uses identical provider binaries.
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
# be committed to version control to ensure everyone uses identical binaries.
#
# PROVIDERS IN THIS PROJECT:
#   1. tehcyx/kind       - Creates local Kubernetes clusters using Kind
#   2. hashicorp/helm    - Deploys Helm charts to Kubernetes clusters
#   3. hashicorp/kubernetes - Manages Kubernetes resources directly
# =============================================================================

terraform {
  # Minimum Terraform CLI version required.
  # Features used from Terraform >= 1.5.0:
  #   - optional() with defaults in variable type definitions
  #   - check blocks (available but not used here yet)
  #   - import blocks (available but not used here yet)
  required_version = ">= 1.5.0"

  required_providers {
    # Kind Provider (tehcyx/kind)
    # Creates and manages local Kubernetes clusters via Kind.
    # Resources: kind_cluster, kind_load
    # Registry: https://registry.terraform.io/providers/tehcyx/kind/latest
    kind = {
      source  = "tehcyx/kind"
      version = "0.7.0"
    }

    # Helm Provider (hashicorp/helm)
    # Deploys Helm charts into Kubernetes clusters.
    # Used here to install the NGINX Ingress Controller.
    # Registry: https://registry.terraform.io/providers/hashicorp/helm/latest
    helm = {
      source  = "hashicorp/helm"
      version = "2.15.0"
    }

    # Kubernetes Provider (hashicorp/kubernetes)
    # Manages native Kubernetes resources (Deployments, Services, etc.).
    # Configured here but available for extending the project with
    # additional Kubernetes resources beyond what Helm provides.
    # Registry: https://registry.terraform.io/providers/hashicorp/kubernetes/latest
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.32.0"
    }
  }
}
