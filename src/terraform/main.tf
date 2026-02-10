# =============================================================================
# ROOT MODULE: main.tf
# =============================================================================
# This is the entry point for the Terraform project. It orchestrates:
#
#   1. A Kind Kubernetes cluster (via the child module in modules/kind-cluster/)
#   2. Provider configuration for kubernetes and helm (using cluster credentials)
#   3. An NGINX Ingress Controller deployment (via Helm)
#   4. A demo NGINX web server (Deployment + Service + Ingress)
#
# ARCHITECTURE OVERVIEW:
#   ┌──────────────────────────────────────────────────────────────┐
#   │  Root Module (this file)                                     │
#   │  ┌─────────────────────┐  ┌───────────────────────────────┐ │
#   │  │  Module: k8s_cluster│  │  Helm: ingress_nginx          │ │
#   │  │  (kind-cluster/)    │──│  (NGINX Ingress Controller)   │ │
#   │  │                     │  └───────────────┬───────────────┘ │
#   │  │  Creates:           │                  │ routes to        │
#   │  │  - 2 control-planes │  ┌───────────────▼───────────────┐ │
#   │  │  - 2 workers        │  │  Demo: nginx                  │ │
#   │  │  - networking       │  │  (Deployment+Service+Ingress) │ │
#   │  └─────────────────────┘  │  → curl http://localhost      │ │
#   │                           └───────────────────────────────┘ │
#   └──────────────────────────────────────────────────────────────┘
#
# HOW TERRAFORM MODULES WORK:
# A module is a container for related resources. The root module (this file)
# calls the child module (modules/kind-cluster/) by passing input variables.
# The child module creates resources and exposes outputs. The root module
# uses those outputs to configure other resources and providers.
#
# DEPENDENCY GRAPH:
#   kind_cluster (module) → kubernetes/helm providers → helm_release (ingress)
#                                                     → namespace/deployment/service/ingress (demo nginx)
# =============================================================================


# =============================================================================
# SECTION 1: Kind Cluster (Child Module)
# =============================================================================
# This module call creates the entire Kubernetes cluster. All the variables
# below map to the module's input variables defined in
# modules/kind-cluster/variables.tf.
#
# TERRAFORM CONCEPT: Module Calls
# `module "name" { source = "path" }` instantiates a module. The `source`
# can be a local path, a Git URL, a Terraform Registry module, or an S3 bucket.
# Local paths (starting with "./" or "../") are relative to the root module.
# =============================================================================

module "k8s_cluster" {
  source = "./modules/kind-cluster"

  # --- Cluster Identity ---
  # These map directly to the kind_cluster resource's top-level arguments.
  cluster_name       = var.cluster_name
  kubernetes_version = var.k8s_version
  kubeconfig_path    = var.kubeconfig_path

  # ---------------------------------------------------------------------------
  # KIND PROVIDER FEATURE: Networking Customization
  # ---------------------------------------------------------------------------
  # This object is passed to the module's networking variable, which configures
  # the kind_config.networking block. Every field here demonstrates a different
  # networking capability of the Kind provider.
  #
  # LEARNING EXERCISE: Try modifying these values and running `terraform plan`
  # to see how the cluster configuration changes. Remember: Kind clusters
  # don't support in-place updates, so changes will destroy and recreate.
  networking = {
    # Fixed API server port for consistent kubeconfig across cluster recreations.
    # Default is a random port, which changes every time.
    api_server_port = 6443

    # Custom Pod CIDR -- demonstrates overriding Kind's default (10.244.0.0/16).
    # Useful when your host network conflicts with the default range.
    pod_subnet = "10.200.0.0/16"

    # Custom Service CIDR -- demonstrates overriding Kind's default (10.96.0.0/12).
    # The first IP (10.100.0.1) becomes the kubernetes.default.svc ClusterIP.
    service_subnet = "10.100.0.0/16"

    # Using iptables mode (the most compatible option).
    # LEARNING EXERCISE: Change to "ipvs" and observe the difference, or set
    # to "none" and install Cilium in kube-proxy-free mode.
    kube_proxy_mode = "iptables"

    # IP Family -- uncomment to test dual-stack networking:
    # ip_family = "dual"

    # DNS Search -- uncomment to add custom DNS search domains:
    # dns_search = ["corp.example.com", "internal.local"]
  }

