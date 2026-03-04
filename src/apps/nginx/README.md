# NGINX Demo App -- kubectl Deployment

Deploys an NGINX web server with full Ingress routing into an **existing** Kind cluster using raw Kubernetes YAML and `kubectl`. This is the **kubectl equivalent** of the Terraform approach in [`../../terraform/app_demo/`](../../terraform/app_demo/) -- both deploy identical application resources into the same cluster.

> **Prerequisite:** A Kind cluster must already be running. Create one with:
>
> ```bash
> cd ../../terraform/cluster && terraform init && terraform apply
> ```
>
> Or use the Kind CLI directly: `kind create cluster --name dev`

---

## Two Ways to Deploy the Same App

This folder and `terraform/app_demo/` deploy the exact same resources into the same cluster:

| Approach | Location | Tool | What It Deploys |
|----------|----------|------|-----------------|
| **Terraform** | `terraform/app_demo/` | `terraform apply` | Helm chart + HCL resource blocks |
| **kubectl** | `apps/nginx/` (this folder) | `kubectl apply` | Official manifest URL + YAML file |

Both deploy:
1. NGINX Ingress Controller
2. A `demo` namespace
3. An NGINX Deployment (2 replicas with liveness/readiness probes)
4. A ClusterIP Service
5. An Ingress resource routing `http://localhost/` to the NGINX pods

The result is identical -- `curl http://localhost` returns the NGINX welcome page.

---

## Resource Mapping: Terraform ↔ kubectl

Every resource in `terraform/app_demo/main.tf` has a 1:1 equivalent here:

| Terraform Resource | Terraform Type | kubectl Equivalent | Source |
|--------------------|----------------|-------------------|--------|
| `helm_release.ingress_nginx` | Helm chart | Official Kind manifest | Applied via URL (see Quick Start) |
| `kubernetes_namespace.demo` | `kubernetes_namespace` | `kind: Namespace` | `nginx.yaml` |
| `kubernetes_deployment_v1.nginx` | `kubernetes_deployment_v1` | `kind: Deployment` | `nginx.yaml` |
| `kubernetes_service_v1.nginx` | `kubernetes_service_v1` | `kind: Service` | `nginx.yaml` |
| `kubernetes_ingress_v1.nginx` | `kubernetes_ingress_v1` | `kind: Ingress` | `nginx.yaml` |

---

## Table of Contents

