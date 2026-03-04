# Kind Kubernetes Cluster -- Terraform Project

A comprehensive Terraform project that provisions a fully-featured, multi-node Kubernetes cluster on your local machine using [Kind](https://kind.sigs.k8s.io/) (Kubernetes IN Docker), then optionally deploys a demo NGINX application with ingress routing. This project demonstrates **every feature** of the [tehcyx/kind Terraform provider](https://registry.terraform.io/providers/tehcyx/kind/latest) and serves as both a working development environment and an educational reference for learning Terraform with Kubernetes.

The project is split into two independent Terraform root modules to teach proper infrastructure separation:

| Module | Purpose |
|--------|---------|
| **`cluster/`** | Provisions a pure, fully-featured Kind cluster (infrastructure) |
| **`app_demo/`** | Deploys a demo NGINX app with ingress into the cluster (workload) |

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Two-Module Design](#two-module-design)
- [What Gets Created](#what-gets-created)
- [Kind Provider Feature Coverage](#kind-provider-feature-coverage)
- [Prerequisites](#prerequisites)
- [VS Code / Cursor IDE Setup](#vs-code--cursor-ide-setup)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [File-by-File Walkthrough](#file-by-file-walkthrough)
  - [cluster/ Files](#cluster-files)
  - [app_demo/ Files](#app_demo-files)
  - [Shared Module: modules/kind-cluster/](#shared-module-moduleskind-cluster)
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
│  ── Created by cluster/ ──────────────────────────────────────────    │
│                                                                       │
│  localhost:80  ──→ NGINX Ingress ──→ Demo NGINX App                   │
│  localhost:443 ──→ NGINX Ingress ──→ Demo NGINX App                   │
│                                                                       │
│  ── Created by app_demo/ ─────────────────────────────────────────    │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Two-Module Design

This project is intentionally split into **two independent Terraform root modules** rather than one monolithic configuration. This separation teaches an important Terraform best practice:

### Why Separate?

| Concern | Single Module (before) | Two Modules (now) |
|---------|----------------------|-------------------|
| **Blast radius** | Changing the app could accidentally destroy the cluster | Each module has its own state; changes are isolated |
| **Lifecycle** | Cluster and app are created/destroyed together | Destroy the app without touching the cluster, or vice versa |
| **Ownership** | One team owns everything | Platform team owns `cluster/`, app team owns `app_demo/` |
| **State size** | Single large state file | Smaller, focused state files |
| **Provider deps** | All three providers always needed | `cluster/` only needs Kind; `app_demo/` only needs Helm + Kubernetes |
| **Reusability** | Hard to reuse the cluster for other apps | Deploy any app to the cluster -- not just this demo |

### How They Connect

```
cluster/                          app_demo/
┌──────────────────┐              ┌──────────────────┐
│  terraform apply │              │  terraform apply │
│                  │              │                  │
│  Creates Kind    │──kubeconfig──│  Reads kubeconfig│
│  cluster         │  (~/.kube/   │  to connect to   │
│                  │   config)    │  the cluster     │
└──────────────────┘              └──────────────────┘
       ↓                                 ↓
  Pure infrastructure              Application workload
  (nodes, networking)              (Ingress, Deployment,
                                    Service, Ingress)
```

The `cluster/` module creates the Kind cluster, which automatically updates `~/.kube/config`. The `app_demo/` module reads that kubeconfig to connect and deploy resources. No shared state or remote backends are needed.

---

## What Gets Created

### cluster/ (Infrastructure)

| Component | Details |
|-----------|---------|
| **Control Plane Nodes** | 2 nodes (HA cluster with replicated etcd) |
| **Worker Nodes** | 2 nodes (1 general-purpose, 1 tainted for GPU workloads) |
| **Networking** | Custom Pod CIDR (10.200.0.0/16), Service CIDR (10.100.0.0/16), iptables proxy mode |
| **Port Mappings** | Host ports 80/443 forwarded to control-plane node |
| **Storage** | Host /tmp mounted into Worker #1 at /var/local-data |
| **Labels** | Provider-native labels on all nodes for identification |
| **Taints** | GPU taint on Worker #2 (dedicated=gpu:NoSchedule) |

### app_demo/ (Application)

| Component | Details |
|-----------|---------|
| **Ingress Controller** | NGINX Ingress Controller via Helm, accessible at localhost:80/443 |
| **Demo Namespace** | Isolated `demo` namespace for the sample app |
| **NGINX Deployment** | 2 replicas with liveness and readiness probes |
| **ClusterIP Service** | Internal load balancing across NGINX replicas |
| **Ingress Resource** | Routes `http://localhost/` to the NGINX service |

---

## Kind Provider Feature Coverage

The `cluster/` module uses **every resource and every attribute** available in the tehcyx/kind Terraform provider (v0.7.0):

### Resources

| Resource | Status | Description |
|----------|--------|-------------|
| `kind_cluster` | Used | Creates the Kind cluster |
| `kind_load` | Unreleased | Loads local Docker images into the cluster. Available in provider source code but NOT in any published release (as of v0.10.0). Documented with workarounds in `cluster/main.tf`. |

### kind_cluster Arguments

| Argument | Used | Location |
|----------|------|----------|
| `name` | Yes | `cluster/modules/kind-cluster/main.tf` |
| `node_image` | Yes | `cluster/modules/kind-cluster/main.tf` |
| `wait_for_ready` | Yes | `cluster/modules/kind-cluster/main.tf` |
| `kubeconfig_path` | Yes | `cluster/modules/kind-cluster/main.tf` |

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

## VS Code / Cursor IDE Setup

The Terraform language server validates `.tf` files using **provider schemas** -- the detailed type information describing every resource, block, and attribute that each provider supports. These schemas are downloaded during `terraform init` and stored in the `.terraform/` directory. Without them, the language server doesn't know what blocks are valid for provider-specific resources and produces false errors.

### Common False Errors

If you open this project before running `terraform init` in both `cluster/` and `app_demo/`, you'll see errors like:

| File | False Error | Cause |
|------|-------------|-------|
| `app_demo/main.tf` | `Unexpected block: blocks of type "set" are not expected here` | Missing Helm provider schema (`set` is valid on `helm_release`) |
| `cluster/main.tf` | Unknown resource types, missing attributes | Missing Kind provider schema |

These are **not code errors** -- the Terraform is valid. The IDE just can't validate without the schemas.

### Fix: Initialize Both Modules

Run `terraform init` in **each** root module directory. This downloads providers and generates the schemas the language server needs:

```bash
cd cluster/
terraform init

cd ../app_demo/
terraform init
```

After initialization, reload the editor window (`Cmd+Shift+P` > `Developer: Reload Window`) if errors persist. The language server will find the schemas in `.terraform/providers/` and validate correctly, including autocomplete and hover documentation for all provider resources.

### Why Two Separate Inits?

Each root module (`cluster/` and `app_demo/`) has **its own** `.terraform/` directory, lock file, and state file. They use different providers:

| Module | Providers | Schema Coverage |
|--------|-----------|-----------------|
| `cluster/` | `tehcyx/kind` | `kind_cluster`, `kind_config` blocks |
| `app_demo/` | `hashicorp/helm`, `hashicorp/kubernetes` | `helm_release` + `set` blocks, `kubernetes_deployment_v1`, etc. |

Initializing one does not cover the other. Both must be initialized independently.

---

## Quick Start

```bash
# ──────────────────────────────────────────────────────────────
# Step 1: Deploy the cluster
# ──────────────────────────────────────────────────────────────
cd cluster/

terraform init    # Download providers
terraform plan    # Preview what will be created
terraform apply   # Create the cluster (2-5 minutes)

# Verify the cluster
kubectl get nodes -o wide       # Should show 4 nodes
kubectl get nodes --show-labels  # Check labels


# ──────────────────────────────────────────────────────────────
# Step 2: Deploy the demo app
# ──────────────────────────────────────────────────────────────
cd ../app_demo/

terraform init    # Download providers
terraform plan    # Preview the app resources
terraform apply   # Deploy ingress + NGINX app

# Test (wait ~30s for pods to become Ready)
kubectl -n demo get pods
curl http://localhost


# ──────────────────────────────────────────────────────────────
# Cleanup
# ──────────────────────────────────────────────────────────────
# Remove just the app:
cd app_demo/ && terraform destroy

# Remove the cluster:
cd ../cluster/ && terraform destroy
```

---

## Project Structure

```
terraform/
├── README.md                            # This file (project overview)
│
├── cluster/                             # TERRAFORM ROOT MODULE #1: Infrastructure
│   ├── main.tf                          # Calls the kind-cluster module with all
│   │                                    #   Kind features configured (networking,
│   │                                    #   nodes, labels, taints, mounts, ports)
│   ├── variables.tf                     # cluster_name, k8s_version, kubeconfig_path
│   ├── outputs.tf                       # Cluster endpoint, kubeconfig, context name,
│   │                                    #   TLS certs, and post-apply instructions
│   ├── versions.tf                      # tehcyx/kind provider only
│   ├── terraform.tfvars                 # Your cluster customizations
│   │
│   └── modules/
│       └── kind-cluster/                # Reusable child module
│           ├── main.tf                  # kind_cluster resource with ALL features
│           ├── variables.tf             # Module API (typed, validated inputs)
│           ├── outputs.tf               # Connection credentials (sensitive)
│           └── versions.tf              # Module provider contract
│
├── app_demo/                            # TERRAFORM ROOT MODULE #2: Application
│   ├── main.tf                          # NGINX Ingress (Helm) + demo app
│   │                                    #   (Deployment + Service + Ingress)
│   ├── variables.tf                     # kubeconfig_path, kubeconfig_context
│   ├── outputs.tf                       # nginx_url, post-deploy instructions
│   ├── versions.tf                      # hashicorp/helm + hashicorp/kubernetes
│   └── terraform.tfvars                 # Context name matching the cluster
│
├── .terraform/                          # Auto-generated (per root module)
├── .terraform.lock.hcl                 # Provider lock (per root module, commit this)
└── terraform.tfstate                   # State file (per root module, DO NOT commit)
```

> **Note:** Each root module (`cluster/` and `app_demo/`) has its own `.terraform/` directory, lock file, and state file. Run `terraform init` separately in each.

---

## File-by-File Walkthrough

### cluster/ Files

#### `cluster/versions.tf` -- Provider Dependencies
Declares only the Kind provider. This module doesn't need `hashicorp/kubernetes` or `hashicorp/helm` because it doesn't deploy any workloads -- the cluster is a pure infrastructure concern.

#### `cluster/variables.tf` -- User Inputs
Three variables: cluster name, Kubernetes version, and optional kubeconfig path. Each has extensive documentation explaining its purpose and valid values.

#### `cluster/main.tf` -- The Cluster Orchestrator
The heart of cluster provisioning. It calls the `kind-cluster` child module with full configuration:
- **Networking**: custom pod/service CIDRs, proxy mode, port forwarding
- **Nodes**: 4 nodes (2 control-plane, 2 worker) with labels, taints, mounts
- **Commented sections** for feature gates, runtime config, and containerd patches

#### `cluster/outputs.tf` -- Cluster Credentials & Instructions
Exports connection details (endpoint, TLS certs, kubeconfig) for use by other tools or terraform modules. Includes the `cluster_context` output that `app_demo/` references.

#### `cluster/terraform.tfvars` -- Customization
Override cluster name and Kubernetes version here.

---

### app_demo/ Files

#### `app_demo/versions.tf` -- Provider Dependencies
Declares only `hashicorp/helm` and `hashicorp/kubernetes`. No Kind provider needed since the cluster is managed by the sibling module.

#### `app_demo/variables.tf` -- Connection Config
Two variables: kubeconfig path (defaults to `~/.kube/config`) and kubeconfig context (defaults to `kind-dev`). Changing the context lets you target a different cluster.

#### `app_demo/main.tf` -- Application Deployment
Deploys three layers:
1. **NGINX Ingress Controller** via Helm -- processes Ingress resources and routes HTTP traffic
2. **Demo NGINX app** -- Deployment (2 replicas), Service (ClusterIP), and Ingress
3. **Provider config** -- connects to the cluster using kubeconfig context

#### `app_demo/outputs.tf` -- Access Instructions
Shows the URL to reach the demo app and cleanup commands.

#### `app_demo/terraform.tfvars` -- Cluster Context
Must match the `cluster_name` in `cluster/terraform.tfvars`. If you change the cluster name, update this too.

---

### Shared Module: modules/kind-cluster/

The child module in `cluster/modules/kind-cluster/` is unchanged from the monolithic version. It encapsulates the `kind_cluster` resource with every provider feature:

#### `modules/kind-cluster/variables.tf` -- The Module API
Defines every possible configuration option as a typed variable. Uses Terraform's `optional()` function with defaults so callers only specify what they want to customize.

#### `modules/kind-cluster/main.tf` -- The Kind Cluster Resource
Contains the `kind_cluster` resource with every supported attribute. Uses `dynamic` blocks to generate node configurations from a list variable.

#### `modules/kind-cluster/outputs.tf` -- Credential Export
Exposes the five computed attributes (endpoint, certificates, kubeconfig) needed by providers to connect to the cluster. Sensitive values are marked to prevent accidental log exposure.

#### `modules/kind-cluster/versions.tf` -- Module Provider Contract
Declares the minimum Kind provider version needed (`>= 0.7.0`). Uses `>=` so the root module controls the exact version.

---

## Configuration Reference

### cluster/terraform.tfvars

```hcl
# Cluster name (becomes kubectl context "kind-my-project")
cluster_name = "my-project"

# Kubernetes version
k8s_version = "kindest/node:v1.31.0"

# Custom kubeconfig location (optional)
# kubeconfig_path = "/Users/you/.kube/kind-my-project"
```

### app_demo/terraform.tfvars

```hcl
# Must match cluster_name in ../cluster/terraform.tfvars
# Kind contexts are "kind-<cluster_name>"
kubeconfig_context = "kind-my-project"

# Custom kubeconfig path (optional, defaults to ~/.kube/config)
# kubeconfig_path = "/Users/you/.kube/kind-my-project"
```

### Command-Line Overrides

```bash
# Override cluster name
cd cluster/
terraform apply -var="cluster_name=test-cluster"

# Then update the app context to match
cd ../app_demo/
terraform apply -var="kubeconfig_context=kind-test-cluster"
```

---

## Learning Exercises

These exercises teach Terraform and Kubernetes concepts by making incremental changes.

### Exercise 1: Change the Cluster Name

**Concepts:** Variables, terraform.tfvars, plan output, multi-module coordination

```hcl
# In cluster/terraform.tfvars:
cluster_name = "learning-cluster"
```

```hcl
# In app_demo/terraform.tfvars:
kubeconfig_context = "kind-learning-cluster"
```

```bash
cd cluster && terraform apply     # Destroys and recreates (Kind is immutable)
cd ../app_demo && terraform apply # Redeploy app to the new cluster
```

**What you'll learn:** How Terraform detects changes, why Kind clusters are immutable, and how two root modules coordinate via kubeconfig.

---

### Exercise 2: Add a Third Worker Node

**Concepts:** List variables, dynamic blocks

In `cluster/main.tf`, add a new entry to the `nodes` list:

```hcl
    {
      role = "worker"
      labels = {
        "workload-type" = "batch"
      }
    }
```

```bash
cd cluster && terraform plan   # See: destroy + recreate (cluster replacement)
cd cluster && terraform apply
kubectl get nodes              # Should show 5 nodes
```

**What you'll learn:** How dynamic blocks generate Kubernetes nodes from list data.

---

### Exercise 3: Enable Dual-Stack Networking

**Concepts:** Networking, IP families

In `cluster/main.tf`, add `ip_family` to the networking block:

```hcl
  networking = {
    api_server_port = 6443
    pod_subnet      = "10.200.0.0/16"
    service_subnet  = "10.100.0.0/16"
    kube_proxy_mode = "iptables"
    ip_family       = "dual"
  }
```

```bash
cd cluster && terraform apply
kubectl get nodes -o wide   # Check for IPv6 addresses
kubectl get svc -A          # Services will have dual-stack ClusterIPs
```

**What you'll learn:** How Kubernetes dual-stack networking works.

---

### Exercise 4: Enable Feature Gates

**Concepts:** Kubernetes feature gates, map variables

In `cluster/main.tf`, uncomment and customize the `feature_gates` block:

```hcl
  feature_gates = {
    "GracefulNodeShutdown" = "true"
  }
```

```bash
cd cluster && terraform apply
kubectl get nodes -o jsonpath='{.items[0].status.conditions}' | jq .
```

**What you'll learn:** How Kubernetes feature gates control experimental features.

---

### Exercise 5: Enable Runtime Config

**Concepts:** Kubernetes API groups, HCL map keys

In `cluster/main.tf`, uncomment and customize the `runtime_config` block:

```hcl
  runtime_config = {
    "api_alpha" = "true"   # "_" becomes "/" (api/alpha)
  }
```

```bash
cd cluster && terraform apply
kubectl api-versions   # Look for alpha API versions
```

**What you'll learn:** How Kubernetes API groups are enabled/disabled at the cluster level.

---

### Exercise 6: Install a Custom CNI (Calico)

**Concepts:** CNI plugins, disable_default_cni, cross-module changes

1. Disable kindnet in `cluster/main.tf`:

```hcl
  networking = {
    # ... existing settings ...
    disable_default_cni = true
  }
```

2. Add a Helm release for Calico in `app_demo/main.tf`:

```hcl
resource "helm_release" "calico" {
  name             = "calico"
  repository       = "https://docs.tigera.io/calico/charts"
  chart            = "tigera-operator"
  namespace        = "tigera-operator"
  create_namespace = true
}
```

**What you'll learn:** How to replace Kind's default CNI with a production-grade one, and how changes span both root modules.

---

### Exercise 7: Load a Docker Image (CLI Workaround)

**Concepts:** kind load CLI, local images, container runtime

Since `kind_load` is not yet released, use the Kind CLI directly:

```bash
docker pull nginx:alpine
kind load docker-image nginx:alpine --name dev
kubectl run test --image=nginx:alpine --restart=Never --image-pull-policy=Never
kubectl get pod test
```

**What you'll learn:** How Kind loads images from the local Docker daemon into cluster nodes via containerd.

---

### Exercise 8: Use IPVS Proxy Mode

**Concepts:** kube-proxy modes, IPVS

In `cluster/main.tf`, change the proxy mode:

```hcl
  networking = {
    # ... existing settings ...
    kube_proxy_mode = "ipvs"
  }
```

```bash
cd cluster && terraform apply
kubectl -n kube-system logs -l k8s-app=kube-proxy | grep "Using ipvs"
```

**What you'll learn:** The difference between iptables and IPVS proxy modes.

---

### Exercise 9: Add DNS Search Domains

**Concepts:** DNS resolution, search domains

In `cluster/main.tf`, add custom DNS search domains:

```hcl
  networking = {
    # ... existing settings ...
    dns_search = ["corp.example.com", "internal.local"]
  }
```

```bash
cd cluster && terraform apply
kubectl run test --image=busybox --restart=Never -- cat /etc/resolv.conf
kubectl logs test
```

**What you'll learn:** How DNS search domains affect name resolution inside Kubernetes pods.

---

### Exercise 10: Custom kubeconfig Path

**Concepts:** kubeconfig, pathexpand, cross-module coordination

In `cluster/terraform.tfvars`:

```hcl
kubeconfig_path = "/tmp/my-kind-kubeconfig"
```

In `app_demo/terraform.tfvars`:

```hcl
kubeconfig_path = "/tmp/my-kind-kubeconfig"
```

```bash
cd cluster && terraform apply
cd ../app_demo && terraform apply
```

**What you'll learn:** How Kind generates kubeconfig files and how both modules can be pointed at a custom location.

---

### Exercise 11: Test Kubernetes Version Skew

**Concepts:** Per-node images, version compatibility

In `cluster/main.tf`, give the GPU worker a different version:

```hcl
    {
      role  = "worker"
      image = "kindest/node:v1.30.0"
      labels = {
        "workload-type"         = "gpu"
        "hardware-acceleration" = "true"
      }
      kubeadm_config_patches = [
        "kind: JoinConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    register-with-taints: \"dedicated=gpu:NoSchedule\"\n"
      ]
    }
```

```bash
cd cluster && terraform apply
kubectl get nodes -o wide  # Note the different VERSION column
```

**What you'll learn:** Kubernetes version skew policies and how clusters handle mixed versions.

---

### Exercise 12: Mount Propagation Modes

**Concepts:** Bind mounts, mount propagation

In `cluster/main.tf`, change the propagation mode on the existing mount:

```hcl
    extra_mounts = [{
      host_path      = "/tmp"
      container_path = "/var/local-data"
      propagation    = "Bidirectional"
    }]
```

**Options:**
- `"None"` -- No propagation (fully isolated)
- `"HostToContainer"` -- Host mounts visible in container
- `"Bidirectional"` -- Mounts propagate both directions

**What you'll learn:** How Linux mount namespaces and propagation affect container storage.

---

### Exercise 13: Deploy Your Own App

**Concepts:** Kubernetes resources, Terraform state isolation

Create your own version of `app_demo/` in a sibling folder:

```bash
mkdir my_app && cd my_app
```

Use the same `versions.tf` and `variables.tf` from `app_demo/`, then write your own `main.tf` deploying a different image. This demonstrates how the cluster is reusable across multiple applications.

**What you'll learn:** How separated Terraform root modules enable multiple independent deployments on the same cluster.

---

## Modification Guide

### How to Add a New Helm Chart (app_demo/)

```hcl
resource "helm_release" "my_chart" {
  name             = "my-release"
  repository       = "https://charts.example.com"
  chart            = "my-chart"
  namespace        = "my-namespace"
  create_namespace = true

  set {
    name  = "key"
    value = "value"
  }
}
```

### How to Add Kubernetes Resources (app_demo/)

```hcl
resource "kubernetes_namespace" "app" {
  metadata {
    name = "my-app"
    labels = { environment = "development" }
  }
}

resource "kubernetes_deployment_v1" "app" {
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
      metadata { labels = { app = "my-app" } }
      spec {
        container {
          name  = "app"
          image = "nginx:latest"
          port { container_port = 80 }
        }
      }
    }
  }
}
```

### How to Add More Module Variables (cluster/)

1. Add the variable in `cluster/modules/kind-cluster/variables.tf`
2. Use the variable in `cluster/modules/kind-cluster/main.tf`
3. Pass the value in `cluster/main.tf` module call
4. Optionally expose it as a root variable in `cluster/variables.tf`

### How to Create a Second Cluster

Duplicate the `cluster/` directory:

```bash
cp -r cluster/ cluster-staging/
```

Edit `cluster-staging/terraform.tfvars`:

```hcl
cluster_name = "staging"
k8s_version  = "kindest/node:v1.30.0"
```

Then point `app_demo/` at it:

```hcl
kubeconfig_context = "kind-staging"
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
| `Error: provider not found` | Run `terraform init` in the correct subdirectory |
| IDE shows `blocks of type "set" are not expected here` | Run `terraform init` in the module directory -- the language server needs provider schemas (see [IDE Setup](#vs-code--cursor-ide-setup)) |
| Slow cluster creation | Ensure Docker has enough resources (4GB+ RAM recommended) |
| `Error: context not found` | Check that `kubeconfig_context` in `app_demo/terraform.tfvars` matches the Kind cluster name |
| App deploy fails after cluster recreate | Run `cd app_demo && terraform init` to refresh provider cache |

### Resetting Everything

```bash
# Nuclear option: delete everything and start fresh
cd app_demo && terraform destroy -auto-approve
cd ../cluster && terraform destroy -auto-approve
kind delete clusters --all
cd ../cluster && rm -rf .terraform terraform.tfstate*
cd ../app_demo && rm -rf .terraform terraform.tfstate*
cd ../cluster && terraform init && terraform apply
cd ../app_demo && terraform init && terraform apply
```

### Checking Provider Versions

```bash
cd cluster && terraform providers   # Should show tehcyx/kind
cd ../app_demo && terraform providers  # Should show hashicorp/helm + hashicorp/kubernetes
```

---

## Terraform Concepts Used

This project demonstrates these core Terraform concepts:

| Concept | Where Used | What It Does |
|---------|-----------|--------------|
| **Modules** | `cluster/main.tf` → `modules/kind-cluster/` | Encapsulates reusable infrastructure |
| **Multiple Root Modules** | `cluster/` and `app_demo/` | Separates concerns with independent state |
| **Variables** | All `variables.tf` files | Parameterizes configurations |
| **Outputs** | All `outputs.tf` files | Exports values between modules and to the user |
| **Dynamic Blocks** | `modules/kind-cluster/main.tf` | Generates repeated blocks from lists |
| **Provider Configuration** | `cluster/main.tf`, `app_demo/main.tf` | Connects Terraform to APIs |
| **kubeconfig Auth** | `app_demo/main.tf` provider blocks | Config-path based cluster authentication |
| **Certificate Auth** | `cluster/outputs.tf` | TLS client cert/key for direct API access |
| **Version Constraints** | All `versions.tf` files | Pins reproducible versions |
| **Type Constraints** | Variable `type` attributes | Validates input shapes |
| **Optional Fields** | Variable `optional()` | Allows partial object inputs |
| **Sensitive Values** | Output `sensitive = true` | Protects credentials |
| **Depends On** | `app_demo/main.tf` | Controls resource ordering |
| **Validation** | Module variable `validation` blocks | Custom input validation rules |
| **Try Function** | Module `main.tf` | Safe access to optional attributes |
| **HereDocs** | Multiple files | Multi-line string literals |
| **Helm Provider** | `app_demo/versions.tf` | Manages Helm chart deployments |
| **Kubernetes Provider** | `app_demo/versions.tf` | Manages native Kubernetes resources |

---

## Additional Resources

- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Kind Terraform Provider](https://registry.terraform.io/providers/tehcyx/kind/latest/docs)
- [Kind Provider Source Code](https://github.com/tehcyx/terraform-provider-kind)
- [Terraform Documentation](https://developer.hashicorp.com/terraform/docs)
- [Terraform Modules](https://developer.hashicorp.com/terraform/language/modules)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Helm Provider](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
- [Kubernetes Provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)