  # ---------------------------------------------------------------------------
  # KIND PROVIDER FEATURE: Containerd Config Patches
  # ---------------------------------------------------------------------------
  # Raw TOML patches applied to containerd on all nodes.
  #
  # IMPORTANT: containerd v2.x (shipped in kindest/node v1.34+) REMOVED the
  # registry.mirrors section from the CRI plugin config. The old format:
  #
  #   [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
  #     endpoint = ["http://registry:5000"]
  #
  # will BREAK containerd on v2.x, preventing the kubelet from starting and
  # causing `kubeadm init` to time out. For containerd v2.x, configure
  # registry mirrors using the hosts directory approach instead:
  #
  #   [plugins."io.containerd.grpc.v1.cri".registry]
  #     config_path = "/etc/containerd/certs.d"
  #
  # Then mount host config files via extra_mounts. See:
  # https://kind.sigs.k8s.io/docs/user/local-registry/
  #
  # For now, no containerd patches are needed for basic cluster operation.
  # containerd_config_patches = []

  # ---------------------------------------------------------------------------
  # KIND PROVIDER FEATURE: Runtime Config (Kubernetes API Overrides)
  # ---------------------------------------------------------------------------
  # Uncomment to enable alpha APIs or disable specific API groups.
  # Remember: Use "_" instead of "/" in keys (provider converts automatically).
  #
  # runtime_config = {
  #   "api_alpha" = "true"  # Enable all alpha APIs (becomes api/alpha=true)
  # }

  # ---------------------------------------------------------------------------
  # KIND PROVIDER FEATURE: Feature Gates (Kubernetes Feature Toggles)
  # ---------------------------------------------------------------------------
  # Uncomment to enable specific Kubernetes feature gates.
  # Full list: https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/
  #
  # feature_gates = {
  #   "GracefulNodeShutdown" = "true"  # Graceful shutdown support
  # }

  # ---------------------------------------------------------------------------
  # KIND PROVIDER FEATURE: Node Definitions
  # ---------------------------------------------------------------------------
  # Each entry creates a Docker container acting as a Kubernetes node.
  # This configuration demonstrates ALL node-level features:
  #   - Multiple control-planes (HA)
  #   - Kubeadm config patches (labels, taints)
  #   - Provider-native node labels
  #   - Extra port mappings (ingress)
  #   - Extra mounts with all options (propagation, selinux_relabel)
  nodes = [

    # ── Node 1: Control Plane Leader (Ingress Ready) ────────────────────────
    # The FIRST control-plane node runs the etcd leader and initializes the
    # cluster. We configure it for ingress by:
    #   1. Adding the "ingress-ready=true" label via kubeadm patch
    #   2. Mapping host ports 80/443 to the container (for Ingress traffic)
    #   3. Adding provider-native labels for node identification
    {
      role = "control-plane"

      # KIND PROVIDER FEATURE: kubeadm_config_patches
      # This YAML patch is applied to kubeadm's InitConfiguration.
      # It adds the "ingress-ready=true" label to this node, which is
      # required by many Ingress controllers (like NGINX) to know which
      # node should handle incoming traffic.
      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]

      # KIND PROVIDER FEATURE: labels (Provider-Native)
      # Direct node labels via the Kind provider (alternative to kubeadm patches).
      # These labels appear on the Kubernetes node object and can be used
      # in nodeSelector, nodeAffinity, and topology spread constraints.
      labels = {
        "node-role.example.com/ingress" = "true"
        "cluster-role"                  = "primary-control-plane"
      }

      # KIND PROVIDER FEATURE: extra_port_mappings
      # Forward host ports 80 and 443 to this node container. This is what
      # allows `curl http://localhost` on your machine to reach the NGINX
      # Ingress Controller running inside the cluster.
      extra_port_mappings = [
        {
          container_port = 80        # HTTP traffic
          host_port      = 80        # Accessible at http://localhost:80
          listen_address = "0.0.0.0" # Bind to all host interfaces
          protocol       = "TCP"     # HTTP uses TCP
        },
        {
          container_port = 443 # HTTPS traffic
          host_port      = 443 # Accessible at https://localhost:443
          listen_address = "0.0.0.0"
          protocol       = "TCP"
        }
      ]
    },