- [What Gets Created](#what-gets-created)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Files](#files)
- [The Journey of a Request](#the-journey-of-a-request)
- [Terraform vs kubectl: Key Differences](#terraform-vs-kubectl-key-differences)
- [Learning Exercises](#learning-exercises)
- [Cleanup](#cleanup)

---

## What Gets Created

| Resource | Name | Namespace | Details |
|----------|------|-----------|---------|
| **Ingress Controller** | ingress-nginx | ingress-nginx | Official NGINX Ingress Controller for Kind |
| **Namespace** | demo | -- | Isolates app from system resources |
| **Deployment** | nginx | demo | 2 replicas of `nginx:stable` with liveness/readiness probes |
| **Service** | nginx | demo | ClusterIP, routes port 80 → container port 80 |
| **Ingress** | nginx | demo | Routes `http://localhost/` → nginx Service |

---

## Prerequisites

A running Kind cluster with port mappings for 80/443 on a control-plane node labeled `ingress-ready=true`. The cluster created by `terraform/cluster/` meets these requirements.

| Tool | Minimum Version | Installation |
|------|----------------|--------------|
| **kubectl** | >= 1.28 | `brew install kubectl` or [install guide](https://kubernetes.io/docs/tasks/tools/) |

Verify you have cluster access:

```bash
kubectl get nodes    # Should show your Kind cluster nodes
```

---

## Quick Start

```bash
# ──────────────────────────────────────────────────────────────
# Step 1: Deploy the NGINX Ingress Controller
# ──────────────────────────────────────────────────────────────
# This mirrors: helm_release.ingress_nginx in terraform/app_demo/main.tf
#
# The official Kind-specific manifest configures hostPort, nodeSelector
# (ingress-ready=true), and control-plane tolerations -- the same
# settings the Terraform Helm chart uses.
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Wait for the Ingress Controller to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# ──────────────────────────────────────────────────────────────
# Step 2: Deploy the demo NGINX app
# ──────────────────────────────────────────────────────────────
# This mirrors the kubernetes_* resources in terraform/app_demo/main.tf
kubectl apply -f nginx.yaml

# Wait for pods to be ready
kubectl wait --namespace demo \
  --for=condition=ready pod \
  --selector=app=nginx \
  --timeout=60s

# ──────────────────────────────────────────────────────────────
# Step 3: Test
# ──────────────────────────────────────────────────────────────
curl http://localhost
# Should return the NGINX welcome page -- same result as the Terraform approach
```

---

## Files

| File | Purpose | Terraform Equivalent |
|------|---------|---------------------|
| `nginx.yaml` | Namespace + Deployment + Service + Ingress | `terraform/app_demo/main.tf` (kubernetes_* resources) |
| `README.md` | This documentation | |

---

## The Journey of a Request

When you run `curl http://localhost`, here is the path the request takes:

### 1. Your Machine → Kind Node

The cluster's control-plane node has `extraPortMappings` forwarding host port 80 to container port 80. Docker listens on your machine's port 80 and forwards packets into the Kind node.

### 2. Kind Node → Ingress Controller

The NGINX Ingress Controller runs as a pod on the control-plane node (selected via the `ingress-ready=true` label). It binds to hostPort 80/443 and receives the HTTP request.

### 3. Ingress Controller → Service

The `Ingress` resource in `nginx.yaml` says "route path `/` to Service `nginx` on port 80." The Ingress Controller looks up the Service's endpoints and forwards traffic.

### 4. Service → Pod

The `Service` has `selector: { app: nginx }`, matching the Deployment's pod labels. Traffic is load-balanced across the 2 healthy NGINX replicas.

### Traffic Flow Summary

```
curl http://localhost
     │
     ▼
Host port 80  ──────────────────────────────  Cluster port mapping
     │
     ▼
Kind node port 80  ─────────────────────────  Ingress Controller (hostPort)
     │
     ▼
Ingress rule: / → nginx:80  ───────────────  nginx.yaml (Ingress)
     │
     ▼
ClusterIP Service nginx:80  ───────────────  nginx.yaml (Service)
     │
     ▼
Pod nginx:80 (one of 2 replicas)  ─────────  nginx.yaml (Deployment)
```

---

## Terraform vs kubectl: Key Differences

Understanding both approaches deepens your knowledge of Kubernetes and infrastructure-as-code:

| Aspect | Terraform (`app_demo/`) | kubectl (this folder) |
|--------|------------------------|----------------------|
| **Ingress Controller** | Helm chart via `helm_release` | Official manifest via `kubectl apply -f <URL>` |
| **App deployment** | HCL resource blocks | Raw Kubernetes YAML |
| **State tracking** | `terraform.tfstate` (tracks all resources) | No state file (cluster is the source of truth) |
| **Drift detection** | `terraform plan` shows diffs | Manual: `kubectl diff -f nginx.yaml` |
| **Rollback** | `terraform apply` with prior state | `kubectl rollout undo` or reapply old YAML |
| **Deletion** | `terraform destroy` (removes all managed resources) | `kubectl delete -f nginx.yaml` (manual) |
| **Dependencies** | Automatic via `depends_on` and reference chains | Manual ordering (deploy Ingress Controller first) |
| **Idempotency** | Built-in (apply is always safe to re-run) | Built-in (`kubectl apply` is idempotent) |
| **Learning value** | Teaches IaC, providers, modules, state | Teaches raw K8s API, YAML structure, kubectl |

### When to Use Each

- **kubectl/YAML**: Learning Kubernetes fundamentals, quick prototyping, debugging, understanding what Terraform abstracts away.
- **Terraform**: Production deployments, team environments, reproducible infrastructure, managing multiple clusters, auditing changes via state.

---

## Learning Exercises

### Exercise 1: Scale the Deployment

```bash
# kubectl approach -- imperative
kubectl -n demo scale deployment nginx --replicas=4
kubectl -n demo get pods -o wide

# Terraform equivalent -- declarative (edit app_demo/main.tf, change replicas = 4)
# Then: terraform apply
```

### Exercise 2: Inspect the Ingress Controller

```bash
kubectl -n ingress-nginx get pods
kubectl -n ingress-nginx logs -l app.kubernetes.io/component=controller --tail=20
kubectl -n demo describe ingress nginx
kubectl -n demo get endpoints nginx
```

### Exercise 3: Observe Health Probes

```bash
kubectl -n demo get pods -w
kubectl -n demo describe pod -l app=nginx | grep -A5 "Liveness\|Readiness"
```

### Exercise 4: Use kubectl diff (Terraform plan equivalent)

```bash
# Edit nginx.yaml (e.g., change replicas to 3)
# Then preview the change without applying:
kubectl diff -f nginx.yaml
```

### Exercise 5: Deploy a Second App

Create a new YAML file for a different app in the same cluster:

```yaml
# httpbin.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: httpbin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
  namespace: httpbin
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
  template:
    metadata:
      labels:
        app: httpbin
    spec:
      containers:
        - name: httpbin
          image: kennethreitz/httpbin
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: httpbin
spec:
  type: ClusterIP
  selector:
    app: httpbin
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: httpbin
  namespace: httpbin
spec:
  ingressClassName: nginx
  rules:
    - host: httpbin.localhost
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: httpbin
                port:
                  number: 80
```

```bash
kubectl apply -f httpbin.yaml
curl -H "Host: httpbin.localhost" http://localhost/get
```

This demonstrates how the cluster supports multiple independent applications -- the same pattern as deploying multiple Terraform app modules.

---

## Cleanup

```bash
# Remove just the demo app (keep the cluster and Ingress Controller)
kubectl delete -f nginx.yaml

# Remove the Ingress Controller too
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```
