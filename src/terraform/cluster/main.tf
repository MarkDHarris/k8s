# =============================================================================
# CLUSTER MODULE: main.tf
# =============================================================================
# This is the entry point for cluster provisioning. It creates a fully-featured,
# multi-node Kind Kubernetes cluster using every capability of the Kind provider.
#
# WHAT THIS CREATES:
#   - A Kind cluster with configurable node counts (control_plane_count + worker_count)
#   - Custom networking (pod/service CIDRs, proxy mode)
#   - Node labels, taints, mounts, and port mappings
#   - Port forwarding for ingress traffic (80/443 → control-plane)
#
# WHAT THIS DOES NOT CREATE:
#   - No applications or workloads (see ../app_demo/ for that)
#   - No Helm releases or Kubernetes resources
#   - The cluster is a clean, empty Kubernetes environment
#
# USAGE:
#   cd cluster/
#   terraform init
#   terraform apply
#
# NODE GENERATION STRATEGY:
#   Node counts are controlled by var.control_plane_count and var.worker_count.
#   The node list is built dynamically in the locals block:
#
#   Control-plane nodes:
#     - CP #1 (always): ingress-ready label + host port mappings (80/443)
#     - CP #2..N:        plain HA members with sequential labels
#
#   Worker nodes:
#     - Worker #1 (always): general-purpose with storage mount demo
#     - Worker #2..N-1:     plain general-purpose
#     - Worker #N (last, if >= 2): GPU-tainted (demonstrates taints)
#
# DEPENDENCY GRAPH:
#   variables → locals (node generation) → module "k8s_cluster" → outputs
#
# TERRAFORM CONCEPT: Module Calls
# `module "name" { source = "path" }` instantiates a module. The `source`
# can be a local path, a Git URL, a Terraform Registry module, or an S3 bucket.
# Local paths (starting with "./" or "../") are relative to this file.
# =============================================================================


# =============================================================================
# SECTION 1: Dynamic Node Generation
# =============================================================================
# TERRAFORM CONCEPT: Locals
# The `locals` block defines named expressions that can be referenced
# elsewhere in the module as `local.<name>`. Locals are useful for:
#   - Computing values from variables (like building a node list from counts)
#   - Avoiding repetition of complex expressions
#   - Giving meaningful names to intermediate calculations
#
# TERRAFORM CONCEPT: for Expressions
# `[for i in range(N) : { ... }]` generates a list of N objects. This is
# Terraform's equivalent of a for-loop in imperative languages. Combined
# with `concat()`, it builds a single flat list from multiple sources.
#
# TERRAFORM CONCEPT: Conditional Expressions
# `condition ? true_value : false_value` selects between two values. We use
# this to only include the GPU-tainted worker when there are 2+ workers.
# =============================================================================

locals {
  # ---------------------------------------------------------------------------
  # Control Plane #1: Ingress-Ready Leader
  # ---------------------------------------------------------------------------
  # The first control-plane node always gets:
  #   1. "ingress-ready=true" label (required by NGINX Ingress Controller)
  #   2. Host port mappings for 80/443 (ingress traffic from localhost)
  #   3. Identification labels
  cp_leader = {
    role = "control-plane"

    kubeadm_config_patches = [
      "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
    ]

    labels = {
      "node-role.example.com/ingress" = "true"
      "cluster-role"                  = "primary-control-plane"
    }

    extra_port_mappings = [
      {
        container_port = 80
        host_port      = 80
        listen_address = "0.0.0.0"
        protocol       = "TCP"
      },
      {
        container_port = 443
        host_port      = 443
        listen_address = "0.0.0.0"
        protocol       = "TCP"
      }
    ]
  }

  # ---------------------------------------------------------------------------
  # Control Planes #2..N: HA Secondary Members
  # ---------------------------------------------------------------------------
  # Additional control-plane nodes create High Availability:
  #   - etcd runs on all control-plane nodes (replicated)
  #   - An internal load balancer distributes API server requests
  #   - The cluster survives the failure of floor(N/2) control-plane nodes
  cp_secondary = [
    for i in range(var.control_plane_count - 1) : {
      role = "control-plane"
      labels = {
        "cluster-role" = "secondary-control-plane"
      }
    }
  ]

  # ---------------------------------------------------------------------------
  # Worker #1: General-Purpose with Storage Mount
  # ---------------------------------------------------------------------------
  # The first worker always demonstrates extra_mounts with ALL supported
  # attributes: host_path, container_path, read_only, propagation, selinux_relabel.
  worker_with_storage = var.worker_count >= 1 ? [{
    role = "worker"

    labels = {
      "workload-type" = "general"
      "has-storage"   = "true"
    }

    extra_mounts = [
      {
        host_path       = "/tmp"
        container_path  = "/var/local-data"
        read_only       = false
        propagation     = "None"
        selinux_relabel = false
      }
    ]
  }] : []

  # ---------------------------------------------------------------------------
  # Workers #2..N-1: Plain General-Purpose
  # ---------------------------------------------------------------------------
  # Middle workers are clean, general-purpose nodes with no special config.
  # When worker_count=2 there are 0 middle workers (just storage + GPU).
  # When worker_count=5 there are 3 middle workers.
  worker_plain_count = max(0, var.worker_count - 2)
  workers_plain = [
    for i in range(local.worker_plain_count) : {
      role = "worker"
      labels = {
        "workload-type" = "general"
      }
    }
  ]

  # ---------------------------------------------------------------------------
  # Worker #N (last): GPU-Tainted Specialized Node
  # ---------------------------------------------------------------------------
  # The last worker (when there are 2+) demonstrates taints. The taint
  # "dedicated=gpu:NoSchedule" means only pods with a matching toleration
  # are scheduled here. This simulates a dedicated GPU/spot/ARM node pool.
  worker_gpu = var.worker_count >= 2 ? [{
    role = "worker"

    labels = {
      "workload-type"         = "gpu"
      "hardware-acceleration" = "true"
    }

    kubeadm_config_patches = [
      "kind: JoinConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    register-with-taints: \"dedicated=gpu:NoSchedule\"\n"
    ]
  }] : []

  # ---------------------------------------------------------------------------
  # Combined Node List
  # ---------------------------------------------------------------------------
  # TERRAFORM CONCEPT: concat()
  # Joins multiple lists into a single flat list. The order matters: Kind
  # uses the first control-plane as the cluster initializer (etcd leader).
  nodes = concat(
    [local.cp_leader],
    local.cp_secondary,
    local.worker_with_storage,
    local.workers_plain,
    local.worker_gpu,
  )
}


