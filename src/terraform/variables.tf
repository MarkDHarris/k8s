# =============================================================================
# ROOT MODULE: variables.tf
# =============================================================================
# These are the top-level input variables for the entire project. Users
# customize cluster behavior by setting these variables via:
#
#   1. terraform.tfvars file (most common for persistent settings)
#   2. Command line: terraform apply -var="cluster_name=my-cluster"
#   3. Environment variables: TF_VAR_cluster_name=my-cluster
#   4. .auto.tfvars files (automatically loaded)
#
# TERRAFORM CONCEPT: Variable Precedence (highest to lowest)
#   1. -var and -var-file on the command line
#   2. *.auto.tfvars files (alphabetical order)
#   3. terraform.tfvars
#   4. Environment variables (TF_VAR_*)
#   5. Default values in variable blocks
#
# These root variables are passed to the child module (modules/kind-cluster)
# in main.tf. The root module acts as the "glue" that connects user inputs
# to the module's API.
# =============================================================================


# -----------------------------------------------------------------------------
# Cluster Identity & Version
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = <<-EOT
    Name for the Kind cluster. This name is used as:
      - Docker container name prefix ("kind-<name>-control-plane", etc.)
      - kubectl context name ("kind-<name>")
      - Reference in terraform outputs and state
    
    Must be a valid DNS label: lowercase letters, numbers, and hyphens.
    
    To run multiple clusters simultaneously, each needs a unique name.
  EOT
  type        = string
  default     = "dev-cluster"
}

variable "k8s_version" {
  description = <<-EOT
    Kind node image that determines the Kubernetes version.
    Format: "kindest/node:vX.Y.Z"
    
    Available images: https://hub.docker.com/r/kindest/node/tags
    
    LEARNING TIP: Try changing this to an older version (e.g., "kindest/node:v1.29.0")
    and running `terraform plan` to see how Terraform handles the diff. Since Kind
    doesn't support in-place updates, it will show a destroy-and-recreate plan.
  EOT
  type        = string
  default     = "kindest/node:v1.31.0"
}

variable "kubeconfig_path" {
  description = <<-EOT
    (Optional) Custom file path to write the kubeconfig. When null, Kind uses
    its default location. Useful for managing multiple cluster configs.
    
    Example: pathexpand("~/.kube/kind-dev-config")
    
    TIP: Remember to use pathexpand() for paths containing "~".
  EOT
  type        = string
  default     = null
}


# -----------------------------------------------------------------------------
# Docker Image Loading (Future Feature)
# -----------------------------------------------------------------------------
# The Kind provider's source code includes a `kind_load` resource for loading
# local Docker images into the cluster. As of v0.10.0 it has NOT been included
# in any published release. See Section 4 of main.tf for workarounds.
#
# Once released, you would add a variable like:
#   variable "load_docker_images" {
#     type    = list(string)
#     default = []
#   }
# And a kind_load resource in main.tf using for_each.
# -----------------------------------------------------------------------------
