# Kind Kubernetes Cluster -- Terraform Project

A comprehensive Terraform project that provisions a fully-featured, multi-node Kubernetes cluster on your local machine using [Kind](https://kind.sigs.k8s.io/) (Kubernetes IN Docker). This project demonstrates **every feature** of the [tehcyx/kind Terraform provider](https://registry.terraform.io/providers/tehcyx/kind/latest) and serves as both a working development environment and an educational reference for learning Terraform with Kubernetes.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [What Gets Created](#what-gets-created)
- [Kind Provider Feature Coverage](#kind-provider-feature-coverage)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [File-by-File Walkthrough](#file-by-file-walkthrough)
- [Configuration Reference](#configuration-reference)
- [Learning Exercises](#learning-exercises)
- [Modification Guide](#modification-guide)
- [Troubleshooting](#troubleshooting)
- [Terraform Concepts Used](#terraform-concepts-used)

---

## Architecture Overview

```
┌─ Your Machine (macOS/Linux) ──────────────────────────────────────────┐
│                                                                       │
│  ┌─ Docker ────────────────────────────────────────────────────────┐  │
│  │                                                                 │  │
│  │   ┌──────────────────────┐  ┌──────────────────────┐            │  │
│  │   │  Control Plane #1    │  │  Control Plane #2    │            │  │
│  │   │  (etcd leader)       │  │  (HA secondary)      │            │  │
│  │   │  Ports: 80, 443 ← ───┤──┤  Labels: secondary   │            │  │
│  │   │  Label: ingress-ready│  │                      │            │  │
│  │   │  NGINX Ingress ↑     │  │                      │            │  │
│  │   └──────────────────────┘  └──────────────────────┘            │  │
│  │                                                                 │  │
│  │   ┌──────────────────────┐  ┌──────────────────────┐            │  │
│  │   │  Worker #1           │  │  Worker #2           │            │  │
│  │   │  Mount: /tmp →       │  │  Taint: dedicated=   │            │  │
│  │   │    /var/local-data   │  │    gpu:NoSchedule    │            │  │
│  │   │  Label: general      │  │  Label: gpu          │            │  │
│  │   └──────────────────────┘  └──────────────────────┘            │  │
│  │                                                                 │  │
│  │ Network: pod_subnet=10.200.0.0/16, service_subnet=10.100.0.0/16 │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  localhost:80  ──→ NGINX Ingress ──→ Your Services                    │
│  localhost:443 ──→ NGINX Ingress ──→ Your Services                    │
└───────────────────────────────────────────────────────────────────────┘
```

## What Gets Created

| Component | Details |
|-----------|---------|
| **Control Plane Nodes** | 2 nodes (HA cluster with replicated etcd) |
| **Worker Nodes** | 2 nodes (1 general-purpose, 1 tainted for GPU workloads) |
| **Networking** | Custom Pod CIDR (10.200.0.0/16), Service CIDR (10.100.0.0/16), iptables proxy mode |
| **Ingress** | NGINX Ingress Controller via Helm, accessible at localhost:80/443 |
| **Container Runtime** | Containerd with registry mirror patches |
| **Port Mappings** | Host ports 80/443 forwarded to control-plane node |
| **Storage** | Host /tmp mounted into Worker #1 at /var/local-data |
| **Labels** | Provider-native labels on all nodes for identification |
| **Taints** | GPU taint on Worker #2 (dedicated=gpu:NoSchedule) |

---

## Kind Provider Feature Coverage

This project uses **every resource and every attribute** available in the tehcyx/kind Terraform provider (v0.7.0):

### Resources

| Resource | Status | Description |
|----------|--------|-------------|
| `kind_cluster` | Used | Creates the Kind cluster |
| `kind_load` | Unreleased | Loads local Docker images into the cluster. Available in provider source code but NOT in any published release (as of v0.10.0). Documented with workarounds in `main.tf` Section 4. |

### kind_cluster Arguments

| Argument | Used | Location |
|----------|------|----------|
| `name` | Yes | `modules/kind-cluster/main.tf` |
| `node_image` | Yes | `modules/kind-cluster/main.tf` |
| `wait_for_ready` | Yes | `modules/kind-cluster/main.tf` |
| `kubeconfig_path` | Yes | `modules/kind-cluster/main.tf` |

### kind_config Block

| Attribute | Used | Description |
|-----------|------|-------------|
| `kind` | Yes | Config type ("Cluster") |
| `api_version` | Yes | Config API version |
| `containerd_config_patches` | Yes | TOML containerd configuration |
| `runtime_config` | Yes | Kubernetes API runtime overrides (commented, ready to enable) |
| `feature_gates` | Yes | Kubernetes feature toggles (commented, ready to enable) |

### Networking Block (all 8 attributes)

| Attribute | Used | Description |
|-----------|------|-------------|
| `api_server_address` | Yes | API server bind IP |
| `api_server_port` | Yes | API server port |
| `pod_subnet` | Yes | Pod IP CIDR range |
| `service_subnet` | Yes | Service ClusterIP CIDR range |
| `disable_default_cni` | Yes | Toggle kindnet CNI |
| `kube_proxy_mode` | Yes | iptables/ipvs/none |
| `ip_family` | Yes | IPv4/IPv6/DualStack (commented, ready to enable) |
| `dns_search` | Yes | Custom DNS search domains (commented, ready to enable) |

### Node Block (all 6 attributes)

| Attribute | Used | Description |
|-----------|------|-------------|
| `role` | Yes | control-plane or worker |
| `image` | Yes | Per-node image override (variable support) |
| `kubeadm_config_patches` | Yes | Kubeadm YAML patches |
| `labels` | Yes | Provider-native node labels |
| `extra_mounts` | Yes | Host directory bind mounts |
| `extra_port_mappings` | Yes | Host-to-container port forwards |

### Extra Mounts (all 5 attributes)

| Attribute | Used | Description |
|-----------|------|-------------|
| `host_path` | Yes | Source path on host |
| `container_path` | Yes | Destination in container |
| `read_only` | Yes | Write protection flag |
| `propagation` | Yes | Mount propagation mode |
| `selinux_relabel` | Yes | SELinux relabel flag |

### Extra Port Mappings (all 4 attributes)

| Attribute | Used | Description |
|-----------|------|-------------|
| `container_port` | Yes | Container port |
| `host_port` | Yes | Host port |
| `listen_address` | Yes | Host bind IP |
| `protocol` | Yes | TCP/UDP/SCTP |

### Computed Outputs (all 5 attributes)

| Output | Exported | Description |
|--------|----------|-------------|
| `endpoint` | Yes | API server URL |
| `client_certificate` | Yes | TLS client cert |
| `client_key` | Yes | TLS client key |
| `cluster_ca_certificate` | Yes | Cluster CA cert |
| `kubeconfig` | Yes | Full kubeconfig YAML |

---

## Prerequisites

| Tool | Minimum Version | Installation |
|------|----------------|--------------|
| **Terraform** | >= 1.5.0 | [Install guide](https://developer.hashicorp.com/terraform/install) |
| **Docker** | >= 20.10 | [Install guide](https://docs.docker.com/get-docker/) |
| **Kind** | >= 0.20.0 | `brew install kind` or [install guide](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) |
| **kubectl** | >= 1.28 | `brew install kubectl` or [install guide](https://kubernetes.io/docs/tasks/tools/) |
| **Helm** | >= 3.12 | `brew install helm` (optional, for manual chart management) |

Verify your setup:

```bash
terraform version   # Should show >= 1.5.0
docker version      # Should show Docker Engine running
kind version        # Should show >= 0.20.0
kubectl version     # Client version >= 1.28
```

---

## Quick Start

```bash
# 1. Clone and navigate to the project
cd /path/to/k8s/src/terraform

# 2. Initialize Terraform (downloads providers)
terraform init

# 3. Preview what will be created
terraform plan

# 4. Create the cluster (takes 2-5 minutes)
terraform apply

# 5. Verify the cluster
kubectl get nodes -o wide
kubectl get pods -A

# 6. Test ingress (after NGINX pods are Running)
curl http://localhost

# 7. Clean up when done
terraform destroy
```

---

## Project Structure

```
terraform/
├── main.tf                          # Root module: orchestrates everything
│                                    #   - Calls kind-cluster module
│                                    #   - Configures kubernetes/helm providers
│                                    #   - Deploys NGINX Ingress via Helm
│                                    #   - Loads Docker images via kind_load
├── variables.tf                     # Root module: input variables
│                                    #   - cluster_name, k8s_version
│                                    #   - kubeconfig_path
│                                    #   - load_docker_images
├── outputs.tf                       # Root module: output values
│                                    #   - Cluster endpoint, kubeconfig
│                                    #   - Post-apply instructions
├── versions.tf                      # Root module: provider version pins
│                                    #   - tehcyx/kind, hashicorp/helm,
│                                    #     hashicorp/kubernetes
├── terraform.tfvars                 # Your custom variable overrides
│                                    #   (edit this file to customize)
├── README.md                        # This file
│
├── modules/
│   └── kind-cluster/                # Child module: Kind cluster creation
│       ├── main.tf                  # The kind_cluster resource with ALL features
│       ├── variables.tf             # Module inputs (the module's API)
│       ├── outputs.tf               # Module outputs (connection details)
│       └── versions.tf              # Module provider requirements
│
├── .terraform/                      # Auto-generated: downloaded providers
├── .terraform.lock.hcl             # Provider version lock file (commit this)
├── terraform.tfstate               # Cluster state (DO NOT commit)
└── dev-cluster-config              # Generated kubeconfig (DO NOT commit)
```

---

## File-by-File Walkthrough

### Root Module Files

#### `versions.tf` -- Provider Dependencies
Declares the three providers this project needs and pins their versions for reproducibility. The lock file (`.terraform.lock.hcl`) records exact binary hashes.

#### `variables.tf` -- User Inputs
Defines the knobs users can turn: cluster name, Kubernetes version, kubeconfig path, and Docker images to load. Each variable has extensive documentation explaining its purpose and valid values.

#### `main.tf` -- The Orchestrator
The heart of the project. It:
1. **Calls the child module** with all configuration (networking, nodes, patches)
2. **Configures providers** using the module's credential outputs
3. **Deploys NGINX Ingress** via a Helm release
4. **Documents the unreleased `kind_load` resource** with workarounds

#### `outputs.tf` -- Results Display
Shows the cluster endpoint and helpful post-apply instructions including kubectl commands for verification.

### Child Module Files (`modules/kind-cluster/`)

#### `variables.tf` -- The Module API
Defines every possible configuration option as a typed variable. Uses Terraform's `optional()` function with defaults so callers only need to specify what they want to customize.

#### `main.tf` -- The Kind Cluster Resource
Contains the `kind_cluster` resource with every supported attribute. Uses `dynamic` blocks to generate node configurations from a list variable. Extensively commented to explain each feature.

#### `outputs.tf` -- Credential Export
Exposes the five computed attributes (endpoint, certificates, kubeconfig) needed by other providers to connect to the cluster. Sensitive values are marked to prevent accidental log exposure.

#### `versions.tf` -- Module Provider Contract
Declares the minimum Kind provider version needed. Uses `>=` (not exact pin) so the root module controls the exact version.

---

## Configuration Reference

### terraform.tfvars

Customize your cluster by editing `terraform.tfvars`:

```hcl
# Cluster name (becomes kubectl context "kind-my-project")
cluster_name = "my-project"

# Kubernetes version
k8s_version = "kindest/node:v1.31.0"

# Custom kubeconfig location (optional)
# kubeconfig_path = "/Users/you/.kube/kind-my-project"

# Load local Docker images into the cluster (optional)
# load_docker_images = ["myapp:latest", "sidecar:v2.0"]
```

### Command-Line Overrides

```bash
# Override a single variable
terraform apply -var="cluster_name=test-cluster"

# Override multiple variables
terraform apply -var="cluster_name=test" -var="k8s_version=kindest/node:v1.30.0"

# Use a different var file
terraform apply -var-file="production.tfvars"
```

---

## Learning Exercises

These exercises are designed to teach Terraform and Kubernetes concepts by making incremental changes to this project.

### Exercise 1: Change the Cluster Name

**Concepts:** Variables, terraform.tfvars, plan output

```hcl
# In terraform.tfvars:
cluster_name = "learning-cluster"
```

```bash
terraform plan    # See what changes
terraform apply   # Note: destroys and recreates (Kind doesn't support rename)
```

**What you'll learn:** How Terraform detects changes and why Kind clusters are immutable.

---

### Exercise 2: Add a Third Worker Node

**Concepts:** List variables, dynamic blocks

In `main.tf`, add a new entry to the `nodes` list:

```hcl
    # Add after the last node entry:
    {
      role = "worker"
      labels = {
        "workload-type" = "batch"
      }
    }
```

```bash
terraform plan   # See: 1 to destroy, 1 to create (cluster replacement)
terraform apply
kubectl get nodes  # Should show 5 nodes
```

**What you'll learn:** How dynamic blocks generate Kubernetes nodes from list data.

---

### Exercise 3: Enable Dual-Stack Networking

**Concepts:** Networking, IP families

In `main.tf`, add `ip_family` to the networking block:

```hcl
  networking = {
    api_server_port = 6443
    pod_subnet      = "10.200.0.0/16"
    service_subnet  = "10.100.0.0/16"
    kube_proxy_mode = "iptables"
    ip_family       = "dual"  # Enable IPv4 + IPv6
  }
```

```bash
terraform apply
kubectl get nodes -o wide   # Check for IPv6 addresses
kubectl get svc -A          # Services will have dual-stack ClusterIPs
```

**What you'll learn:** How Kubernetes dual-stack networking works.

---

### Exercise 4: Enable Feature Gates

**Concepts:** Kubernetes feature gates, map variables

In `main.tf`, uncomment and customize the `feature_gates` block:

```hcl
  feature_gates = {
    "GracefulNodeShutdown" = "true"
  }
```

```bash
terraform apply
# Verify:
kubectl get nodes -o jsonpath='{.items[0].status.conditions}' | jq .
```

**What you'll learn:** How Kubernetes feature gates control experimental features.

---

### Exercise 5: Enable Runtime Config

**Concepts:** Kubernetes API groups, HCL map keys

In `main.tf`, uncomment and customize the `runtime_config` block:

```hcl
  runtime_config = {
    "api_alpha" = "true"   # Remember: _ becomes / (api/alpha)
  }
```

```bash
terraform apply
kubectl api-versions   # Look for alpha API versions
```

**What you'll learn:** How Kubernetes API groups are enabled/disabled at the cluster level.

---

### Exercise 6: Install a Custom CNI (Calico)

**Concepts:** CNI plugins, disable_default_cni

1. Disable kindnet in the networking block:

```hcl
  networking = {
    # ... existing settings ...
    disable_default_cni = true
  }
```

2. Add a Helm release for Calico in `main.tf`:

```hcl
resource "helm_release" "calico" {
  name       = "calico"
  repository = "https://docs.tigera.io/calico/charts"
  chart      = "tigera-operator"
  namespace  = "tigera-operator"
  create_namespace = true
  depends_on = [module.k8s_cluster]
}
```

**What you'll learn:** How to replace Kind's default CNI with a production-grade one.

---

### Exercise 7: Load a Docker Image (CLI Workaround)

**Concepts:** kind load CLI, local images, container runtime

Since the `kind_load` Terraform resource is not yet in any released provider version, use the Kind CLI directly after cluster creation:

```bash
# 1. Pull an image locally
docker pull nginx:alpine

# 2. Load it into the Kind cluster
kind load docker-image nginx:alpine --name dev-cluster

# 3. Verify and use it (no registry needed!)
kubectl run test --image=nginx:alpine --restart=Never --image-pull-policy=Never
kubectl get pod test
```

**What you'll learn:** How Kind loads images from the local Docker daemon into cluster nodes via containerd.

---

### Exercise 8: Use IPVS Proxy Mode

**Concepts:** kube-proxy modes, IPVS

Change the proxy mode:

```hcl
  networking = {
    # ... existing settings ...
    kube_proxy_mode = "ipvs"
  }
```

```bash
terraform apply
# Verify IPVS mode:
kubectl -n kube-system logs -l k8s-app=kube-proxy | grep "Using ipvs"
```

**What you'll learn:** The difference between iptables and IPVS proxy modes and when to use each.

---

### Exercise 9: Add DNS Search Domains

**Concepts:** DNS resolution, search domains

Add custom DNS search domains:

```hcl
  networking = {
    # ... existing settings ...
    dns_search = ["corp.example.com", "internal.local"]
  }
```

```bash
terraform apply
# Verify inside a pod:
kubectl run test --image=busybox --restart=Never -- cat /etc/resolv.conf
kubectl logs test
```

**What you'll learn:** How DNS search domains affect name resolution inside Kubernetes pods.

---

### Exercise 10: Custom kubeconfig Path

**Concepts:** kubeconfig, pathexpand, file outputs

Set a custom kubeconfig path in `terraform.tfvars`:

```hcl
kubeconfig_path = "/tmp/my-kind-kubeconfig"
```

```bash
terraform apply
# Use the custom kubeconfig:
export KUBECONFIG=/tmp/my-kind-kubeconfig
kubectl get nodes
```

**What you'll learn:** How Kind generates and writes kubeconfig files.

---

### Exercise 11: Test Kubernetes Version Skew

**Concepts:** Per-node images, version compatibility

Give the second worker a different Kubernetes version:

```hcl
    # Modify the GPU worker node:
    {
      role  = "worker"
      image = "kindest/node:v1.30.0"  # Different version!
      # ... rest of config
    }
```

```bash
terraform apply
kubectl get nodes -o wide  # Note the different VERSION column
```

**What you'll learn:** Kubernetes version skew policies and how clusters handle mixed versions.

---

### Exercise 12: Mount Propagation Modes

**Concepts:** Bind mounts, mount propagation

Change the propagation mode on the existing mount:

```hcl
    extra_mounts = [{
      host_path      = "/tmp"
      container_path = "/var/local-data"
      propagation    = "Bidirectional"  # Try different modes
    }]
```

**Options:**
- `"None"` -- No propagation (fully isolated)
- `"HostToContainer"` -- Host mounts visible in container
- `"Bidirectional"` -- Mounts propagate both directions

**What you'll learn:** How Linux mount namespaces and propagation affect container storage.

---

## Modification Guide

### How to Add a New Helm Chart

1. Add a new `helm_release` resource in `main.tf`:

```hcl
resource "helm_release" "my_chart" {
  name       = "my-release"
  repository = "https://charts.example.com"
  chart      = "my-chart"
  namespace  = "my-namespace"
  create_namespace = true
  depends_on = [module.k8s_cluster]

  set {
    name  = "key"
    value = "value"
  }
}
```

### How to Add Kubernetes Resources

Use the `kubernetes` provider (already configured):

```hcl
resource "kubernetes_namespace" "app" {
  metadata {
    name = "my-app"
    labels = {
      environment = "development"
    }
  }
  depends_on = [module.k8s_cluster]
}

resource "kubernetes_deployment" "app" {
  metadata {
    name      = "my-app"
    namespace = kubernetes_namespace.app.metadata[0].name
  }
  spec {
    replicas = 2
    selector {
      match_labels = { app = "my-app" }
    }
    template {
      metadata {
        labels = { app = "my-app" }
      }
      spec {
        container {
          name  = "app"
          image = "nginx:latest"
          port {
            container_port = 80
          }
        }
      }
    }
  }
}
```

### How to Add More Module Variables

1. Add the variable in `modules/kind-cluster/variables.tf`
2. Use the variable in `modules/kind-cluster/main.tf`
3. Pass the value in the root `main.tf` module call
4. Optionally expose it as a root variable in root `variables.tf`

### How to Create a Second Cluster

Duplicate the module call with a different name:

```hcl
module "staging_cluster" {
  source = "./modules/kind-cluster"
  cluster_name = "staging"
  kubernetes_version = var.k8s_version
  nodes = [
    { role = "control-plane" },
    { role = "worker" }
  ]
}
```

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| `Error: Cluster already exists` | Run `kind delete cluster --name <name>` then `terraform apply` |
| `Error: port 80 already in use` | Stop any process using port 80: `lsof -i :80` |
| `Error: image not found locally` | Build/pull the image first: `docker pull <image>` |
| Nodes stuck in `NotReady` | Wait 1-2 minutes, or check: `kubectl describe node <name>` |
| Terraform state out of sync | `terraform refresh` or `kind delete cluster && terraform apply` |
| `Error: provider not found` | Run `terraform init` to download providers |
| Slow cluster creation | Ensure Docker has enough resources (4GB+ RAM recommended) |

### Resetting Everything

```bash
# Nuclear option: delete everything and start fresh
terraform destroy -auto-approve
kind delete clusters --all
rm -rf .terraform terraform.tfstate*
terraform init
terraform apply
```

### Checking Provider Versions

```bash
terraform providers          # Show providers used by this config
terraform version            # Show Terraform and provider versions
```

---

## Terraform Concepts Used

This project demonstrates these core Terraform concepts:

| Concept | Where Used | What It Does |
|---------|-----------|--------------|
| **Modules** | `main.tf` → `modules/kind-cluster/` | Encapsulates reusable infrastructure |
| **Variables** | `variables.tf` files | Parameterizes configurations |
| **Outputs** | `outputs.tf` files | Exports values between modules |
| **Dynamic Blocks** | `modules/kind-cluster/main.tf` | Generates repeated blocks from lists |
| **Provider Configuration** | `main.tf` provider blocks | Connects Terraform to APIs |
| **Version Constraints** | `versions.tf` files | Pins reproducible versions |
| **Type Constraints** | Variable `type` attributes | Validates input shapes |
| **Optional Fields** | Variable `optional()` | Allows partial object inputs |
| **Sensitive Values** | Output `sensitive = true` | Protects credentials |
| **Depends On** | `depends_on` meta-argument | Controls resource ordering |
| **For Each** | `kind_load` resource | Creates multiple resource instances |
| **Try Function** | Module `main.tf` | Safe access to optional attributes |
| **Validation** | Variable `validation` blocks | Custom input validation rules |
| **HereDocs** | `<<TOML ... TOML` syntax | Multi-line string literals |

---

## Additional Resources

- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Kind Terraform Provider](https://registry.terraform.io/providers/tehcyx/kind/latest/docs)
- [Kind Provider Source Code](https://github.com/tehcyx/terraform-provider-kind)
- [Terraform Documentation](https://developer.hashicorp.com/terraform/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Helm Provider](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
