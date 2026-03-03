# Argo CD -- Hands-On Lab

A progressive, hands-on lab that takes you from zero to GitOps continuous delivery with [Argo CD](https://argo-cd.readthedocs.io/) on a local Kind cluster. By the end, you'll understand how to declaratively manage Kubernetes deployments from Git.

---

## Table of Contents

- [Background: What Is Argo CD?](#background-what-is-argo-cd)
- [Setup](#setup)
- [Lab 1: Your First Application](#lab-1-your-first-application)
- [Lab 2: Deploying Your Own Manifests](#lab-2-deploying-your-own-manifests)
- [Lab 3: Auto-Sync and Self-Healing](#lab-3-auto-sync-and-self-healing)
- [Lab 4: App of Apps Pattern](#lab-4-app-of-apps-pattern)
- [Lab 5: Helm Chart Deployments](#lab-5-helm-chart-deployments)
- [Lab 6: Kustomize Overlays (Dev vs Prod)](#lab-6-kustomize-overlays-dev-vs-prod)
- [Lab 7: Projects and RBAC](#lab-7-projects-and-rbac)
- [Concept Reference](#concept-reference)
- [Cleanup](#cleanup)
- [Additional Resources](#additional-resources)

> **Tip:** Each lab ends with a "Further Reading" section linking to official docs and guides. Use these to dig deeper into anything that catches your interest.

---

## Background: What Is Argo CD?

Argo CD is a **declarative, GitOps continuous delivery** tool for Kubernetes. Instead of running `kubectl apply` manually or building custom deployment scripts, you point Argo CD at a Git repository and it continuously reconciles the cluster state to match what's in Git.

### The GitOps Model

```
       YOU                    GIT                    ARGO CD               CLUSTER
    push code ──→    repo updated      ──→    detects drift     ──→    syncs resources
                     (source of truth)        (polls every 3min)       (kubectl apply)
```

The key principle: **Git is the single source of truth.** You never run `kubectl apply` directly in production. Instead, you commit manifests to Git, and Argo CD deploys them. This gives you:

- **Audit trail** -- every deployment is a Git commit
- **Rollback** -- revert a deployment by reverting a commit
- **Drift detection** -- Argo CD alerts you when the cluster doesn't match Git
- **Self-healing** -- optionally auto-fix manual changes to the cluster

### How It Differs from Tekton

Tekton and Argo CD solve **different halves** of CI/CD:

| | Tekton | Argo CD |
|---|---|---|
| **What** | CI/CD **pipelines** (build, test, package) | **Continuous delivery** (deploy to Kubernetes) |
| **Model** | Imperative: "run these steps in order" | Declarative: "make the cluster match this Git state" |
| **Trigger** | PipelineRun (explicit) | Git polling or webhook (continuous) |
| **Output** | Build artifacts (binaries, images) | Running workloads in the cluster |
| **Analogy** | The factory (builds the thing) | The shipping dock (delivers the thing) |

In a full CI/CD system, Tekton builds your container image and pushes it to a registry, then Argo CD deploys that image to the cluster by syncing the updated manifest from Git.

### Core Concepts

| Concept | What It Is |
|---------|-----------|
| **Application** | The central Argo CD resource. Points to a Git repo path and a cluster destination. |
| **Sync** | The act of applying the Git manifests to the cluster. |
| **Sync Status** | `Synced` (cluster matches Git) or `OutOfSync` (cluster drifted from Git). |
| **Health Status** | `Healthy`, `Progressing`, `Degraded`, or `Missing`. Reflects the actual workload state. |
| **Sync Policy** | Manual (you click sync) or Automated (Argo CD syncs on drift). |
| **Self-Heal** | Auto-revert manual `kubectl` changes back to the Git state. |
| **Prune** | Auto-delete resources that were removed from Git. |
| **Project** | A grouping mechanism with RBAC: restricts which repos, clusters, and namespaces an Application can use. |

### Further Reading

- [Argo CD Core Concepts](https://argo-cd.readthedocs.io/en/stable/core_concepts/)
- [GitOps Principles (OpenGitOps)](https://opengitops.dev/)
- [Argo CD vs Flux: A Comparison](https://www.cncf.io/blog/2023/07/19/argo-cd-and-flux-a-comparison/)

---

## Setup

### Prerequisites

You need a running Kind cluster. If you followed the Terraform setup from the root README:

```bash
cd ../../terraform
terraform apply
```

Or create a simple cluster:

```bash
kind create cluster --name dev
```

### Install the Argo CD CLI

```bash
brew install argocd
```

### Install Argo CD on the Cluster

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Wait for all pods to be ready:

```bash
kubectl -n argocd rollout status deployment argocd-server
kubectl -n argocd rollout status deployment argocd-repo-server
kubectl -n argocd rollout status deployment argocd-applicationset-controller
```

### Access the Argo CD UI

**Option A: Port-forward (simplest)**

```bash
kubectl port-forward svc/argocd-server -n argocd 8443:443
```

Then open [https://localhost:8443](https://localhost:8443) in your browser (accept the self-signed certificate warning).

**Option B: NodePort (persistent access)**

```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"port": 443, "nodePort": 30443}]}}'
```

### Get the Admin Password

Argo CD generates a random admin password on install, stored in a Kubernetes Secret:

```bash
argocd admin initial-password -n argocd
```

The username is `admin`. Change the password after your first login:

```bash
argocd login localhost:8443 --insecure
argocd account update-password
```

### Verify the Installation

```bash
# Check Argo CD pods
kubectl get pods -n argocd

# Check Argo CD version
argocd version

# List applications (should be empty)
argocd app list
```

You should see pods for `argocd-server`, `argocd-repo-server`, `argocd-application-controller`, `argocd-applicationset-controller`, `argocd-redis`, and `argocd-dex-server`.

### Further Reading

- [Argo CD Getting Started Guide](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [Argo CD Installation Methods](https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/)
- [Argo CD CLI Reference](https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd/)

---

## Lab 1: Your First Application

**Concepts:** Application resource, sync, health status, manual sync

This lab deploys Argo CD's canonical example app -- a simple guestbook. You'll create an Application resource that tells Argo CD "watch this Git repo path and deploy it to this namespace."

### What You're Deploying

The [argocd-example-apps](https://github.com/argoproj/argocd-example-apps) repo contains a `guestbook/` directory with a Deployment and Service. Argo CD will clone this repo, read the YAML, and apply it to your cluster.

### Create the Application

**Option A: Declarative (YAML)**

```bash
kubectl apply -f 01-guestbook-app.yaml
```

**Option B: CLI**

```bash
argocd app create guestbook \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default
```

**Option C: UI**

1. Open the Argo CD dashboard
2. Click **+ New App**
3. Fill in: Name=`guestbook`, Project=`default`, Repo URL=`https://github.com/argoproj/argocd-example-apps.git`, Path=`guestbook`, Cluster=`https://kubernetes.default.svc`, Namespace=`default`
4. Click **Create**

### Observe the Application

```bash
# List applications
argocd app list

# Get detailed status
argocd app get guestbook
```

The application should show `OutOfSync` -- Argo CD knows what Git says but hasn't applied it yet. This is the **manual sync** model: Argo CD detects drift but waits for you to approve.

### Sync (Deploy) the Application

```bash
argocd app sync guestbook
```

Or click **Sync** in the UI. Watch the resources appear:

```bash
kubectl get all -n default -l app=guestbook-ui
```

### View the Guestbook App

The guestbook UI runs on port 80 inside the cluster. Port-forward to access it locally:

```bash
kubectl port-forward svc/guestbook-ui 8080:80
```

Then open [http://localhost:8080](http://localhost:8080) in your browser. You should see a simple guestbook form where you can submit messages.

Press `Ctrl+C` to stop the port-forward when you're done.

### Explore the Argo CD UI

Open the Argo CD dashboard and click the `guestbook` application. You'll see:

- **Resource tree** -- a visual graph of the Deployment → ReplicaSet → Pod hierarchy
- **Sync status** -- green checkmark when Synced
- **Health status** -- hearts showing Healthy/Progressing/Degraded
- **Diff view** -- what would change on the next sync
- **History** -- past sync operations with timestamps

### Key Takeaways

- An **Application** is just a pointer: "watch this Git path, deploy to this destination"
- `OutOfSync` means Git and the cluster differ -- it's informational, not an error
- Manual sync gives you a review step before deployment
- The UI provides a real-time resource tree that's far richer than `kubectl get`

### Further Reading

- [Argo CD Application Specification](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#applications)
- [Tracking Strategies (targetRevision)](https://argo-cd.readthedocs.io/en/stable/user-guide/tracking_strategies/)
- [Sync Options Reference](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)

---

## Lab 2: Deploying Your Own Manifests

**Concepts:** Using your own repo, CreateNamespace sync option, editing manifests and re-syncing

Lab 1 used Argo CD's example repo. This lab deploys manifests from **this** repository, so you can edit them and see Argo CD pick up the changes.

### The Manifests

This lab includes a local guestbook app in `apps/guestbook/`:

```
apps/guestbook/
├── deployment.yaml    # guestbook-ui Deployment
└── service.yaml       # NodePort Service on port 31080
```

### Create the Application

```bash
kubectl apply -f 02-guestbook-local-app.yaml
```

This Application points to your fork of this repo at `src/research/argocd/apps/guestbook`.

> **Note:** The `CreateNamespace=true` sync option tells Argo CD to create the `guestbook` namespace if it doesn't exist. Without this, syncing to a non-existent namespace would fail.

### Sync and Verify

```bash
argocd app sync guestbook-local

kubectl get all -n guestbook
```

### Experiment: Edit and Re-Sync

1. Change the replica count in `apps/guestbook/deployment.yaml` from `1` to `3`
2. Commit and push to your repo
3. Wait ~3 minutes for Argo CD to detect the change, or force a refresh:

```bash
argocd app get guestbook-local --refresh
```

4. The app should show `OutOfSync`. Sync it:

```bash
argocd app sync guestbook-local
```

5. Verify:

```bash
kubectl get pods -n guestbook
```

You should see 3 pods now. This is the GitOps workflow: change Git, Argo CD detects drift, you sync to apply.

### Key Takeaways

- Argo CD works with **any** Git repo, not just special repos
- `CreateNamespace=true` is essential for deploying to new namespaces
- The poll interval is ~3 minutes by default; use `--refresh` or webhooks for faster detection
- The GitOps workflow: edit manifests → commit → push → Argo CD detects → sync → deployed

### Further Reading

- [Git Webhook Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/webhook/) -- Eliminate the 3-minute polling delay
- [Private Repository Access](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/) -- Connect to private Git repos and registries
- [Directory-type Applications](https://argo-cd.readthedocs.io/en/stable/user-guide/directory/)

---

## Lab 3: Auto-Sync and Self-Healing

**Concepts:** Automated sync policy, self-healing, pruning, drift detection

Labs 1 and 2 used manual sync -- you had to explicitly trigger deployment. This lab enables **automated sync**, where Argo CD deploys changes the moment it detects drift between Git and the cluster.

### What Changes

The key addition in `03-autosync-app.yaml`:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

| Setting | What It Does |
|---------|-------------|
| `automated` | Argo CD syncs automatically when it detects drift |
| `prune: true` | If you delete a manifest from Git, Argo CD deletes the resource from the cluster |
| `selfHeal: true` | If someone runs `kubectl edit` to change a resource, Argo CD reverts it to match Git |

### Apply the Application

```bash
kubectl apply -f 03-autosync-app.yaml
```

Because auto-sync is enabled, Argo CD will immediately start syncing -- no manual trigger needed.

```bash
# Watch it sync automatically
argocd app get guestbook-autosync

# See the deployed resources
kubectl get all -n autosync-demo
```

### Experiment: Self-Healing in Action

Try manually changing the deployment:

```bash
kubectl scale deployment guestbook-ui -n autosync-demo --replicas=5
```

Watch what happens:

```bash
kubectl get pods -n autosync-demo -w
```

Within seconds, Argo CD detects the drift and scales it back to 1 (the value in Git). You'll see pods terminating as self-heal kicks in.

Check the Argo CD history to see the auto-heal event:

```bash
argocd app history guestbook-autosync
```

### Experiment: Pruning in Action

If you were to remove `service.yaml` from the guestbook directory in Git and push, Argo CD would delete the Service from the cluster (because `prune: true`). Without pruning, removed manifests become orphans in the cluster.

### When to Use Auto-Sync

| Environment | Recommendation |
|-------------|---------------|
| **Development** | Auto-sync + self-heal + prune. Fast iteration, no manual steps. |
| **Staging** | Auto-sync + self-heal. Maybe prune cautiously. |
| **Production** | Manual sync (or auto-sync with [sync windows](https://argo-cd.readthedocs.io/en/stable/user-guide/sync_windows/)). Human review before deploy. |

### Key Takeaways

- Auto-sync eliminates the manual "sync" step -- changes deploy as soon as they're pushed
- Self-healing prevents configuration drift from manual `kubectl` changes
- Pruning keeps the cluster clean by removing resources deleted from Git
- Production environments typically use manual sync or sync windows for safety

### Further Reading

- [Automated Sync Policy](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)
- [Sync Windows](https://argo-cd.readthedocs.io/en/stable/user-guide/sync_windows/) -- Restrict when auto-sync can happen (maintenance windows)
- [Resource Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/) -- Run Jobs before/after sync (migrations, smoke tests)

---

## Lab 4: App of Apps Pattern

**Concepts:** App of Apps, managing multiple applications declaratively, bootstrapping

So far, each lab has created one Application at a time. In a real environment, you might have dozens of applications. The **App of Apps** pattern solves this: you create one "parent" Application that points to a directory of Application YAMLs. Argo CD deploys the parent, which creates all the child Applications, which then deploy their own workloads.

### The Pattern

```
Parent Application (points to apps/ directory)
├── child-app-1.yaml    →  deploys workload A
├── child-app-2.yaml    →  deploys workload B
└── child-app-3.yaml    →  deploys workload C
```

One `kubectl apply` creates the parent. Argo CD does the rest.

### Try It

The Argo CD example-apps repo has an `apps/` directory containing several Application definitions:

```bash
kubectl apply -f 04-app-of-apps.yaml
```

Then sync the parent:

```bash
argocd app sync lab-apps
```

Watch child applications appear:

```bash
argocd app list
```

You should see multiple applications created automatically. Each one is a separate Argo CD Application that manages its own workload.

### When to Use App of Apps

- **Cluster bootstrapping** -- one parent app deploys all infrastructure (monitoring, ingress, cert-manager, etc.)
- **Multi-team environments** -- each team has an Application YAML in a shared repo
- **Environment promotion** -- a parent per environment (dev, staging, prod) pointing to different overlays

### App of Apps vs ApplicationSets

Argo CD also has **ApplicationSets**, a newer feature that generates Applications from templates:

| Feature | App of Apps | ApplicationSet |
|---------|------------|----------------|
| Defined as | Directory of Application YAMLs | Template with generators (Git, list, cluster, etc.) |
| Flexibility | Full control per app | DRY templates for many similar apps |
| Complexity | Simple (just YAML files) | More powerful but more abstract |
| Use case | Heterogeneous apps | Many similar apps across clusters/environments |

### Key Takeaways

- App of Apps is a bootstrapping pattern: one parent deploys many children
- Each child Application is independently synced, health-checked, and rollback-able
- In production, the "apps" directory is often the first thing Argo CD deploys after installation
- ApplicationSets are the templated evolution of this pattern

### Further Reading

- [App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/#app-of-apps-pattern)
- [ApplicationSet Controller](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Cluster Bootstrapping](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)

---

## Lab 5: Helm Chart Deployments

**Concepts:** Helm source type, value overrides, parameter injection

Argo CD natively understands Helm charts. Instead of running `helm install` manually, you point an Application at a chart and Argo CD renders the templates, applies them, and keeps them in sync with Git.

### How Argo CD Handles Helm

```
Git Repo
└── helm-guestbook/
    ├── Chart.yaml          # Chart metadata
    ├── values.yaml         # Default values
    └── templates/
        ├── deployment.yaml # {{ .Values.replicaCount }}
        └── service.yaml    # {{ .Values.service.type }}
```

Argo CD runs `helm template` internally (it never runs `helm install`). This means:
- No Tiller, no Helm state in the cluster
- The rendered manifests are what Argo CD tracks and diffs
- You can override values in the Application spec

### Apply the Helm Application

```bash
kubectl apply -f 05-helm-app.yaml
```

Look at what makes this different from previous labs:

```yaml
source:
  path: helm-guestbook
  helm:
    valueFiles:
      - values.yaml
    parameters:
      - name: replicaCount
        value: "2"
      - name: service.type
        value: NodePort
```

The `helm.parameters` field overrides specific values without editing `values.yaml`.

### Sync and Verify

```bash
argocd app sync helm-guestbook

kubectl get all -n helm-demo
```

You should see 2 replicas (overridden from the default of 1) and a NodePort service.

### Experiment: Change Values via CLI

```bash
argocd app set helm-guestbook --helm-set replicaCount=4
argocd app sync helm-guestbook
kubectl get pods -n helm-demo
```

Now 4 replicas. The override is stored in the Application spec, not in Git -- so this is a quick way to test, but for GitOps purity you'd commit the change to the Application YAML.

### Helm from OCI Registries

Argo CD also supports Helm charts from OCI registries (not just Git repos):

```yaml
source:
  repoURL: registry-1.docker.io/bitnamicharts
  chart: nginx
  targetRevision: 15.0.0
  helm:
    releaseName: my-nginx
```

### Key Takeaways

- Argo CD renders Helm charts with `helm template` -- no Helm release state in the cluster
- Value overrides can come from `valueFiles`, `parameters`, or `values` (inline YAML)
- Parameter overrides in the Application spec are useful for per-environment tuning
- OCI registries work too -- not just Git repos

### Further Reading

- [Argo CD Helm Guide](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)
- [Helm Value File Overrides](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/#values-files)
- [OCI Helm Charts in Argo CD](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/#helm-oci-based-chart-repository)

---

## Lab 6: Kustomize Overlays (Dev vs Prod)

**Concepts:** Kustomize source type, overlays, environment-specific configuration, same base different config

Kustomize lets you define a **base** set of manifests and then create **overlays** that patch them for different environments. Argo CD detects Kustomize directories automatically (by the presence of `kustomization.yaml`) and renders them before applying.

### The Structure

This lab includes a complete Kustomize setup in `apps/kustomize-guestbook/`:

```
apps/kustomize-guestbook/
├── base/
│   ├── kustomization.yaml    # Lists resources
│   ├── deployment.yaml       # 1 replica, minimal resources
│   └── service.yaml          # ClusterIP
└── overlays/
    ├── dev/
    │   └── kustomization.yaml   # namespace: dev, namePrefix: dev-, 1 replica
    └── prod/
        └── kustomization.yaml   # namespace: prod, namePrefix: prod-, 3 replicas, more resources
```

The **base** defines the common structure. Each **overlay** patches it:

| Property | Base | Dev Overlay | Prod Overlay |
|----------|------|-------------|-------------|
| Namespace | (none) | `dev` | `prod` |
| Name prefix | (none) | `dev-` | `prod-` |
| Replicas | 1 | 1 | 3 |
| CPU request | 50m | 50m (inherited) | 100m |
| Memory request | 64Mi | 64Mi (inherited) | 128Mi |

### Deploy Both Environments

```bash
# Dev: auto-sync enabled (fast iteration)
kubectl apply -f 06-kustomize-dev-app.yaml

# Prod: manual sync (deliberate deployment)
kubectl apply -f 07-kustomize-prod-app.yaml
```

Sync both:

```bash
argocd app sync guestbook-dev
argocd app sync guestbook-prod
```

### Verify the Differences

```bash
# Dev: 1 replica, dev- prefix
kubectl get all -n dev

# Prod: 3 replicas, prod- prefix, higher resource limits
kubectl get all -n prod
kubectl get deployment -n prod -o jsonpath='{.items[0].spec.template.spec.containers[0].resources}'
```

### How Argo CD Detects Kustomize

When the `path` in an Application source contains a `kustomization.yaml`, Argo CD automatically uses Kustomize to render the manifests. You don't need to specify any special configuration -- it just works.

You can verify what Argo CD will apply:

```bash
argocd app manifests guestbook-dev
argocd app manifests guestbook-prod
```

### The Real-World Pattern

In production GitOps, the pattern looks like:

```
infrastructure-repo/
├── apps/
│   ├── service-a/
│   │   ├── base/
│   │   └── overlays/
│   │       ├── dev/
│   │       ├── staging/
│   │       └── prod/
│   └── service-b/
│       └── ...
└── argocd-apps/
    ├── service-a-dev.yaml        # Application → apps/service-a/overlays/dev
    ├── service-a-staging.yaml    # Application → apps/service-a/overlays/staging
    └── service-a-prod.yaml       # Application → apps/service-a/overlays/prod
```

Each environment gets its own Application pointing to the correct overlay. Promotion is just updating `targetRevision` or merging to a branch.

### Key Takeaways

- Kustomize overlays let you manage multiple environments from a single base
- Argo CD auto-detects Kustomize directories (looks for `kustomization.yaml`)
- Dev gets auto-sync for fast iteration; prod gets manual sync for safety
- The name prefix (`dev-`, `prod-`) prevents resource name collisions if deployed to the same cluster

### Further Reading

- [Argo CD Kustomize Guide](https://argo-cd.readthedocs.io/en/stable/user-guide/kustomize/)
- [Kustomize Official Docs](https://kustomize.io/)
- [Managing Environments with Kustomize](https://kubectl.docs.kubernetes.io/guides/introduction/kustomize/)

---

## Lab 7: Projects and RBAC

**Concepts:** AppProject, source restrictions, destination restrictions, namespace-scoped RBAC

The `default` project has no restrictions -- any Application can deploy to any namespace from any repo. In a real environment, you need **guardrails**. Argo CD Projects provide them.

### What an AppProject Controls

| Restriction | What It Limits |
|-------------|---------------|
| `sourceRepos` | Which Git repos Applications in this project can pull from |
| `destinations` | Which cluster + namespace combinations Applications can deploy to |
| `clusterResourceWhitelist` | Which cluster-scoped resources (Namespaces, ClusterRoles, etc.) are allowed |
| `namespaceResourceWhitelist` | Which namespaced resources (Deployments, Services, etc.) are allowed |

### Create a Restricted Project

```bash
kubectl apply -f 08-project.yaml
```

This creates a `team-alpha` project that:
- Can only pull from the example-apps and k8s repos
- Can only deploy to the `team-alpha` namespace
- Can only create Deployments, Services, ConfigMaps, and Secrets (no RBAC resources, no PVCs, etc.)

### Deploy an App in the Restricted Project

```bash
kubectl apply -f 09-project-app.yaml
argocd app sync team-alpha-guestbook
```

```bash
kubectl get all -n team-alpha
```

### Experiment: Test the Guardrails

Try creating an Application that violates the project restrictions:

```bash
argocd app create forbidden-app \
  --project team-alpha \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace kube-system
```

This should fail with a permissions error -- `team-alpha` can only deploy to the `team-alpha` namespace.

### Project Roles and JWT Tokens

Projects can also define roles with their own JWT tokens, enabling fine-grained automation:

```yaml
spec:
  roles:
    - name: deployer
      description: CI system role
      policies:
        - p, proj:team-alpha:deployer, applications, sync, team-alpha/*, allow
        - p, proj:team-alpha:deployer, applications, get, team-alpha/*, allow
```

This creates a `deployer` role that can sync and view applications in the project but can't create, delete, or modify them. Useful for CI systems that trigger deployments.

### Key Takeaways

- Projects are Argo CD's RBAC mechanism for multi-team clusters
- `sourceRepos` prevents teams from deploying arbitrary code
- `destinations` prevents teams from deploying to namespaces they don't own
- Resource whitelists prevent privilege escalation (e.g., teams creating ClusterRoles)
- Project roles + JWT tokens enable scoped automation without sharing the admin password

### Further Reading

- [Projects](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/)
- [RBAC Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)
- [Project Roles and Tokens](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/#project-roles)

---

## Concept Reference

### Application Lifecycle

```
1. Create Application       kubectl apply -f app.yaml
2. OutOfSync detected       Argo CD compares Git ↔ Cluster
3. Sync (manual or auto)    Argo CD runs kubectl apply
4. Synced + Healthy          Cluster matches Git, workloads running
5. Drift detected            Someone runs kubectl edit, or Git changes
6. Back to step 2            Cycle repeats
```

### Sync Strategies

| Strategy | `syncPolicy` | Behavior |
|----------|-------------|----------|
| Manual | (empty) | You trigger every sync |
| Auto-sync | `automated: {}` | Syncs when Git changes |
| Auto-sync + prune | `automated: { prune: true }` | Also deletes removed resources |
| Auto-sync + self-heal | `automated: { selfHeal: true }` | Also reverts manual kubectl changes |
| Full auto | `automated: { prune: true, selfHeal: true }` | Complete GitOps: Git is the absolute truth |

### Source Types

Argo CD auto-detects the source type based on the repo contents:

| Type | Detection | What Argo CD Does |
|------|-----------|------------------|
| **Directory** | Plain YAML files | `kubectl apply` on all YAML files in the path |
| **Helm** | `Chart.yaml` present | `helm template` with optional value overrides |
| **Kustomize** | `kustomization.yaml` present | `kustomize build` then apply |
| **Jsonnet** | `.jsonnet` files | Render Jsonnet, then apply |
| **Plugin** | Custom CMP config | Run a custom tool to generate manifests |

### Health Assessment

Argo CD checks health beyond just "does the resource exist":

| Resource | Healthy When |
|----------|-------------|
| Deployment | All replicas available, no rollout in progress |
| StatefulSet | All replicas ready |
| DaemonSet | Desired count equals available |
| Service | Endpoints exist |
| Ingress | Load balancer IP assigned (cloud) |
| Pod | Running and passing readiness probes |
| PVC | Bound |
| Custom Resource | Via [custom health checks](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/) (Lua scripts) |

---

## Cleanup

### Remove All Lab Applications

```bash
# Delete all applications created in these labs
argocd app delete guestbook --yes
argocd app delete guestbook-local --yes
argocd app delete guestbook-autosync --yes
argocd app delete lab-apps --yes
argocd app delete helm-guestbook --yes
argocd app delete guestbook-dev --yes
argocd app delete guestbook-prod --yes
argocd app delete team-alpha-guestbook --yes

# Delete the project
kubectl delete appproject team-alpha -n argocd

# Delete lab namespaces
kubectl delete namespace guestbook autosync-demo helm-demo dev prod team-alpha --ignore-not-found
```

### Remove Argo CD Entirely

```bash
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl delete namespace argocd
```

### Delete the Kind Cluster

```bash
kind delete cluster --name dev
```

---

## Additional Resources

### Official Documentation

- [Argo CD Documentation](https://argo-cd.readthedocs.io/en/stable/)
- [Argo CD Operator Manual](https://argo-cd.readthedocs.io/en/stable/operator-manual/)
- [Argo CD User Guide](https://argo-cd.readthedocs.io/en/stable/user-guide/)

### Architecture and Internals

- [Argo CD Architecture Overview](https://argo-cd.readthedocs.io/en/stable/operator-manual/architecture/)
- [High Availability Setup](https://argo-cd.readthedocs.io/en/stable/operator-manual/high_availability/)
- [Disaster Recovery](https://argo-cd.readthedocs.io/en/stable/operator-manual/disaster_recovery/)

### Advanced Patterns

- [ApplicationSets](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/) -- Generate Applications from templates
- [Sync Waves and Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/) -- Control deployment ordering
- [Config Management Plugins](https://argo-cd.readthedocs.io/en/stable/operator-manual/config-management-plugins/) -- Extend Argo CD with custom manifest generators
- [Notifications](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/) -- Slack, email, webhook alerts on sync events
- [Image Updater](https://argocd-image-updater.readthedocs.io/) -- Automatically update container image tags

### Community

- [Argo CD GitHub](https://github.com/argoproj/argo-cd)
- [Argo Project Blog](https://blog.argoproj.io/)
- [CNCF Argo Project](https://www.cncf.io/projects/argo/)
- [Awesome Argo](https://github.com/akuity/awesome-argo) -- Curated list of Argo resources