    # ── Node 2: HA Control Plane (Secondary) ────────────────────────────────
    # Adding a SECOND control-plane node creates a High Availability (HA)
    # cluster. In HA mode:
    #   - etcd runs on both control-plane nodes (replicated)
    #   - An internal load balancer distributes API server requests
    #   - The cluster survives the failure of one control-plane node
    #
    # KIND PROVIDER FEATURE: labels (Provider-Native)
    # We label this as the secondary control-plane for identification.
    {
      role = "control-plane"
      labels = {
        "cluster-role" = "secondary-control-plane"
      }
    },

    # ── Node 3: Standard Worker with Persistent Storage ─────────────────────
    # This worker demonstrates extra_mounts with ALL supported attributes:
    #   - host_path / container_path (basic bind mount)
    #   - read_only (write protection)
    #   - propagation (mount propagation mode)
    #   - selinux_relabel (SELinux support)
    #
    # KIND PROVIDER FEATURE: extra_mounts (all attributes)
    {
      role = "worker"

      labels = {
        "workload-type" = "general"
        "has-storage"   = "true"
      }

      extra_mounts = [
        {
          # Mount /tmp from the host into the container at /var/local-data.
          # Data written here persists across Pod restarts (but not cluster
          # recreation). Useful for development: place test data in /tmp
          # and it's immediately available inside Kubernetes pods that
          # use hostPath volumes.
          host_path      = "/tmp"
          container_path = "/var/local-data"
          read_only      = false # Read-write mount (pods can write data)

          # KIND PROVIDER FEATURE: propagation
          # Mount propagation controls how mounts created inside a container
          # are visible to the host and other containers:
          #   "None"            - Isolated, no propagation
          #   "HostToContainer" - Host mounts propagate into the container
          #   "Bidirectional"   - Mounts propagate in both directions
          # NOTE: "HostToContainer" (rslave) fails on macOS/Docker Desktop
          # because /tmp (/private/tmp) is not on a shared/slave mount.
          # Use "None" for macOS compatibility.
          propagation = "None"

          # KIND PROVIDER FEATURE: selinux_relabel
          # When true, the mount is relabeled to allow container access
          # under SELinux mandatory access controls. Only relevant on
          # SELinux-enforcing hosts (RHEL, Fedora, CentOS).
          # On macOS/Docker Desktop, this has no effect but is harmless.
          selinux_relabel = false
        }
      ]
    },

    # ── Node 4: Specialized Worker (Tainted for GPU Workloads) ──────────────
    # This worker is "tainted" so that only pods with matching tolerations
    # are scheduled here. This simulates a dedicated GPU node pool.
    #
    # KIND PROVIDER FEATURE: kubeadm_config_patches (taints)
    # The taint "dedicated=gpu:NoSchedule" means:
    #   - Regular pods are NOT scheduled on this node
    #   - Only pods with a matching toleration can run here
    #   - This is how cloud providers handle GPU/spot/ARM node pools
    {
      role = "worker"

      labels = {
        "workload-type"         = "gpu"
        "hardware-acceleration" = "true"
      }

      kubeadm_config_patches = [
        "kind: JoinConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    register-with-taints: \"dedicated=gpu:NoSchedule\"\n"
      ]
    }
  ]
}


# =============================================================================
# SECTION 2: Provider Configuration (Kubernetes & Helm)
# =============================================================================
# After the Kind cluster is created, we need to configure the kubernetes and
# helm providers with the cluster's connection details. These come from the
# module's outputs, which are computed attributes of the kind_cluster resource.
#
# TERRAFORM CONCEPT: Provider Configuration
# Providers can be configured using data from other resources. Here, we use
# the module outputs (endpoint, certificates) to point the kubernetes and
# helm providers at our newly created Kind cluster.
#
# IMPORTANT: Because these providers depend on module outputs, Terraform
# must create the cluster first, then configure the providers, then create
# any kubernetes_* or helm_release resources. This is handled automatically
# by Terraform's dependency graph.
# =============================================================================