# =============================================================================
# SECTION 2: Kind Cluster Module
# =============================================================================

module "k8s_cluster" {
  source = "./modules/kind-cluster"

  # --- Cluster Identity ---
  cluster_name       = var.cluster_name
  kubernetes_version = var.k8s_version
  kubeconfig_path    = var.kubeconfig_path

  # ---------------------------------------------------------------------------
  # KIND PROVIDER FEATURE: Networking Customization
  # ---------------------------------------------------------------------------
  # Every field here demonstrates a different networking capability of the Kind
  # provider. Modify these and run `terraform plan` to see how the cluster
  # configuration changes. Kind clusters don't support in-place updates, so
  # changes will destroy and recreate.
  networking = {
    api_server_port = 6443
    pod_subnet      = "10.200.0.0/16"
    service_subnet  = "10.100.0.0/16"
    kube_proxy_mode = "iptables"

    # Uncomment to test dual-stack networking:
    # ip_family = "dual"

    # Uncomment to add custom DNS search domains:
    # dns_search = ["corp.example.com", "internal.local"]
  }

  # ---------------------------------------------------------------------------
  # KIND PROVIDER FEATURE: Containerd Config Patches
  # ---------------------------------------------------------------------------
  # Raw TOML patches applied to containerd on all nodes.
  #
  # IMPORTANT: containerd v2.x (shipped in kindest/node v1.34+) REMOVED the
  # registry.mirrors section from the CRI plugin config. For containerd v2.x,
  # configure registry mirrors using the hosts directory approach instead.
  # See: https://kind.sigs.k8s.io/docs/user/local-registry/
  # containerd_config_patches = []

  # ---------------------------------------------------------------------------
  # KIND PROVIDER FEATURE: Runtime Config (Kubernetes API Overrides)
  # ---------------------------------------------------------------------------
  # Uncomment to enable alpha APIs or disable specific API groups.
  # Remember: Use "_" instead of "/" in keys (provider converts automatically).
  #
  # runtime_config = {
  #   "api_alpha" = "true"
  # }

  # ---------------------------------------------------------------------------
  # KIND PROVIDER FEATURE: Feature Gates (Kubernetes Feature Toggles)
  # ---------------------------------------------------------------------------
  # Uncomment to enable specific Kubernetes feature gates.
  # Full list: https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/
  #
  # feature_gates = {
  #   "GracefulNodeShutdown" = "true"
  # }

  # ---------------------------------------------------------------------------
  # Node Definitions (dynamically generated)
  # ---------------------------------------------------------------------------
  # The node list is built in the locals block above from
  # var.control_plane_count and var.worker_count. See Section 1 for the
  # generation logic and what each node type includes.
  #
  # Default (2 CP + 2 workers) produces:
  #   - CP #1: ingress-ready, ports 80/443
  #   - CP #2: HA secondary
  #   - Worker #1: general, storage mount /tmp → /var/local-data
  #   - Worker #2: GPU taint (dedicated=gpu:NoSchedule)
  nodes = local.nodes
}


# =============================================================================
# Docker Image Loading (kind_load) -- UPCOMING FEATURE
# =============================================================================
# The Kind provider's source code includes a `kind_load` resource that loads
# Docker images from the local Docker daemon into the Kind cluster's nodes.
#
# IMPORTANT: As of provider v0.10.0, `kind_load` is only available on the
# unreleased master branch. Once released, you can use:
#
#   resource "kind_load" "images" {
#     for_each     = toset(var.load_docker_images)
#     image        = each.value
#     cluster_name = module.k8s_cluster.cluster_name
#     depends_on   = [module.k8s_cluster]
#   }
#
# WORKAROUND: Use the CLI after terraform apply:
#   kind load docker-image myapp:latest --name dev
# =============================================================================
