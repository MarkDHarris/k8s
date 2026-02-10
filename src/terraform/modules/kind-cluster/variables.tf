# =============================================================================
# MODULE: kind-cluster -- variables.tf
# =============================================================================
# This file defines every input variable the kind-cluster module accepts.
# Variables are the "API surface" of a Terraform module: callers (the root
# module in main.tf) pass values in, and this module uses them to configure
# the Kind cluster resource.
#
# Terraform variable blocks support:
#   - description : human-readable docs (shown in `terraform plan` output)
#   - type        : enforces the shape of data (string, number, bool, object, list, map)
#   - default     : value used when the caller does not provide one
#   - validation  : custom rules that reject bad input early
#   - sensitive   : hides values from CLI output (useful for secrets)
#   - nullable    : whether the variable can be set to null (default true)
#
# LEARNING TIP: The `optional()` function inside object types lets you define
# fields that callers can omit. The second argument to optional() sets a
# default value when the field is omitted, preventing null-reference errors
# in the resource block.
# =============================================================================


# -----------------------------------------------------------------------------
# Cluster Identity
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = <<-EOT
    Name of the Kind cluster. This becomes the Docker container name prefix
    and the kubectl context name (prefixed with "kind-"). Must be unique if
    running multiple Kind clusters simultaneously.
    
    Example: "dev-cluster" creates context "kind-dev-cluster"
  EOT
  type        = string
  default     = "enterprise-cluster"

  validation {
    # Kind cluster names must be valid DNS labels (RFC 1123).
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$", var.cluster_name))
    error_message = "Cluster name must be a valid DNS label: lowercase alphanumeric and hyphens, 2-63 chars."
  }
}

variable "kubernetes_version" {
  description = <<-EOT
    The Kind node Docker image to use, which determines the Kubernetes version.
    Format: "kindest/node:vX.Y.Z"
    
    Find available versions at: https://hub.docker.com/r/kindest/node/tags
    
    Examples:
      - "kindest/node:v1.35.0"  (Kubernetes 1.35)
      - "kindest/node:v1.31.0"  (Kubernetes 1.31)
      - "kindest/node:v1.30.0"  (Kubernetes 1.30)
      - "kindest/node:v1.29.0"  (Kubernetes 1.29)
  EOT
  type        = string
  default     = "kindest/node:v1.35.0"
}

variable "kubeconfig_path" {
  description = <<-EOT
    (Optional) File path where the generated kubeconfig will be written.
    If not set, Kind writes to its default location (~/.kube/config or merges
    into existing config).
    
    KIND PROVIDER FEATURE: kubeconfig_path
    
    IMPORTANT: If your path contains "~", you must wrap it with Terraform's
    pathexpand() function in the calling module, e.g.:
      kubeconfig_path = pathexpand("~/my-cluster-config")
    
    This is because Terraform does not automatically expand shell tilde notation.
  EOT
  type        = string
  default     = null # null means "use Kind's default behavior"
}


# -----------------------------------------------------------------------------
# Networking Configuration
# -----------------------------------------------------------------------------
# The networking block maps directly to the Kind `networking` config section.
# It controls how the virtual Kubernetes cluster's network is configured,
# including IP ranges for Pods and Services, the API server binding, CNI
# plugin behavior, and IP family (IPv4/IPv6/DualStack).
#
# KIND PROVIDER FEATURES DEMONSTRATED:
#   - api_server_address  : Bind address for the API server
#   - api_server_port     : Port the API server listens on
#   - pod_subnet          : CIDR range allocated to Pod IPs
#   - service_subnet      : CIDR range allocated to ClusterIP Services
#   - disable_default_cni : Disable kindnet to install your own CNI (e.g., Calico, Cilium)
#   - kube_proxy_mode     : Proxy mode: "iptables", "ipvs", or "none"
#   - ip_family           : IP stack: "ipv4", "ipv6", or "dual"
#   - dns_search          : Custom DNS search domains for all containers
# -----------------------------------------------------------------------------

