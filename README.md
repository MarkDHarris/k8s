# k8s

A local Kubernetes learning environment built on [Kind](https://kind.sigs.k8s.io/) (Kubernetes IN Docker). Includes Terraform for automated cluster provisioning, sample app deployments, and hands-on research labs.

---

## Project Structure

```
src/
├── terraform/                  Cluster provisioning (Terraform + Kind provider)
│   ├── main.tf                 Orchestrates cluster, ingress controller, and demo nginx
│   ├── modules/
│   │   └── kind-cluster/       Reusable Kind cluster module
│   └── README.md               Comprehensive walkthrough with 12 learning exercises
│
├── apps/                       Sample application deployments
│   └── nginx/                  Manual nginx deployment via kubectl (NodePort pattern)
│       ├── cluster.yaml        Kind cluster config (standalone, not Terraform)
│       ├── nginx.yaml          Service + Deployment manifests
│       └── README.md           Traffic flow walkthrough
│
└── research/                   Hands-on learning labs
    ├── rbac-test/              RBAC experiments (3 progressive paths)
    │   ├── 01-machine-path/    ServiceAccount → Role → RoleBinding
    │   ├── 02-human-path/      X.509 certs → Group → RoleBinding
    │   ├── 03-global-path/     ClusterRole → ClusterRoleBinding
    │   └── README.md           Progressive walkthrough
    │
    └── tekton-pipelines/       Tekton CI/CD pipeline lab
        ├── 01-10 YAML files    Progressive labs from hello-world to build pipelines
        └── README.md           Full lab guide with production pipeline analysis
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

## Research Labs

After you have a running cluster (via either option above), work through the labs:

### RBAC

Three progressive paths covering ServiceAccount auth, X.509 certificate auth, and cluster-wide permissions.

See [src/research/rbac-test/README.md](src/research/rbac-test/README.md).

### Tekton Pipelines

Five progressive labs that take you from a hello-world Task to a multi-stage build pipeline, then decode a production pipeline.

See [src/research/tekton-pipelines/README.md](src/research/tekton-pipelines/README.md).

---

## Prerequisites

| Tool | Installation |
|------|-------------|
| **Docker** | [Install guide](https://docs.docker.com/get-docker/) |
| **Kind** | `brew install kind` |
| **kubectl** | `brew install kubectl` |
| **Terraform** | `brew install terraform` (only for Option A) |
| **Helm** | `brew install helm` (optional) |
| **tkn** | `brew install tektoncd-cli` (for Tekton labs) |
