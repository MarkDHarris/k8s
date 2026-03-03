# RBAC Learning Lab

A hands-on walkthrough of Kubernetes Role-Based Access Control (RBAC), organized into three progressive experiments. Each builds on the previous one, moving from the simplest form of identity (ServiceAccount) to human user authentication (X.509 certificates) to cluster-wide permissions (ClusterRole).

---

## Prerequisites

- A running Kubernetes cluster (use the [terraform/](../../terraform/) folder or `kind create cluster`)
- `kubectl` configured to talk to the cluster
- `openssl` (for the human-path certificate exercises)

### Initial Setup

Create the shared namespace and ServiceAccount used across the experiments:

```bash
kubectl create namespace rbac-test
kubectl create serviceaccount my-app-sa -n rbac-test
```

---

## Overview

| Path | Identity Type | Scope | What You Learn |
|------|--------------|-------|----------------|
| [01-machine-path](01-machine-path/) | ServiceAccount | Namespace | How pods authenticate to the API server; Role + RoleBinding basics |
| [02-human-path](02-human-path/) | X.509 Certificate (User/Group) | Namespace | How humans authenticate; certificate signing; group-based bindings |
| [03-global-path](03-global-path/) | Group (from 02) | Cluster-wide | ClusterRole vs Role; cluster-scoped resources (nodes) |

```
Scope narrows → widens:

01: ServiceAccount ──→ Role ──→ RoleBinding ──→ pods (in rbac-test)
02: X.509 User/Group ─→ Role ──→ RoleBinding ──→ pods (in rbac-test)
03: Group ─────────────→ ClusterRole ──→ ClusterRoleBinding ──→ nodes (cluster-wide)
```

---

## Path 1: Machine Identity (ServiceAccount)

**Concept:** Pods use ServiceAccounts to authenticate to the Kubernetes API. A ServiceAccount is an in-cluster identity bound to a namespace.

**Files:**
- `01-machine-path/role.yaml` -- A `Role` granting read access to pods in `rbac-test`
- `01-machine-path/rolebinding.yaml` -- Binds the Role to the `my-app-sa` ServiceAccount

**Steps:**

```bash
# Apply the Role (defines what actions are allowed)
kubectl apply -f 01-machine-path/role.yaml

# Apply the RoleBinding (connects the Role to the ServiceAccount)
kubectl apply -f 01-machine-path/rolebinding.yaml

# Test: can the ServiceAccount list pods?
kubectl auth can-i list pods \
  --as=system:serviceaccount:rbac-test:my-app-sa \
  -n rbac-test
# Expected: yes

# Test: can it list pods in the default namespace?
kubectl auth can-i list pods \
  --as=system:serviceaccount:rbac-test:my-app-sa \
  -n default
# Expected: no (Role is namespace-scoped)
```

**Key Takeaway:** A `Role` + `RoleBinding` grants permissions within a single namespace only.

---

## Path 2: Human Identity (X.509 Certificates)

**Concept:** Human users authenticate using X.509 client certificates signed by the cluster's Certificate Authority. The certificate's `CN` (Common Name) becomes the username, and `O` (Organization) becomes the group membership.

**Files:**
- `02-human-path/groupbinding.yaml` -- Binds the existing `pod-reader` Role to the `developers` group

**Steps:**

```bash
# Generate a private key for the user "mark"
openssl genrsa -out mark.key 2048

# Create a Certificate Signing Request
# CN=mark (username), O=developers (group)
openssl req -new -key mark.key -out mark.csr -subj "/CN=mark/O=developers"

# Submit the CSR to the Kubernetes cluster for signing
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: mark
spec:
  request: $(cat mark.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
  - client auth
EOF

# Approve the CSR (in production, this would require admin review)
kubectl certificate approve mark

# Retrieve the signed certificate
kubectl get csr mark -o jsonpath='{.status.certificate}' | base64 --decode > mark.crt

# Configure kubectl credentials for mark
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
kubectl config set-credentials mark --client-key=mark.key --client-certificate=mark.crt
kubectl config set-context mark-context --cluster=$CLUSTER_NAME --user=mark

# Test: mark has no permissions yet
kubectl get pods -n rbac-test --context=mark-context
# Expected: Forbidden

# Apply the group binding (grants pod-reader to the "developers" group)
kubectl apply -f 02-human-path/groupbinding.yaml

# Test again: mark is in the "developers" group, so now has access
kubectl get pods -n rbac-test --context=mark-context
# Expected: success (empty list or running pods)
```

**Key Takeaway:** The `O=developers` field in the certificate maps to a Kubernetes group. A single RoleBinding to the group grants access to all members -- no per-user bindings needed.

---

## Path 3: Cluster-Wide Permissions (ClusterRole)

**Concept:** `ClusterRole` + `ClusterRoleBinding` grants permissions across all namespaces and for cluster-scoped resources like nodes, persistent volumes, and namespaces themselves.

**Files:**
- `03-global-path/clusterrole.yaml` -- A `ClusterRole` granting read access to nodes
- `03-global-path/clusterrolebinding.yaml` -- Binds the ClusterRole to the `developers` group

**Steps:**

```bash
# Apply the ClusterRole
kubectl apply -f 03-global-path/clusterrole.yaml

# Apply the ClusterRoleBinding
kubectl apply -f 03-global-path/clusterrolebinding.yaml

# Test: mark (as a member of "developers") can now list nodes
kubectl get nodes --context=mark-context
# Expected: success (shows cluster nodes)
```

**Key Takeaway:** Use `ClusterRole` + `ClusterRoleBinding` for cluster-scoped resources. Use `ClusterRole` + `RoleBinding` (in a specific namespace) to reuse a ClusterRole at namespace scope.

---

## RBAC Mental Model

```
WHO                          WHAT                         WHERE
─────────────────────        ─────────────────────        ─────────────────────
ServiceAccount               Role                         RoleBinding
  (pods/machines)              (namespace-scoped rules)     (connects WHO→WHAT
                                                             in one namespace)
User / Group                 ClusterRole
  (humans, via certs           (cluster-scoped rules)     ClusterRoleBinding
   or OIDC)                                                 (connects WHO→WHAT
                                                             cluster-wide)
```

---

## Cleanup

```bash
# Remove RBAC resources
kubectl delete -f 03-global-path/
kubectl delete -f 02-human-path/
kubectl delete -f 01-machine-path/

# Remove the namespace (also deletes the ServiceAccount)
kubectl delete namespace rbac-test

# Remove mark's kubectl context and credentials
kubectl config delete-context mark-context
kubectl config delete-user mark

# Remove generated certificate files
rm -f mark.key mark.csr mark.crt

# Delete the CSR from the cluster
kubectl delete csr mark
```
