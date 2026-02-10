# =============================================================================
# MODULE: kind-cluster -- main.tf
# =============================================================================
# This is the core of the Kind cluster module. It defines a single resource
# -- `kind_cluster` -- that creates a local Kubernetes cluster using
# Kubernetes IN Docker (Kind).
#
# HOW KIND WORKS:
#   Kind creates Docker containers that act as Kubernetes "nodes". Each
#   container runs kubelet, a container runtime (containerd), and etcd
#   (on control-plane nodes). This gives you a real, multi-node Kubernetes
#   cluster running entirely in Docker on your local machine.
#
# PROVIDER RESOURCE: kind_cluster
#   This is the ONLY resource type in the Kind provider (besides kind_load).
#   It supports CREATE and DELETE but NOT UPDATE -- any configuration change
#   forces a full cluster replacement (destroy + recreate). This is by design
#   because Kind clusters are ephemeral development environments.
#
# ALL KIND PROVIDER kind_config FEATURES USED IN THIS MODULE:
#   1.  name                     - Cluster name (becomes Docker container prefix)
#   2.  node_image               - Docker image determining Kubernetes version
#   3.  wait_for_ready           - Block until cluster is healthy
#   4.  kubeconfig_path          - Custom kubeconfig file output location
#   5.  kind_config.kind         - Config type identifier ("Cluster")
#   6.  kind_config.api_version  - Config API version
#   7.  kind_config.containerd_config_patches - Raw TOML containerd patches
#   8.  kind_config.runtime_config   - Kubernetes API runtime config overrides
#   9.  kind_config.feature_gates    - Kubernetes feature gate toggles
#   10. kind_config.networking       - Full networking configuration block:
#       a. api_server_address    - API server bind IP
#       b. api_server_port       - API server port
#       c. pod_subnet            - Pod CIDR range
#       d. service_subnet        - Service CIDR range
#       e. disable_default_cni   - Toggle default CNI (kindnet)
#       f. kube_proxy_mode       - Proxy mode (iptables/ipvs/none)
#       g. ip_family             - IP stack (ipv4/ipv6/dual)
#       h. dns_search            - Custom DNS search domains
#   11. kind_config.node (dynamic) - Per-node configuration:
#       a. role                  - control-plane or worker
#       b. image                 - Per-node image override
#       c. kubeadm_config_patches - Kubeadm YAML patches
#       d. labels                - Direct node label assignment
#       e. extra_mounts          - Host directory bind mounts:
#          i.   host_path        - Source path on host
#          ii.  container_path   - Destination path in container
#          iii. read_only        - Read-only flag
#          iv.  propagation      - Mount propagation mode
#          v.   selinux_relabel  - SELinux relabel flag
#       f. extra_port_mappings   - Host-to-container port forwards:
#          i.   container_port   - Container port
#          ii.  host_port        - Host port
#          iii. listen_address   - Host bind IP
#          iv.  protocol         - TCP/UDP/SCTP
#
# COMPUTED OUTPUTS (read-only attributes after creation):
#   - endpoint              : Kubernetes API server URL
#   - client_certificate    : TLS client cert (base64 PEM)
#   - client_key            : TLS client key (base64 PEM)
#   - cluster_ca_certificate: Cluster CA cert (base64 PEM)
#   - kubeconfig            : Full kubeconfig YAML string
# =============================================================================


