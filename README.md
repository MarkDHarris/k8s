# k8s

A local Kubernetes learning environment built on [Kind](https://kind.sigs.k8s.io/) (Kubernetes IN Docker). Includes Terraform for automated cluster provisioning, sample app deployments, and hands-on RBAC experiments.

---

## Project Structure

```
src/
├── terraform/            Cluster provisioning (Terraform + Kind provider)
│   ├── main.tf           Orchestrates cluster, ingress controller, and demo nginx
│   ├── modules/
│   │   └── kind-cluster/ Reusable Kind cluster module
│   └── README.md         Comprehensive walkthrough with learning exercises
│
├── apps/                 Sample application deployments
│   └── nginx/            Manual nginx deployment via kubectl (NodePort pattern)
│       ├── cluster.yaml  Kind cluster config (standalone, not Terraform)
│       ├── nginx.yaml    Service + Deployment manifests
│       └── README.md     Traffic flow walkthrough
│
└── rbac-test/            RBAC learning experiments
    ├── 01-machine-path/  ServiceAccount → Role → RoleBinding
    ├── 02-human-path/    X.509 certs → Group → RoleBinding
    ├── 03-global-path/   ClusterRole → ClusterRoleBinding
    └── README.md         Progressive walkthrough of all three paths
```

---

## Getting Started

### Option A: Automated (Terraform)

Terraform provisions a full HA cluster (2 control planes, 2 workers), installs the NGINX Ingress Controller, and deploys a demo nginx app -- all in one command.

```bash
cd src/terraform
terraform init
terraform apply

# Verify
kubectl get nodes -o wide
curl http://localhost
```

See [src/terraform/README.md](src/terraform/README.md) for the full walkthrough, configuration reference, and 12 learning exercises.

### Option B: Manual (kubectl)

A lightweight approach using raw YAML manifests. Good for understanding exactly what each Kubernetes resource does.

```bash
cd src/apps/nginx
kind create cluster --config cluster.yaml
kubectl apply -f nginx.yaml
curl http://localhost:8080
```

See [src/apps/nginx/README.md](src/apps/nginx/README.md) for the traffic flow explanation.

---

## RBAC Experiments

After you have a running cluster (via either option above), work through the RBAC labs:

```bash
cd src/rbac-test
```

Three progressive paths covering ServiceAccount auth, X.509 certificate auth, and cluster-wide permissions. See [src/rbac-test/README.md](src/rbac-test/README.md) for the full walkthrough.

---

## Prerequisites

| Tool | Installation |
|------|-------------|
| **Docker** | [Install guide](https://docs.docker.com/get-docker/) |
| **Kind** | `brew install kind` |
| **kubectl** | `brew install kubectl` |
| **Terraform** | `brew install terraform` (only for Option A) |
| **Helm** | `brew install helm` (optional) |
