# Kind Cluster -- CLI Approach

Creates a fully-featured, multi-node Kubernetes cluster on your local machine using the [Kind CLI](https://kind.sigs.k8s.io/) and a YAML configuration file. This is the **Kind-native alternative** to the Terraform approach in [`../terraform/cluster/`](../terraform/cluster/) -- both produce identical clusters.

> **What is a Kind cluster config?**
> It's a YAML file that Kind reads to customize the cluster it creates. Without a config, `kind create cluster` gives you a single-node cluster with defaults. With a config, you control the number of nodes, networking, labels, taints, mounts, port mappings, and more.

---

## Two Ways to Create the Same Cluster

| Approach | Location | Command | State Tracking | Node Count Control |
|----------|----------|---------|----------------|-------------------|
| **Kind CLI** | `kind-cluster/` (this folder) | `kind create cluster --config` | None (cluster is the source of truth) | Edit YAML (add/remove node entries) |
| **Terraform** | `terraform/cluster/` | `terraform apply` | `terraform.tfstate` | Variables: `control_plane_count`, `worker_count` |

Both create the same cluster:
- 2 control-plane nodes (HA with replicated etcd)
- 2 worker nodes (1 general-purpose with storage, 1 GPU-tainted)
- Custom networking (pod/service CIDRs, iptables proxy)
- Port mappings (80/443 on control-plane for ingress)
- Node labels, taints, and mounts

---

## Quick Start

```bash
# Create the cluster
kind create cluster --config cluster.yaml --name dev

# Verify (should show 4 nodes)
kubectl get nodes -o wide

# Done! Deploy apps with:
#   kubectl approach:  cd ../apps/nginx && kubectl apply -f nginx.yaml
#   Terraform approach: cd ../terraform/app_demo && terraform init && terraform apply

# Cleanup
kind delete cluster --name dev
```

---

## What Gets Created

| Component | Details |
|-----------|---------|
| **Control Plane Nodes** | 2 nodes (HA cluster with replicated etcd) |
| **Worker Nodes** | 2 nodes (1 general-purpose with storage, 1 GPU-tainted) |
| **Networking** | Pod CIDR 10.200.0.0/16, Service CIDR 10.100.0.0/16, iptables proxy, API server on port 6443 |
| **Port Mappings** | Host ports 80/443 → control-plane node (for ingress) |
| **Storage** | Host /tmp mounted into Worker #1 at /var/local-data |
| **Labels** | Role, workload-type, and ingress-ready labels on all nodes |
| **Taints** | `dedicated=gpu:NoSchedule` on Worker #2 |

---

## Kind CLI vs Terraform: When to Use Each

| Aspect | Kind CLI (this folder) | Terraform (`terraform/cluster/`) |
|--------|----------------------|----------------------------------|
| **Setup** | Just Kind + Docker | Kind + Docker + Terraform |
| **Speed** | Fastest (no provider init) | Slightly slower (provider download + init) |
| **State** | Stateless (cluster is truth) | Stateful (`terraform.tfstate` tracks everything) |
| **Node counts** | Edit YAML manually | Variables: `control_plane_count = 3` |
| **Drift detection** | None (use `kind get clusters` + `kubectl`) | `terraform plan` shows what changed |
| **Reproducibility** | YAML file is the spec | YAML + state + lock file |
| **Destroy** | `kind delete cluster --name dev` | `terraform destroy` |
| **Learning value** | Teaches Kind config, YAML structure, CLI | Teaches IaC, providers, modules, state, variables |
| **Best for** | Quick local dev, learning Kind, CI/CD scripts | Team environments, auditable changes, multi-cluster |

### Rules of Thumb

- **Use the Kind CLI** when you want to spin up a cluster fast, are learning Kind's features, or need a cluster in a CI/CD pipeline script.
- **Use Terraform** when you want state tracking, parameterized node counts, reproducible builds, or are learning infrastructure-as-code.
- Both produce the **same cluster**. The apps (`apps/nginx/` and `terraform/app_demo/`) work with either.

---

## Files

| File | Purpose |
|------|---------|
| `cluster.yaml` | Kind cluster configuration (nodes, networking, labels, taints, mounts, port mappings) |
| `README.md` | This documentation |
| `../../.vscode/settings.json` | Workspace settings -- maps Kind YAML files to the local JSON schema |
| `../../.vscode/kind-config-schema.json` | JSON schema for Kind v1alpha4 cluster config (enables validation + autocomplete) |

---

## VS Code / Cursor IDE Setup

Kind does not publish an official JSON schema for its cluster config format. Without configuration, the Red Hat YAML extension (`redhat.vscode-yaml`) sees `apiVersion:` and `kind:` fields and assumes the file is a standard Kubernetes resource, producing false errors like **"Property kind is not allowed"** on every field.

This repo includes a local JSON schema and workspace settings that fix this automatically.

### What's Included

| File | Purpose |
|------|---------|
| `.vscode/kind-config-schema.json` | JSON schema describing the Kind v1alpha4 cluster config format (all valid properties, types, enums) |
| `.vscode/settings.json` | Workspace settings that map the schema to `**/kind-cluster/cluster.yaml` files |

The workspace settings handle schema resolution automatically when you open the project. No inline directives are needed in `cluster.yaml` itself.

### If You Still See Errors

If the Red Hat YAML extension still shows validation warnings after opening the project:

1. **Reload the window** -- `Cmd+Shift+P` (macOS) or `Ctrl+Shift+P` (Linux/Windows) > `Developer: Reload Window`
2. **Verify the YAML extension is installed** -- search for `redhat.vscode-yaml` in Extensions
3. **Check that workspace settings are active** -- open Settings (`Cmd+,`), switch to **Workspace** tab, and confirm `yaml.schemas` is populated

### Adding Schema Support to Other Projects

To reuse this schema in a different repo or for additional Kind config files:

**Option A: Inline directive** (per-file, no settings needed)

Add this as the first line of any Kind cluster config YAML, using the relative path from that file to the schema:

```yaml
# yaml-language-server: $schema=../../.vscode/kind-config-schema.json
```

> **Note:** The relative path must resolve from the YAML file's location. Inline directives are convenient for single files but workspace settings (Option B) are more reliable across project structures.

**Option B: Workspace settings** (recommended, applies to file patterns)

Copy `.vscode/kind-config-schema.json` into the other project, then add to that project's `.vscode/settings.json`:

```json
{
  "yaml.schemas": {
    "./.vscode/kind-config-schema.json": [
      "**/kind-cluster/**/*.yaml",
      "**/kind-cluster/**/*.yml"
    ]
  }
}
```

Adjust the glob patterns to match wherever your Kind config files live.

**Option C: User settings** (global, all projects)

Add to your global VS Code/Cursor settings (`Cmd+Shift+P` > `Preferences: Open User Settings (JSON)`):

```json
{
  "yaml.schemas": {
    "/absolute/path/to/kind-config-schema.json": [
      "**/kind-cluster/**/*.yaml"
    ]
  }
}
```

---

## Kind Config Reference

The `cluster.yaml` file uses every major Kind configuration feature:

### Top-Level Fields

| Field | Used | Description |
|-------|------|-------------|
| `kind` | Yes | Always `"Cluster"` |
| `apiVersion` | Yes | Always `"kind.x-k8s.io/v1alpha4"` |
| `networking` | Yes | Cluster-wide networking configuration |
| `containerdConfigPatches` | Commented | TOML patches for containerd runtime |
| `featureGates` | Commented | Kubernetes feature gate toggles |
| `runtimeConfig` | Commented | Kubernetes API runtime overrides |
| `nodes` | Yes | List of node definitions |

### Networking Options

| Option | Used | Description |
|--------|------|-------------|
| `apiServerAddress` | Default | API server bind IP (default: 127.0.0.1) |
| `apiServerPort` | Yes | API server port (set to 6443) |
| `podSubnet` | Yes | Pod IP CIDR range |
| `serviceSubnet` | Yes | Service ClusterIP CIDR range |
| `disableDefaultCNI` | Commented | Disable kindnet for custom CNI |
| `kubeProxyMode` | Yes | iptables / ipvs / nftables |
| `ipFamily` | Commented | ipv4 / ipv6 / dual |
| `dnsSearch` | Commented | Custom DNS search domains |

### Node Options

| Option | Used | Description |
|--------|------|-------------|
| `role` | Yes | `"control-plane"` or `"worker"` |
| `image` | Commented | Per-node image override |
| `labels` | Yes | Kubernetes node labels (map) |
| `kubeadmConfigPatches` | Yes | YAML patches for kubeadm |
| `extraMounts` | Yes | Host-to-container bind mounts |
| `extraPortMappings` | Yes | Host-to-container port forwards |

### Extra Mount Options

| Option | Used | Description |
|--------|------|-------------|
| `hostPath` | Yes | Source path on host |
| `containerPath` | Yes | Destination in container |
| `readOnly` | Yes | Write protection flag |
| `propagation` | Yes | None / HostToContainer / Bidirectional |
| `selinuxRelabel` | Yes | SELinux relabel flag |

### Extra Port Mapping Options

| Option | Used | Description |
|--------|------|-------------|
| `containerPort` | Yes | Port inside the container |
| `hostPort` | Yes | Port on the host |
| `listenAddress` | Yes | Host bind IP (0.0.0.0 = all interfaces) |
| `protocol` | Yes | TCP / UDP / SCTP |

---

## Customization Examples

### Change Node Counts

Unlike Terraform (which uses variables), Kind YAML requires explicit node entries. To add a third worker, add another `- role: worker` entry:

```yaml
nodes:
  - role: control-plane
    # ... (existing config)
  - role: control-plane
    # ... (existing config)
  - role: worker
    # ... (existing config)
  - role: worker
    # ... (existing config)
  - role: worker        # NEW: third worker
    labels:
      workload-type: general
```

To create a single control-plane cluster with no HA, remove the second control-plane entry.

### Change Kubernetes Version

```bash
kind create cluster --config cluster.yaml --name dev --image kindest/node:v1.30.0
```

Or set `image:` on individual nodes in the YAML for mixed-version testing.

### Enable Dual-Stack Networking

Uncomment in `cluster.yaml`:

```yaml
networking:
  ipFamily: "dual"
```

### Install a Custom CNI

Uncomment in `cluster.yaml`:

```yaml
networking:
  disableDefaultCNI: true
```

Then install your CNI after cluster creation:

```bash
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

### Add DNS Search Domains

Uncomment in `cluster.yaml`:

```yaml
networking:
  dnsSearch:
    - "corp.example.com"
    - "internal.local"
```

---

## Useful Kind CLI Commands

```bash
# Create a cluster
kind create cluster --config cluster.yaml --name dev

# List clusters
kind get clusters

# Get kubeconfig for a cluster
kind get kubeconfig --name dev

# Export kubeconfig to a file
kind get kubeconfig --name dev > ~/.kube/kind-dev

# Load a local Docker image into the cluster (no registry needed)
kind load docker-image myapp:latest --name dev

# Delete a cluster
kind delete cluster --name dev

# Delete ALL clusters
kind delete clusters --all
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `ERROR: failed to create cluster: node(s) already exist` | Delete first: `kind delete cluster --name dev` |
| `ERROR: port 80 already in use` | Stop the process using port 80: `lsof -i :80` |
| Nodes stuck in `NotReady` | Wait 1-2 minutes, check: `kubectl describe node <name>` |
| `error: context "kind-dev" does not exist` | Cluster may not be running: `kind get clusters` |

---

## Additional Resources

- [Kind Configuration Reference](https://kind.sigs.k8s.io/docs/user/configuration/)
- [Kind Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/)
- [Kind Ingress Setup](https://kind.sigs.k8s.io/docs/user/ingress/)
- [Kind Local Registry](https://kind.sigs.k8s.io/docs/user/local-registry/)
- [Kind Multi-Node Clusters](https://kind.sigs.k8s.io/docs/user/quick-start/#multi-node-clusters)
