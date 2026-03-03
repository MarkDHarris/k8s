# Nginx on Kind -- Manual Deployment (kubectl)

A self-contained example that deploys an nginx web server to a Kind cluster using raw Kubernetes YAML and `kubectl`. This demonstrates the NodePort traffic pattern end-to-end, from your browser to a running Pod.

> **Note:** The [terraform/](../../terraform/) folder provides an alternative automated approach that creates a cluster *and* deploys nginx via Ingress. This folder is the manual/kubectl equivalent -- useful for understanding exactly what each manifest does.

---

## Prerequisites

| Tool | Installation |
|------|-------------|
| **Docker** | [Install guide](https://docs.docker.com/get-docker/) |
| **Kind** | `brew install kind` or [install guide](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) |
| **kubectl** | `brew install kubectl` or [install guide](https://kubernetes.io/docs/tasks/tools/) |

---

## Quick Start

```bash
# 1. Create the Kind cluster (1 control-plane + 3 workers)
kind create cluster --config cluster.yaml

# 2. Deploy nginx (Service + Deployment)
kubectl apply -f nginx.yaml

# 3. Wait for the pod to be ready
kubectl wait --for=condition=Ready pod -l app=nginx --timeout=60s

# 4. Test it
curl http://localhost:8080

# 5. Clean up when done
kind delete cluster
```

---

## What Gets Created

| Resource | Name | Details |
|----------|------|---------|
| **Kind Cluster** | `kind` (default) | 1 control-plane + 3 workers, port 8080 mapped to NodePort 30000 |
| **Service** | `nginx-service` | NodePort on port 30000, routes to container port 80 |
| **Deployment** | `nginx-frontend` | 1 replica of `nginx:alpine`, pinned to the `worker2` node via nodeAffinity |

---

## Files

| File | Purpose |
|------|---------|
| `cluster.yaml` | Kind cluster configuration -- defines nodes, labels, and the host-to-container port mapping that makes `localhost:8080` work |
| `nginx.yaml` | Kubernetes Service (NodePort) + Deployment for nginx |

---

## The Journey of a Request

When you type `http://localhost:8080` into your browser, here is the path the request takes:

### 1. Your Laptop (Host) → The Cluster Node

- **Config:** In `cluster.yaml`, `extraPortMappings` maps `hostPort: 8080` → `containerPort: 30000`.
- **What happens:** Docker listens on your laptop's port 8080 and forwards packets to port 30000 on the `kind-control-plane` container.

> Even though the nginx Pod runs on a worker node, the NodePort Service makes port 30000 available on **every** node, including the control plane.

### 2. The Node → The Service

- **Config:** In `nginx.yaml`, the Service defines `type: NodePort` with `nodePort: 30000`.
- **What happens:** `kube-proxy` is listening on port 30000 on all nodes. It catches the packet and looks up the Service's backend.

### 3. The Service → The Pod

- **Config:** The Service has `selector: {app: nginx}`, and the Deployment's Pod template carries that same label.
- **What happens:** The Service keeps a live list of matching Pods (Endpoints). It picks one and forwards traffic to its internal IP on port 80.

### Connecting the Dots

| Component | Port | Defined In | Purpose |
|-----------|------|-----------|---------|
| **Browser** | `8080` | `cluster.yaml` (`hostPort`) | Entry point on your laptop |
| **Cluster Node** | `30000` | `cluster.yaml` (`containerPort`) | Entry point into the Kubernetes network |
| **Service** | `30000` | `nginx.yaml` (`nodePort`) | Listens on the node to catch traffic |
| **Pod** | `80` | `nginx.yaml` (`targetPort`) | The actual nginx process inside the container |

---

## Cluster Topology

```
┌─ Your Machine ──────────────────────────────────────────────────┐
│  localhost:8080                                                  │
│       │                                                         │
│  ┌─ Docker (Kind Cluster) ───────────────────────────────────┐  │
│  │    ▼                                                      │  │
│  │  ┌─────────────────────┐                                  │  │
│  │  │  Control Plane      │  Ports: 80, 443, 30000           │  │
│  │  │  ingress-ready=true │  (30000 receives your traffic)   │  │
│  │  └─────────────────────┘                                  │  │
│  │                                                           │  │
│  │  ┌──────────┐  ┌──────────────────┐  ┌──────────┐        │  │
│  │  │ Worker 1 │  │ Worker 2         │  │ Worker 3 │        │  │
│  │  │ tier=    │  │ tier=worker2     │  │ tier=    │        │  │
│  │  │ worker1  │  │ ← nginx Pod here │  │ worker3  │        │  │
│  │  └──────────┘  └──────────────────┘  └──────────┘        │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Learning Exercises

### Move the Pod to a Different Worker

Change the nodeAffinity in `nginx.yaml` from `worker2` to `worker1` or `worker3`, then redeploy:

```bash
kubectl apply -f nginx.yaml
kubectl get pods -o wide   # Observe the NODE column
```

### Scale the Deployment

```bash
kubectl scale deployment nginx-frontend --replicas=3
kubectl get pods -o wide   # Only worker2 pods schedule (due to affinity)
```

To spread across all workers, remove the `affinity` block from `nginx.yaml` and reapply.

### Inspect the Service Endpoints

```bash
kubectl get endpoints nginx-service
kubectl describe svc nginx-service
```

---

## Cleanup

```bash
kind delete cluster
```