resource "kind_cluster" "this" {
  # ---------------------------------------------------------------------------
  # TOP-LEVEL RESOURCE ARGUMENTS
  # ---------------------------------------------------------------------------

  # KIND PROVIDER FEATURE: name (Required)
  # The cluster name. This becomes:
  #   - Docker container name prefix: "kind-<name>-control-plane", "kind-<name>-worker", etc.
  #   - kubectl context name: "kind-<name>"
  #   - Docker network name: "kind"
  name = var.cluster_name

  # KIND PROVIDER FEATURE: node_image (Optional)
  # The Docker image used for ALL nodes (unless overridden per-node).
  # This image bundles a specific Kubernetes version with all its dependencies.
  # Format: "kindest/node:vX.Y.Z" -- find tags at https://hub.docker.com/r/kindest/node/tags
  node_image = var.kubernetes_version

  # KIND PROVIDER FEATURE: wait_for_ready (Optional, default: false)
  # When true, Terraform blocks until the Kind cluster's control plane reports
  # healthy. This is essential when other resources (like helm_release) depend
  # on the cluster being fully operational before they can be applied.
  # Without this, dependent resources may fail because the API server isn't ready.
  wait_for_ready = true

  # KIND PROVIDER FEATURE: kubeconfig_path (Optional)
  # Custom file path to write the generated kubeconfig. When null/omitted,
  # Kind uses its default behavior. Useful for CI/CD pipelines or when
  # managing multiple clusters with separate kubeconfig files.
  # NOTE: Use pathexpand() for paths with "~" -- Terraform doesn't expand tilde.
  kubeconfig_path = var.kubeconfig_path

  # ---------------------------------------------------------------------------
  # KIND CONFIG BLOCK
  # ---------------------------------------------------------------------------
  # The kind_config block maps directly to Kind's cluster configuration YAML
  # (https://kind.sigs.k8s.io/docs/user/configuration/). It controls every
  # aspect of how the cluster is provisioned.
  kind_config {
    # These two fields are required by Kind's configuration schema.
    # They identify the configuration format and version.
    kind        = "Cluster"                # Always "Cluster" for kind_cluster resources
    api_version = "kind.x-k8s.io/v1alpha4" # Current Kind config API version

    # -------------------------------------------------------------------------
    # KIND PROVIDER FEATURE: containerd_config_patches
    # -------------------------------------------------------------------------
    # List of raw TOML strings patched into containerd's configuration on
    # EVERY node in the cluster. Containerd is the container runtime inside
    # each Kind node (Docker container).
    #
    # Most common use case: Configure registry mirrors so images tagged for
    # "localhost:5000" are pulled from a local Docker registry. This avoids
    # Docker Hub rate limits and speeds up image pulls in development.
    #
    # The provider validates TOML syntax before applying, and uses diff
    # suppression so whitespace-only TOML changes don't trigger replacements.
    containerd_config_patches = var.containerd_config_patches

    # -------------------------------------------------------------------------
    # KIND PROVIDER FEATURE: runtime_config
    # -------------------------------------------------------------------------
    # Maps to the Kubernetes API server's --runtime-config flag. This is a
    # map of API group/version strings to "true"/"false", controlling which
    # API groups are enabled on the cluster.
    #
    # SPECIAL BEHAVIOR: HCL map keys cannot contain "/" characters, so use "_"
    # instead. The provider automatically converts underscores to slashes.
    # Example: { "api_alpha" = "true" } becomes --runtime-config=api/alpha=true
    #
    # Use cases:
    #   - Enable alpha APIs for testing: { "api_alpha" = "true" }
    #   - Disable legacy APIs: { "api_legacy" = "false" }
    #
    # We use `dynamic` to conditionally include this block only when the map
    # is non-empty, keeping the generated Kind config clean.
    runtime_config = length(var.runtime_config) > 0 ? var.runtime_config : null

    # -------------------------------------------------------------------------
    # KIND PROVIDER FEATURE: feature_gates
    # -------------------------------------------------------------------------
    # Maps to Kubernetes --feature-gates flag on all components (API server,
    # kubelet, controller-manager, scheduler). Feature gates toggle specific
    # Kubernetes features that are in alpha, beta, or can be disabled.
    #
    # This is invaluable for local development: test upcoming Kubernetes
    # features before they become GA, or disable features causing issues.
    #
    # Example: { "GracefulNodeShutdown" = "true" }
    # Full list: https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/
    feature_gates = length(var.feature_gates) > 0 ? var.feature_gates : null

    # -------------------------------------------------------------------------
    # KIND PROVIDER FEATURE: networking (full block)
    # -------------------------------------------------------------------------
    # Controls the virtual network configuration for the entire Kind cluster.
    # This single block exposes ALL networking options the Kind provider supports.
    networking {
      # API Server Bind Address (default: "127.0.0.1")
      # WARNING: Changing from 127.0.0.1 exposes the API server to the network.
      # Only change this if you need external access (e.g., from a VM or CI runner).
      api_server_address = try(var.networking.api_server_address, "127.0.0.1")

      # API Server Port (default: random open port)
      # Using a fixed port (6443) gives consistent kubeconfig but prevents
      # running multiple clusters on the same port simultaneously.
      api_server_port = try(var.networking.api_server_port, 6443)

      # Pod Subnet (default: "10.244.0.0/16")
      # The CIDR range from which Pod IPs are allocated. Each node gets a
      # subnet carved from this range. Customize to avoid conflicts with
      # your host network or VPN ranges.
      pod_subnet = try(var.networking.pod_subnet, "10.244.0.0/16")

      # Service Subnet (default: "10.96.0.0/12")
      # The CIDR range for Kubernetes Service ClusterIPs. The first IP in
      # this range becomes the kubernetes.default.svc ClusterIP.
      service_subnet = try(var.networking.service_subnet, "10.96.0.0/12")

      # Disable Default CNI (default: false)
      # When true, Kind will NOT install its default CNI plugin (kindnet).
      # Use this when you want to install your own CNI (Calico, Cilium, etc.)
      # after cluster creation. Nodes will be NotReady until a CNI is installed.
      disable_default_cni = try(var.networking.disable_default_cni, false)

      # Kube-Proxy Mode (default: "iptables")
      # Options: "iptables", "ipvs", or "none"
      #   - "iptables": Traditional mode, works everywhere, good for small clusters
      #   - "ipvs": Better performance for large clusters (many Services)
      #   - "none": Disable kube-proxy entirely (for CNIs like Cilium that
      #             provide their own kube-proxy replacement)
      kube_proxy_mode = try(var.networking.kube_proxy_mode, "iptables")

      # IP Family (default: "ipv4")
      # Options: "ipv4", "ipv6", or "dual"
      #   - "ipv4": Standard single-stack IPv4 networking
      #   - "ipv6": Single-stack IPv6 (requires IPv6 enabled on Docker host)
      #   - "dual": Dual-stack, assigns both IPv4 and IPv6 to Pods and Services
      # Dual-stack is useful for testing IPv6 readiness of your applications.
      ip_family = try(var.networking.ip_family, null)

      # DNS Search Domains (default: none)
      # List of DNS search domains added to /etc/resolv.conf in all containers.
      # Allows short-name DNS resolution (e.g., "myservice" resolves to
      # "myservice.corp.example.com" if "corp.example.com" is in the search list).
      dns_search = try(var.networking.dns_search, null)
    }

    # -------------------------------------------------------------------------
    # KIND PROVIDER FEATURE: node (dynamic block)
    # -------------------------------------------------------------------------
    # Each `node` block creates one Docker container acting as a Kubernetes node.
    # Using Terraform's `dynamic` block, we iterate over var.nodes to create
    # an arbitrary number of nodes with different configurations.
    #
    # TERRAFORM CONCEPT: Dynamic Blocks
    # `dynamic "node"` generates zero or more `node { ... }` blocks from a list.
    # Inside `content { }`, `node.value` refers to the current list element.
    # This is Terraform's way of generating repeated nested blocks from data.
    dynamic "node" {
      for_each = var.nodes
      content {
        # Node Role: "control-plane" or "worker"
        # Control-plane nodes run: etcd, kube-apiserver, kube-controller-manager,
        # kube-scheduler, and (optionally) workloads.
        # Worker nodes run: kubelet and workload pods only.
        # Multiple control-plane nodes create an HA cluster.
        role = node.value.role

        # Per-Node Image Override (optional)
        # Allows running different Kubernetes versions on different nodes.
        # Useful for testing version skew scenarios (e.g., upgrading workers
        # before control-plane). When null, uses the cluster-level node_image.
        image = node.value.image

        # Kubeadm Config Patches
        # Raw YAML strings patched into kubeadm's InitConfiguration (first
        # control-plane) or JoinConfiguration (workers + additional control-planes).
        # Common uses:
        #   - Add node labels: node-labels: "ingress-ready=true"
        #   - Add taints: register-with-taints: "dedicated=gpu:NoSchedule"
        #   - Set kubelet args: system-reserved: "cpu=100m,memory=100Mi"
        kubeadm_config_patches = node.value.kubeadm_config_patches

        # KIND PROVIDER FEATURE: labels (Provider-Native Node Labels)
        # Direct label assignment via the Kind provider schema. This is a
        # cleaner alternative to using kubeadm_config_patches for labels.
        # Labels are key-value pairs used for node selection, scheduling
        # constraints, and organizational metadata.
        # Example: { "topology.kubernetes.io/zone" = "us-east-1a" }
        labels = length(node.value.labels) > 0 ? node.value.labels : null

        # KIND PROVIDER FEATURE: extra_mounts (dynamic block)
        # Bind-mount directories from the Docker host filesystem into the node
        # container. This is Kind's mechanism for providing persistent storage
        # or injecting configuration files into nodes.
        #
        # Each mount specifies ALL provider-supported attributes:
        #   - host_path       : Source directory on the Docker host
        #   - container_path  : Destination inside the node container
        #   - read_only       : Write protection (default: false)
        #   - propagation     : How sub-mounts propagate:
        #       "None"            - No propagation (isolated)
        #       "HostToContainer" - Host mounts appear in container
        #       "Bidirectional"   - Mounts propagate both directions
        #   - selinux_relabel : Re-label mount for SELinux contexts (default: false)
        #                       Only relevant on SELinux-enabled hosts (RHEL, Fedora)
        dynamic "extra_mounts" {
          for_each = node.value.extra_mounts
          content {
            host_path       = extra_mounts.value.host_path
            container_path  = extra_mounts.value.container_path
            read_only       = extra_mounts.value.read_only
            propagation     = extra_mounts.value.propagation
            selinux_relabel = extra_mounts.value.selinux_relabel
          }
        }

        # KIND PROVIDER FEATURE: extra_port_mappings (dynamic block)
        # Forward ports from the Docker host to the node container. This is
        # how you make services inside Kind accessible from your local machine.
        #
        # The most common use: forward ports 80/443 to a control-plane node
        # running an Ingress controller, so `curl localhost` reaches your
        # in-cluster services.
        #
        # Each mapping specifies ALL provider-supported attributes:
        #   - container_port : Port inside the Kind node container
        #   - host_port      : Port on the Docker host (your machine)
        #   - listen_address : Host IP to bind to (default: "0.0.0.0" = all interfaces)
        #                      Use "127.0.0.1" to restrict to localhost only
        #   - protocol       : "TCP" (default), "UDP", or "SCTP"
        dynamic "extra_port_mappings" {
          for_each = node.value.extra_port_mappings
          content {
            container_port = extra_port_mappings.value.container_port
            host_port      = extra_port_mappings.value.host_port
            listen_address = extra_port_mappings.value.listen_address
            protocol       = extra_port_mappings.value.protocol
          }
        }
      }
    }
  }
}