provider "kubernetes" {
  # API server URL from the Kind cluster (e.g., "https://127.0.0.1:6443")
  host = module.k8s_cluster.endpoint

  # Mutual TLS authentication: client presents certificate + key,
  # and verifies the server using the CA certificate.
  client_certificate     = module.k8s_cluster.client_certificate
  client_key             = module.k8s_cluster.client_key
  cluster_ca_certificate = module.k8s_cluster.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    # Same connection details as the kubernetes provider.
    # The helm provider needs its own kubernetes block because it uses
    # a separate internal Kubernetes client.
    host                   = module.k8s_cluster.endpoint
    client_certificate     = module.k8s_cluster.client_certificate
    client_key             = module.k8s_cluster.client_key
    cluster_ca_certificate = module.k8s_cluster.cluster_ca_certificate
  }
}


# =============================================================================
# SECTION 3: NGINX Ingress Controller (Helm Deployment)
# =============================================================================
# This deploys the NGINX Ingress Controller into the cluster using Helm.
# An Ingress Controller is the component that processes Kubernetes Ingress
# resources and routes external HTTP/HTTPS traffic to the appropriate
# backend Services.
#
# WHY NGINX INGRESS ON KIND?
# Kind doesn't have a cloud load balancer, so we use NodePort + hostPort
# to expose the Ingress Controller. The extra_port_mappings on Node 1
# forward ports 80/443 from your machine to the control-plane node,
# where NGINX listens and routes traffic.
#
# TRAFFIC FLOW:
#   Browser → localhost:80 → Docker port mapping → Kind node:80 →
#   NGINX Ingress Controller → Kubernetes Service → Pod
# =============================================================================

resource "helm_release" "ingress_nginx" {
  # Helm release name (appears in `helm list`)
  name = "ingress-nginx"

  # Helm chart repository and chart name
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"

  # Deploy into a dedicated namespace (best practice for infrastructure components)
  namespace        = "ingress-nginx"
  create_namespace = true # Create the namespace if it doesn't exist

  # TERRAFORM CONCEPT: depends_on
  # Explicit dependency ensures the cluster is fully ready before Helm tries
  # to deploy. Without this, Helm might fail because the API server isn't
  # accepting connections yet.
  depends_on = [module.k8s_cluster]

  # --- Helm Values (equivalent to values.yaml overrides) ---
  # Each `set` block overrides a value in the chart's values.yaml.

  # Use NodePort instead of LoadBalancer (Kind has no cloud LB).
  set {
    name  = "controller.service.type"
    value = "NodePort"
  }

  # Enable hostPort so NGINX binds directly to the node's ports 80/443.
  # Combined with extra_port_mappings, this makes NGINX accessible at localhost.
  set {
    name  = "controller.hostPort.enabled"
    value = "true"
  }

  # Schedule the NGINX controller only on the node labeled "ingress-ready=true".
  # This ensures the controller runs on the control-plane node that has
  # extra_port_mappings for ports 80/443. Without this, the controller might
  # land on a worker node that has no host port forwarding, making it
  # unreachable from localhost.
  set {
    name  = "controller.nodeSelector.ingress-ready"
    value = "true"
    type  = "string" # Must be string, not boolean, for Kubernetes nodeSelector
  }

  # Tolerate the control-plane taint so the controller can be scheduled there.
  # By default, control-plane nodes have a NoSchedule taint that prevents
  # regular workloads from running on them.
  set {
    name  = "controller.tolerations[0].key"
    value = "node-role.kubernetes.io/control-plane"
  }
  set {
    name  = "controller.tolerations[0].operator"
    value = "Exists"
  }
  set {
    name  = "controller.tolerations[0].effect"
    value = "NoSchedule"
  }

  # Same OS selector for the admission webhook (validates Ingress resources).
  set {
    name  = "controller.admissionWebhooks.patch.nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }
}


# =============================================================================
# SECTION 4: Demo NGINX Web Server
# =============================================================================
# This section deploys a simple NGINX web server into the cluster and exposes
# it to the host machine via the Ingress Controller. It demonstrates the full
# traffic path from your browser to a running Pod:
#
#   Browser → localhost:80 → Docker port mapping → Kind node:80 →
#   NGINX Ingress Controller → ClusterIP Service → NGINX Pod
#
# THREE RESOURCES ARE NEEDED:
#   1. Deployment  - Runs the nginx container as a Pod
#   2. Service     - Gives the Pod(s) a stable internal DNS name and IP
#   3. Ingress     - Tells the Ingress Controller to route external traffic
#                    to the Service
#
# WHY ClusterIP (not NodePort or LoadBalancer)?
# The Ingress Controller is already handling external traffic on ports 80/443.
# Our Service only needs to be reachable *inside* the cluster -- the Ingress
# resource handles the external routing. This is the standard pattern:
# external traffic → Ingress → ClusterIP Service → Pods.
# =============================================================================

# --- Namespace ---
# Isolate the demo app in its own namespace (best practice: don't pollute default).
resource "kubernetes_namespace" "demo" {
  metadata {
    name = "demo"
  }

  depends_on = [module.k8s_cluster]
}

# --- Deployment ---
# Creates a ReplicaSet that maintains the desired number of nginx Pods.
# The kubernetes provider's `kubernetes_deployment_v1` resource maps directly
# to a Kubernetes Deployment object.
resource "kubernetes_deployment_v1" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace.demo.metadata[0].name
    labels = {
      app = "nginx"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "nginx"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }

      spec {
        container {
          name  = "nginx"
          image = "nginx:stable"

          port {
            container_port = 80
            protocol       = "TCP"
          }

          # Basic liveness probe -- the Ingress Controller won't route traffic
          # to Pods that fail their health check.
          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 3
            period_seconds        = 5
          }
        }
      }
    }
  }

  depends_on = [helm_release.ingress_nginx]
}

