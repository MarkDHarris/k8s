# =============================================================================
# CLUSTER MODULE: variables.tf
# =============================================================================
# Input variables for cluster provisioning. Users customize behavior via:
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
# =============================================================================


# -----------------------------------------------------------------------------
# Node Counts
# -----------------------------------------------------------------------------

variable "control_plane_count" {
  description = <<-EOT
    Number of control-plane nodes to create.
    
    - 1 node  = single control-plane (no HA, simplest setup)
    - 2 nodes = basic HA (survives failure of one control-plane)
    - 3 nodes = production-like HA (etcd quorum tolerates 1 failure)
    
    The FIRST control-plane node is always configured as the ingress-ready
    leader with host port mappings (80/443). Additional control-plane nodes
    are plain HA members.
    
    TERRAFORM CONCEPT: Validation Blocks
    The validation block below rejects values less than 1 at plan time,
    before any resources are created.
  EOT
  type    = number
  default = 2

  validation {
    condition     = var.control_plane_count >= 1
    error_message = "At least 1 control-plane node is required."
  }
}

variable "worker_count" {
  description = <<-EOT
    Number of worker nodes to create.
    
    - 0 nodes = control-plane-only cluster (workloads run on CP nodes)
    - 1 node  = single worker (general-purpose with storage mount demo)
    - 2 nodes = first worker gets storage mount, last gets GPU taint demo
    - 3+ nodes = middle workers are plain general-purpose nodes
    
    The FIRST worker always demonstrates extra_mounts (host /tmp mounted
    into the node). When there are 2+ workers, the LAST worker demonstrates
    taints (dedicated=gpu:NoSchedule) to simulate a GPU node pool.
  EOT
  type    = number
  default = 3

  validation {
    condition     = var.worker_count >= 0
    error_message = "Worker count must be 0 or greater."
  }
}


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
  type    = string
  default = "dev-cluster"
}

variable "k8s_version" {
  description = <<-EOT
    Kind node image that determines the Kubernetes version.
    Format: "kindest/node:vX.Y.Z"
    
    Available images: https://hub.docker.com/r/kindest/node/tags
    
    LEARNING TIP: Try changing this to an older version and running
    `terraform plan` to see how Terraform handles the diff. Since Kind
    doesn't support in-place updates, it will show a destroy-and-recreate plan.
  EOT
  type    = string
  default = "kindest/node:v1.35.0"
}

variable "kubeconfig_path" {
  description = <<-EOT
    (Optional) Custom file path to write the kubeconfig. When null, Kind uses
    its default location. Useful for managing multiple cluster configs.
    
    Example: pathexpand("~/.kube/kind-dev-config")
    TIP: Remember to use pathexpand() for paths containing "~".
  EOT
  type    = string
  default = null
}