variable "networking" {
  description = <<-EOT
    Custom networking configuration for the Kind cluster. Every field is
    optional; omitted fields use Kind's defaults.
    
    Fields:
      api_server_address  - IP the API server binds to (default: "127.0.0.1").
                            WARNING: Changing this from 127.0.0.1 has security
                            implications as it exposes the API server.
      api_server_port     - Port for the API server (default: random open port).
                            Setting a fixed port (e.g. 6443) is useful for
                            consistent kubeconfig but means only one cluster
                            can use that port.
      pod_subnet          - CIDR for Pod IPs (default: "10.244.0.0/16").
      service_subnet      - CIDR for Service ClusterIPs (default: "10.96.0.0/12").
      disable_default_cni - Set to true to disable kindnet and install your
                            own CNI like Calico or Cilium (default: false).
      kube_proxy_mode     - "iptables" (default), "ipvs", or "none".
                            Use "none" when running a CNI that replaces
                            kube-proxy (e.g. Cilium in kube-proxy-free mode).
      ip_family           - "ipv4" (default), "ipv6", or "dual" for dual-stack.
                            Dual-stack assigns both IPv4 and IPv6 addresses to
                            Pods and Services.
      dns_search          - List of DNS search domains added to all containers.
                            Useful for short-name resolution in corporate
                            environments (e.g. ["corp.example.com"]).
  EOT
  type = object({
    api_server_address  = optional(string)
    api_server_port     = optional(number)
    pod_subnet          = optional(string)
    service_subnet      = optional(string)
    disable_default_cni = optional(bool)
    kube_proxy_mode     = optional(string) # "iptables", "ipvs", or "none"
    ip_family           = optional(string) # "ipv4", "ipv6", or "dual"
    dns_search          = optional(list(string))
  })
  default = {}
}


# -----------------------------------------------------------------------------
# Containerd Configuration Patches
# -----------------------------------------------------------------------------
# Kind uses containerd as its container runtime inside each node. These patches
# are raw TOML strings appended to containerd's config.
#
# KIND PROVIDER FEATURE: containerd_config_patches
# The provider validates these as valid TOML before applying.
#
# IMPORTANT -- CONTAINERD V2.x BREAKING CHANGE:
# kindest/node images for Kubernetes v1.34+ ship containerd v2.x, which
# REMOVED the `registry.mirrors` section from the CRI plugin. Using the
# old format will prevent containerd from starting (kubelet health check
# timeout → kubeadm init failure).
#
# Old format (containerd v1.x ONLY -- DO NOT USE with v1.34+ images):
#   [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
#     endpoint = ["http://registry:5000"]
#
# For containerd v2.x, configure registries via the hosts directory:
#   [plugins."io.containerd.grpc.v1.cri".registry]
#     config_path = "/etc/containerd/certs.d"
# Then mount host-side /etc/containerd/certs.d/<registry>/hosts.toml files
# into nodes using extra_mounts.
# See: https://kind.sigs.k8s.io/docs/user/local-registry/
# -----------------------------------------------------------------------------

variable "containerd_config_patches" {
  description = <<-EOT
    List of raw TOML patches applied to containerd configuration on every node.
    
    WARNING: kindest/node v1.34+ ships containerd v2.x which removed
    registry.mirrors from the CRI config. Using the old mirror format will
    break the kubelet. See the variable comment block for the v2-compatible
    approach using config_path + hosts directory.
    
    For non-registry patches (e.g. snapshotter config), the TOML path
    plugins."io.containerd.grpc.v1.cri" still works for other settings.
  EOT
  type        = list(string)
  default     = []
}


# -----------------------------------------------------------------------------
# Runtime Configuration
# -----------------------------------------------------------------------------
# Maps to Kubernetes API server --runtime-config flag. Allows enabling or
# disabling specific API groups/versions at the cluster level. This is useful
# for testing alpha/beta APIs or disabling deprecated API versions.
#
# KIND PROVIDER FEATURE: runtime_config
# SPECIAL BEHAVIOR: Because HCL map keys cannot contain "/" characters, use
# "_" instead. The provider automatically converts "_" to "/" internally.
# For example: "api_alpha" becomes "api/alpha" in the actual config.
# -----------------------------------------------------------------------------

variable "runtime_config" {
  description = <<-EOT
    Map of Kubernetes runtime configuration overrides. Keys are API group/version
    strings and values are "true" or "false" to enable/disable them.
    
    IMPORTANT: Replace "/" with "_" in keys because HCL does not allow "/"
    in map keys. The Kind provider converts "_" back to "/" automatically.
    
    Examples:
      runtime_config = {
        "api_alpha" = "true"   # Becomes api/alpha=true (enable alpha APIs)
      }
  EOT
  type        = map(string)
  default     = {}
}


# -----------------------------------------------------------------------------
# Feature Gates
# -----------------------------------------------------------------------------
# Maps to Kubernetes --feature-gates flag. Feature gates are key=value pairs
# that toggle experimental or alpha/beta Kubernetes features. They let you
# test upcoming Kubernetes features before they become stable/GA.
#
# KIND PROVIDER FEATURE: feature_gates
# -----------------------------------------------------------------------------