# --- Service (ClusterIP) ---
# A ClusterIP Service gives the nginx Pods a stable internal address
# (nginx.demo.svc.cluster.local) and load-balances across all healthy replicas.
# The Ingress resource below references this Service by name.
resource "kubernetes_service_v1" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace.demo.metadata[0].name
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "nginx"
    }

    port {
      port        = 80 # Service port (what other resources reference)
      target_port = 80 # Container port (where traffic is forwarded)
      protocol    = "TCP"
    }
  }
}

# --- Ingress ---
# This is the key resource that makes nginx reachable from outside the cluster.
# It tells the NGINX Ingress Controller: "route HTTP traffic for path '/' to
# the nginx Service on port 80."
#
# Because the Ingress Controller is bound to hostPorts 80/443 on the
# control-plane node (via the Helm chart), and the Kind node has
# extra_port_mappings forwarding host ports 80/443, the full chain is:
#   curl http://localhost → host:80 → Kind node:80 → Ingress Controller →
#   this Ingress rule → nginx Service:80 → nginx Pod:80
resource "kubernetes_ingress_v1" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace.demo.metadata[0].name
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.nginx.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}


# =============================================================================
# SECTION 5: Docker Image Loading (kind_load) -- UPCOMING FEATURE
# =============================================================================
# The Kind provider's source code includes a `kind_load` resource that loads
# Docker images from the local Docker daemon into the Kind cluster's nodes.
# This is equivalent to running:
#   kind load docker-image <image> --name <cluster>
#
# IMPORTANT: As of provider v0.10.0 (latest release), `kind_load` is only
# available on the unreleased master branch. It is NOT yet in any published
# release on the Terraform Registry. Once it is released, you can use:
#
#   resource "kind_load" "images" {
#     for_each     = toset(var.load_docker_images)
#     image        = each.value
#     cluster_name = module.k8s_cluster.cluster_name
#     depends_on   = [module.k8s_cluster]
#   }
#
# WORKAROUND: Until kind_load is released, use a null_resource with local-exec:
#
#   resource "null_resource" "load_image" {
#     for_each = toset(var.load_docker_images)
#     provisioner "local-exec" {
#       command = "kind load docker-image ${each.value} --name ${var.cluster_name}"
#     }
#     depends_on = [module.k8s_cluster]
#   }
#
# Or simply run the CLI command after terraform apply:
#   kind load docker-image myapp:latest --name dev-cluster
# =============================================================================