variable "feature_gates" {
  description = <<-EOT
    Map of Kubernetes feature gates to enable or disable. Keys are feature
    names, values are "true" or "false".
    
    These map to the --feature-gates flag on Kubernetes components. Useful
    for testing alpha/beta features in a local development cluster.
    
    Examples:
      feature_gates = {
        "EphemeralContainers"         = "true"   # Enable ephemeral debug containers
        "GracefulNodeShutdown"        = "true"   # Enable graceful shutdown
        "TopologyAwareHints"          = "true"   # Enable topology-aware routing
      }
    
    Find the full list of feature gates for your Kubernetes version at:
    https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/
  EOT
  type        = map(string)
  default     = {}
}


# -----------------------------------------------------------------------------
# Node Definitions
# -----------------------------------------------------------------------------
# Each entry in this list creates a Docker container acting as a Kubernetes
# node. The Kind provider supports two roles: "control-plane" and "worker".
#
# KIND PROVIDER NODE FEATURES DEMONSTRATED:
#   - role                   : "control-plane" or "worker"
#   - image                  : Per-node image override (e.g. test mixed versions)
#   - kubeadm_config_patches : Raw YAML patches for kubeadm InitConfiguration
#                              or JoinConfiguration (labels, taints, extra args)
#   - labels                 : Direct node labels (map of key=value strings).
#                              This is the provider-native way to label nodes,
#                              as an alternative to kubeadm_config_patches.
#   - extra_mounts           : Bind-mount host directories into node containers
#     - host_path            : Path on the Docker host
#     - container_path       : Path inside the node container
#     - read_only            : Mount as read-only (default: false)
#     - propagation          : Mount propagation mode:
#                              "None", "HostToContainer", or "Bidirectional"
#     - selinux_relabel      : Relabel mount for SELinux (default: false)
#   - extra_port_mappings    : Forward ports from host to node containers
#     - container_port       : Port inside the container
#     - host_port            : Port on the Docker host
#     - listen_address       : Host IP to bind (default: "0.0.0.0")
#     - protocol             : "TCP" (default), "UDP", or "SCTP"
#
# LEARNING TIP: Multiple control-plane nodes create an HA (High Availability)
# cluster with an etcd cluster and load-balanced API server.
# -----------------------------------------------------------------------------

variable "nodes" {
  description = <<-EOT
    List of node configurations for the Kind cluster. Each object defines
    one Docker container that acts as a Kubernetes node.
    
    Required fields:
      role - "control-plane" or "worker"
    
    Optional fields:
      image                  - Override the node image for this specific node
      kubeadm_config_patches - List of YAML patches for kubeadm configuration
      labels                 - Map of labels to apply directly to the node
      extra_mounts           - List of host-to-container bind mounts
      extra_port_mappings    - List of host-to-container port forwards
    
    HA Clusters: Include 2+ control-plane nodes for high availability.
    The first control-plane runs etcd leader + API server; additional ones
    join as secondary control-plane members.
  EOT
  type = list(object({
    # --- Core Node Settings ---
    role  = string           # "control-plane" or "worker" (REQUIRED)
    image = optional(string) # Per-node image override (default: cluster-level node_image)

    # --- Kubeadm Configuration Patches ---
    # Raw YAML strings patched into kubeadm's InitConfiguration (first control-plane)
    # or JoinConfiguration (workers and additional control-planes).
    # Common uses: adding node labels, taints, extra kubelet args.
    kubeadm_config_patches = optional(list(string), [])

    # --- Node Labels (Provider-Native) ---
    # Direct label assignment via the Kind provider, as an alternative to
    # kubeadm_config_patches. These are applied as Kubernetes node labels.
    # Example: { "workload-type" = "gpu", "environment" = "dev" }
    labels = optional(map(string), {})

    # --- Extra Mounts ---
    # Bind-mount directories from the Docker host into the node container.
    # This is how you provide persistent storage or inject config files
    # into your Kind nodes. The data persists across pod restarts but NOT
    # across cluster recreation (terraform destroy + apply).
    extra_mounts = optional(list(object({
      host_path       = string                # Path on Docker host
      container_path  = string                # Path inside node container
      read_only       = optional(bool, false) # Mount read-only?
      propagation     = optional(string)      # "None", "HostToContainer", or "Bidirectional"
      selinux_relabel = optional(bool, false) # Relabel for SELinux contexts?
    })), [])

    # --- Extra Port Mappings ---
    # Forward ports from the Docker host to the node container. Essential
    # for exposing services (like an Ingress controller) running inside
    # Kind to your local machine.
    extra_port_mappings = optional(list(object({
      container_port = number                      # Port inside the container
      host_port      = number                      # Port on the Docker host
      listen_address = optional(string, "0.0.0.0") # Host IP to bind to
      protocol       = optional(string, "TCP")     # "TCP", "UDP", or "SCTP"
    })), [])
  }))
}
