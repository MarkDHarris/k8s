# Tekton Pipelines -- Hands-On Lab

A progressive, hands-on lab series that takes you from zero to production-expert level with [Tekton](https://tekton.dev/) CI/CD pipelines on a local Kind cluster. Labs 1-5 cover foundations (Tasks, Pipelines, Results, Workspaces). Labs 6-14 cover advanced and production patterns (when expressions, finally blocks, retries, sidecars, matrix, RBAC, bundle resolvers, Kustomize). The Capstone project builds a real cross-compilation Rust pipeline that ties everything together. The Deep Dive sections decode real production pipelines and cover organizational patterns like Prow, Slack notifications, approval workflows, and resource signing.

---

## Table of Contents

### Foundations (Labs 1-5)

- [Background: What Is Tekton?](#background-what-is-tekton)
- [Setup](#setup)
- [Lab 1: Your First Task](#lab-1-your-first-task)
- [Lab 2: Parameters and Multi-Step Tasks](#lab-2-parameters-and-multi-step-tasks)
- [Lab 3: Results (Passing Data Between Tasks)](#lab-3-results-passing-data-between-tasks)
- [Lab 4: Workspaces (Shared Storage)](#lab-4-workspaces-shared-storage)
- [Lab 5: Build Pipeline (Putting It All Together)](#lab-5-build-pipeline-putting-it-all-together)

### Advanced Concepts (Labs 6-14)

- [Lab 6: When Expressions (Conditional Execution)](#lab-6-when-expressions-conditional-execution)
- [Lab 7: Finally Blocks (Always-Run Tasks)](#lab-7-finally-blocks-always-run-tasks)
- [Lab 8: Retries and Timeouts (Resilience)](#lab-8-retries-and-timeouts-resilience)
- [Lab 9: Sidecars (Auxiliary Containers)](#lab-9-sidecars-auxiliary-containers)
- [Lab 10: Matrix (Fan-Out Parallelism)](#lab-10-matrix-fan-out-parallelism)
- [Lab 11: Service Accounts, RBAC, and Secrets](#lab-11-service-accounts-rbac-and-secrets)
- [Lab 12: Advanced Workspaces (SubPath and Inline Tasks)](#lab-12-advanced-workspaces-subpath-and-inline-tasks)
- [Lab 13: Bundle Resolvers and Task Catalogs](#lab-13-bundle-resolvers-and-task-catalogs)
- [Lab 14: Production Operations (CronJobs, Cleanup, Kustomize)](#lab-14-production-operations-cronjobs-cleanup-kustomize)

### Capstone Project

- [Capstone: Real-World Rust Build (rto-rust)](#capstone-real-world-rust-build-rto-rust)

### Production Deep Dive

- [Decoding a Production Pipeline](#decoding-a-production-pipeline)
- [Production Patterns Deep Dive](#production-patterns-deep-dive)
- [Concept Reference](#concept-reference)
- [Cleanup](#cleanup)
- [Additional Resources](#additional-resources)

> **Tip:** Each lab ends with a "Further Reading" section linking to official docs, blog posts, and guides for the concepts just covered. Use these to dig deeper into anything that catches your interest.

---

## Background: What Is Tekton?

Tekton is a Kubernetes-native CI/CD framework. Instead of configuring pipelines in a web UI (Jenkins) or YAML that lives outside the cluster (GitHub Actions), Tekton pipelines are **Kubernetes resources** -- you define them with YAML and apply them with `kubectl`, just like Deployments and Services.

### Why Kubernetes-Native Matters

| Traditional CI/CD | Tekton |
|-------------------|--------|
| Pipeline runs on a CI server (Jenkins, etc.) | Pipeline runs as Pods in your cluster |
| Config lives outside the cluster | Config is a Kubernetes resource (GitOps friendly) |
| Scaling means bigger CI servers | Scaling means more Pods (Kubernetes handles it) |
| Different auth model than your apps | Same RBAC, ServiceAccounts, and secrets as your apps |

### The Four Core Resources

```
DEFINITIONS (reusable templates)       EXECUTIONS (one-time runs)
──────────────────────────────         ──────────────────────────
Task ──────────────────────────→ TaskRun
  (a sequence of steps)                  (runs a single Task)

Pipeline ──────────────────────→ PipelineRun
  (a DAG of Tasks)                       (runs an entire Pipeline)
```

- **Task** -- A reusable unit of work. Contains one or more **Steps**, each running in its own container. All steps in a Task share a Pod.
- **TaskRun** -- A single execution of a Task. Creates a Pod, runs the steps, and records the result.
- **Pipeline** -- A directed acyclic graph (DAG) of Tasks. Tasks can run in parallel or sequentially.
- **PipelineRun** -- A single execution of a Pipeline. Creates one TaskRun per Task.

### How It Maps to Kubernetes

```
PipelineRun
 └── TaskRun (one per task in the pipeline)
      └── Pod (one per TaskRun)
           ├── Step 1 (init container or regular container)
           ├── Step 2
           └── Step 3
```

Every TaskRun becomes a Pod. Every Step becomes a container in that Pod. Workspaces become volume mounts. Results become files on a shared volume.

### Further Reading

- [Tekton Overview](https://tekton.dev/docs/concepts/overview/) -- Official introduction to Tekton's architecture and design philosophy
- [Tekton vs Jenkins: What's Better for CI/CD on OpenShift?](https://redhat.com/en/blog/tekton-vs-jenkins-whats-better-cicd-pipelines-red-hat-openshift) -- Red Hat's comparison of Tekton and Jenkins, good for understanding why Kubernetes-native CI/CD matters
- [CI/CD Tools Comparison: GitHub Actions, Jenkins, Tekton, and Argo CD](https://jiminbyun.medium.com/ci-cd-tools-comparison-github-actions-jenkins-tekton-and-argo-cd-673d205f9fa8) -- Broader landscape comparison to see where Tekton fits
- [Is Tekton Still Alive? Comparing Tekton with Argo Workflows and Jenkins](https://mkdev.me/posts/is-tekton-still-alive-comparing-tekton-pipelines-with-argo-workflows-argocd-and-jenkins) -- Honest assessment of Tekton's strengths and trade-offs vs alternatives

---

## Setup

### Prerequisites

| Tool | Installation |
|------|-------------|
| **A running Kind cluster** | Use [terraform/](../../terraform/) (`terraform apply`) or [apps/nginx/](../../apps/nginx/) (`kind create cluster --config cluster.yaml`) |
| **kubectl** | `brew install kubectl` |
| **tkn** (Tekton CLI) | `brew install tektoncd-cli` |

### Install Tekton Pipelines

```bash
# Install the Tekton Pipelines controller and webhook
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Wait for the components to be ready
kubectl wait --for=condition=Ready pods --all -n tekton-pipelines --timeout=120s

# Verify
kubectl get pods -n tekton-pipelines
```

You should see `tekton-pipelines-controller` and `tekton-pipelines-webhook` both Running.

### Install Tekton Dashboard (Optional but Recommended)

The dashboard gives you a visual view of pipeline runs, logs, and status.

```bash
# Install the dashboard
kubectl apply --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml

# Wait for it
kubectl wait --for=condition=Ready pods --all -n tekton-pipelines --timeout=120s

# Access it via port-forward
kubectl port-forward -n tekton-pipelines svc/tekton-dashboard 9097:9097
```

Then open http://localhost:9097 in your browser. Keep this running in a separate terminal.

### Further Reading

- [Install Tekton Pipelines](https://tekton.dev/docs/pipelines/install/) -- Official installation guide with advanced options (custom namespaces, image mirrors, air-gapped installs)
- [Tekton CLI (tkn) Reference](https://tekton.dev/docs/cli/) -- Full command reference for the `tkn` CLI
- [Tekton Dashboard Documentation](https://tekton.dev/docs/dashboard/) -- Dashboard features, configuration, and RBAC setup

---

## Lab 1: Your First Task

**Concepts:** Task, TaskRun, Steps

A Task is the smallest unit of work in Tekton. Let's create one that prints a greeting.

### Apply the Task Definition

```bash
kubectl apply -f 01-hello-task.yaml
```

This registers the Task as a reusable template in Kubernetes -- nothing runs yet. Think of it like creating a Deployment YAML without replicas: it describes *what* to do, not *when*.

### Run the Task

```bash
kubectl apply -f 02-hello-taskrun.yaml
```

This creates a TaskRun, which tells Tekton "run the `hello` Task now." Tekton creates a Pod, executes the step, and records the result.

### Observe

```bash
# Watch the TaskRun status
tkn taskrun describe hello-run

# View the logs
tkn taskrun logs hello-run

# See the Pod that was created
kubectl get pods
```

### What Just Happened

```
You applied 02-hello-taskrun.yaml
  → Tekton controller saw the TaskRun
    → Created a Pod with one container (the "say-hello" step)
      → Container ran the script
        → TaskRun status updated to Succeeded (or Failed)
```

### Key Takeaway

A **Task** is a reusable definition. A **TaskRun** is a one-time execution. The same Task can be run many times with different TaskRuns.

### Further Reading

- [Tekton Tasks](https://tekton.dev/docs/pipelines/tasks/) -- Complete reference for Task definition, including step ordering, resource limits, sidecars, and step templates
- [Tekton TaskRuns](https://tekton.dev/docs/pipelines/taskruns/) -- How TaskRuns work, status conditions, timeouts, and cancellation
- [Getting Started with Pipelines](https://tekton.dev/docs/getting-started/pipelines/) -- Tekton's own getting-started tutorial (good second perspective on the same concepts)

---

## Lab 2: Parameters and Multi-Step Tasks

**Concepts:** Params, multiple Steps, `$(params.name)` syntax

Parameters make Tasks reusable. Instead of hardcoding values, you declare inputs.

### Apply and Run

```bash
kubectl apply -f 03-param-task.yaml
kubectl apply -f 04-param-taskrun.yaml

# View logs (shows both steps)
tkn taskrun logs greeting-run
```

### Observe Multi-Step Behavior

```bash
# Describe shows each step's status independently
tkn taskrun describe greeting-run
```

You'll see two steps: `greet` and `context`. Both ran sequentially in the same Pod.

### Experiment

```bash
# Run the same task with different params (inline TaskRun)
kubectl create -f - <<EOF
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  generateName: greeting-custom-
spec:
  taskRef:
    name: greeting
  params:
    - name: person
      value: "Kind Cluster"
    - name: greeting
      value: "Greetings from"
EOF

# List all TaskRuns for the greeting task
tkn taskrun list
```

### Key Takeaways

- **Steps** run sequentially in the same Pod. They share the Pod's filesystem but each step is a separate container.
- **Params** are declared in the Task's `spec.params` and referenced with `$(params.name)`.
- **`generateName`** creates a unique name for each run (useful for re-running).

### Further Reading

- [Variable Substitutions](https://tekton.dev/docs/pipelines/variables/) -- Complete list of all `$(...)` variable substitutions available in Tasks and Pipelines
- [Step-by-Step: Setting Up a CI/CD Pipeline Using Tekton](https://hayorov.me/posts/tekton-cicd-pipeline-guide/) -- End-to-end walkthrough from a practitioner's perspective, covers real-world patterns
- [How to Get Started with Tekton Pipelines](https://oneuptime.com/blog/post/2026-01-26-tekton-pipelines-guide/view) -- Another step-by-step guide with practical examples

---

## Lab 3: Results (Passing Data Between Tasks)

**Concepts:** Results, `$(tasks.name.results.name)` syntax, Pipelines, runAfter

Results are how Tasks export small pieces of data (commit SHAs, version strings, status codes) for other Tasks to consume. This is the Tekton equivalent of output variables.

### Apply the Tasks and Pipeline

```bash
# Apply the two tasks (generate-name and display-result)
kubectl apply -f 05-result-tasks.yaml

# Apply the pipeline definition
kubectl apply -f 06-result-pipeline.yaml

# Start a run (use "create" not "apply" because generateName requires it)
kubectl create -f 06-result-pipelinerun.yaml
```

### Observe

```bash
# The PipelineRun name is auto-generated. Find it:
tkn pipelinerun list

# Describe the pipeline run (shows task ordering and results)
tkn pipelinerun describe <name-from-above>

# View logs for the entire pipeline (--last gets the most recent run)
tkn pipelinerun logs --last
```

### How Results Flow

```
┌────────────────────────────────────────────────────────────────┐
│  Pipeline: result-chain                                        │
│                                                                │
│  ┌──────────────┐  results.animal  ┌────────────────────────┐  │
│  │ generate     │ ──────────────→  │ display                │  │
│  │ (generate-   │                  │ (display-result)       │  │
│  │  name task)  │                  │ params.message =       │  │
│  │              │                  │   "The animal is: cat" │  │
│  └──────────────┘                  └────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

The `generate` task writes a random animal to `$(results.animal.path)`. The Pipeline wires it to the `display` task's `message` param via `$(tasks.generate.results.animal)`.

### Key Takeaways

- **Results** are small strings (max 4096 bytes) written to a special file path.
- Tasks in a Pipeline communicate through Results (small data) and Workspaces (large data/files).
- **`runAfter`** controls execution order. Without it, tasks run in parallel (if they have no data dependencies).
- Note: When a task references another task's result (e.g., `$(tasks.clone.results.commit-sha)`), Tekton automatically infers the ordering -- `runAfter` is only needed when there's no data dependency but you still need sequencing.

### Further Reading

- [Tekton Pipelines](https://tekton.dev/docs/pipelines/pipelines/) -- Full Pipeline reference: task ordering, `runAfter`, `when` expressions (conditional execution), and `finally` tasks
- [How to Configure Tekton PipelineRuns](https://oneuptime.com/blog/post/2026-02-02-tekton-pipelineruns/view) -- Deep dive into PipelineRun configuration, timeouts, and parameter passing
- [Using Results](https://tekton.dev/docs/pipelines/pipelines/#using-results) -- Official docs on result propagation between tasks, including size limits and array results

---

## Lab 4: Workspaces (Shared Storage)

**Concepts:** Workspaces, volumeClaimTemplate, PVC-backed storage, workspace mapping

Results are for small strings. **Workspaces** are for files -- source code, build artifacts, configuration. They're backed by Kubernetes volumes (PVCs, ConfigMaps, Secrets, or emptyDir).

### Apply the Tasks and Pipeline

```bash
# Apply the write-file and read-file tasks
kubectl apply -f 07-workspace-tasks.yaml

# Apply the pipeline definition
kubectl apply -f 08-workspace-pipeline.yaml

# Start a run (use "create" because it uses generateName)
kubectl create -f 08-workspace-pipelinerun.yaml
```

### Observe

```bash
tkn pipelinerun list
tkn pipelinerun logs --last

# See the PVC that was automatically created
kubectl get pvc
```

### How Workspaces Connect

This is one of the most important concepts for understanding production pipelines:

```
PIPELINE LEVEL                     TASK LEVEL
─────────────────                  ─────────────────

Pipeline.spec.workspaces:          Task.spec.workspaces:
  - name: shared-data                - name: output    ← write-file task
                                     - name: input     ← read-file task

PipelineRun.spec.workspaces:       Pipeline.spec.tasks[].workspaces:
  - name: shared-data                - name: output
    volumeClaimTemplate: ...            workspace: shared-data  ← mapping!
    (creates a real PVC)              - name: input
                                        workspace: shared-data  ← same PVC!
```

The key insight: **Tasks name their own workspaces independently** (`output`, `input`). The **Pipeline maps them** to a shared pipeline-level workspace (`shared-data`). The **PipelineRun provides the actual volume** (a PVC).

### The Three-Level Workspace Model

| Level | Declares | Provides |
|-------|----------|----------|
| **Task** | "I need a workspace called X" | Nothing -- it's abstract |
| **Pipeline** | "Map task workspace X to pipeline workspace Y" | Nothing -- still abstract |
| **PipelineRun** | Nothing new | The actual volume (PVC, emptyDir, etc.) |

This separation is what makes Tasks reusable. A `git-clone` Task doesn't care whether its `output` workspace is backed by a 1GB PVC or a 100GB PVC -- it just writes to the path.

### Experiment: Workspace SubPaths

Production pipelines often use **subPaths** to partition a single PVC:

```yaml
tasks:
  - name: clone-app
    workspaces:
      - name: output
        workspace: shared-data
        subPath: app-repo          # writes to /workspace/app-repo/

  - name: clone-tools
    workspaces:
      - name: output
        workspace: shared-data
        subPath: tools-repo        # writes to /workspace/tools-repo/
```

This is exactly how the production pipeline isolates multiple git repositories on a single volume.

### Key Takeaways

- **Workspaces** are the mechanism for sharing files between Tasks in a Pipeline.
- The naming is decoupled: Tasks, Pipelines, and PipelineRuns each have their own names for the same storage.
- **`volumeClaimTemplate`** creates a temporary PVC that is automatically cleaned up when the PipelineRun finishes.
- **`subPath`** lets multiple tasks use different directories on the same volume.

### Further Reading

- [Tekton Workspaces](https://tekton.dev/docs/pipelines/workspaces/) -- Complete workspace reference: all backing types, `subPath`, `readOnly` mode, and isolated workspaces
- [How to Use Tekton Workspaces](https://oneuptime.com/blog/post/2026-02-02-tekton-workspaces/view) -- Practical guide covering PVC, emptyDir, ConfigMap, and Secret-backed workspaces with examples
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) -- Understanding the PVC/PV model that underpins Tekton workspaces

---

## Lab 5: Build Pipeline (Putting It All Together)

**Concepts:** Multi-stage pipeline, parallel execution, combining results and workspaces

This lab builds a realistic pipeline that clones a Git repository, runs tests, generates a version, and produces a build report. It demonstrates the same patterns used in production pipelines.

### Apply Everything

```bash
# Apply all four tasks + the pipeline definition
kubectl apply -f 09-build-pipeline.yaml

# Start a pipeline run (use "create" because it uses generateName)
kubectl create -f 10-build-pipelinerun.yaml
```

### Observe the Execution

```bash
# Watch the pipeline run in real-time
tkn pipelinerun logs -f --last

# Or describe for a summary
tkn pipelinerun describe --last
```

### Pipeline Execution Graph

```
                  ┌─────────────┐
                  │    clone    │
                  │ (git-clone- │
                  │   simple)   │
                  └──────┬──────┘
                         │
              ┌──────────┼──────────┐
              │ results: │          │
              │ commit-sha          │
              ▼          │          ▼
     ┌────────────┐      │   ┌────────────┐
     │  version   │      │   │    test    │
     │ (generate- │      │   │ (run-tests)│
     │  version)  │      │   │            │
     └─────┬──────┘      │   └──────┬─────┘
           │             │          │
           │ results:    │          │ results:
           │ version     │          │ status
           │             │          │
           └──────┬──────┘──────────┘
                  ▼
           ┌────────────┐
           │   report   │
           │  (build-   │
           │   report)  │
           └────────────┘
```

Note: `version` depends on `clone` through a result reference (`$(tasks.clone.results.commit-sha)`), so Tekton runs it **after** clone finishes. `test` also runs after `clone` (explicit `runAfter`). Both `version` and `test` can run in **parallel** since they don't depend on each other. `report` waits for both.

### Where Are the Build Artifacts?

The cloned repository and test results live on the PVC that was created by the `volumeClaimTemplate`. Once the PipelineRun finishes, the PVC is cleaned up automatically -- so you need to retrieve artifacts **before** Tekton garbage-collects the run, or change the approach.

**Option 1: Inspect artifacts while the PVC still exists**

After the pipeline completes, the PVC lingers briefly. Find it and spin up a debug pod to browse the contents:

```bash
# Find the PVC created by the pipeline run
kubectl get pvc

# Launch a pod that mounts the PVC (replace <pvc-name> with the actual name)
kubectl run artifact-browser --rm -it \
  --image=alpine:3 \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "artifact-browser",
        "image": "alpine:3",
        "command": ["sh"],
        "stdin": true,
        "tty": true,
        "volumeMounts": [{
          "name": "workspace",
          "mountPath": "/workspace"
        }]
      }],
      "volumes": [{
        "name": "workspace",
        "persistentVolumeClaim": {
          "claimName": "<pvc-name>"
        }
      }]
    }
  }'

# Inside the pod:
ls /workspace/source/       # The cloned repo + test results
```

**Option 2: Use `kubectl cp` from a completed task pod**

If the last task's pod hasn't been deleted yet:

```bash
# Find the pod from the report task (most recent)
kubectl get pods -l tekton.dev/pipelineRun --sort-by=.metadata.creationTimestamp

# Copy files out (replace <pod-name>)
kubectl cp <pod-name>:/workspace/source/ ./lab5-artifacts/
```

**Option 3 (production pattern): Add an upload task**

In real pipelines, a final task uploads artifacts to external storage (S3, Artifactory, a container registry). The workspace is ephemeral -- it only lives for the duration of the pipeline run. Production pipelines never rely on the PVC for long-term storage.

### Key Takeaways

- Pipelines form a **DAG** (Directed Acyclic Graph). Tekton maximizes parallelism automatically.
- **Results** create implicit dependencies (no `runAfter` needed when referencing a result).
- **Workspaces** carry large data (the git repo); **Results** carry small data (the commit SHA, version string).
- This four-task pipeline mirrors production patterns: fetch → process → validate → report.
- **Workspaces are ephemeral.** The `volumeClaimTemplate` PVC is cleaned up after the run. To keep artifacts, you must extract them or add an upload task.

### Further Reading

- [Tekton Hub](https://hub.tekton.dev/) -- Browse community-maintained reusable Tasks (git-clone, kaniko, buildah, golang-build, etc.) instead of writing your own
- [How to Build a Reusable Tekton Task Catalog](https://oneuptime.com/blog/post/2026-02-09-tekton-task-catalog-reusable/view) -- Best practices for creating standardized, parameterized tasks that teams can share
- [Tekton Catalog on GitHub](https://github.com/tektoncd/catalog) -- Source for the official community task catalog; study these for well-structured Task design

---

## Lab 6: When Expressions (Conditional Execution)

**Concepts:** `when` expressions, conditional task execution, result-based branching, `operator: in`

When expressions let you conditionally skip tasks based on parameter values or results from previous tasks. This is one of the most heavily used patterns in production -- pipelines that deploy to different environments based on the branch, skip notifications when disabled, or gate on approval status.

### How When Expressions Work

```yaml
tasks:
  - name: deploy-prod
    when:
      - input: "$(tasks.check.results.is-main)"   # value to evaluate
        operator: in                                # "in" or "notin"
        values: ["true"]                            # list of acceptable values
    taskRef:
      name: run-deploy
```

If the `when` condition is **not met**, the task is **skipped** (not failed). Downstream tasks that depend on a skipped task via `runAfter` are also skipped, but tasks with no dependency on the skipped task still run.

### Apply and Run

```bash
# Apply the tasks (check-branch, run-deploy, run-integration-tests, send-notification)
kubectl apply -f 11-when-tasks.yaml

# Apply the pipeline
kubectl apply -f 12-when-pipeline.yaml

# Run with branch=main (triggers production deploy + integration tests)
kubectl create -f 12-when-pipelinerun-main.yaml

# Run with branch=feature/add-login (triggers staging deploy, skips integration tests)
kubectl create -f 12-when-pipelinerun-feature.yaml
```

### Observe

```bash
# Compare the two runs
tkn pipelinerun list

# Describe each -- notice which tasks were Skipped vs Succeeded
tkn pipelinerun describe --last

# The "main" run should show:
#   check:             Succeeded
#   deploy-prod:       Succeeded    ← when: is-main = "true"
#   deploy-staging:    Skipped      ← when: is-main != "false"
#   integration-tests: Succeeded    ← when: branch-type = "release"
#   notify-deploy:     Succeeded    ← when: enable-notifications = "true"

# The "feature" run should show:
#   check:             Succeeded
#   deploy-prod:       Skipped      ← when: is-main != "true"
#   deploy-staging:    Succeeded    ← when: is-main = "false"
#   integration-tests: Skipped      ← when: branch-type = "other" (not release/hotfix)
#   notify-deploy:     Skipped      ← when: enable-notifications = "false"
```

### Pipeline Execution Graph

```
                         ┌─────────────┐
                         │    check    │
                         │ (check-     │
                         │  branch)    │
                         └──────┬──────┘
                                │
              ┌─────────────────┼─────────────────┐─────────────┐
              │ when:           │ when:            │ when:       │ when:
              │ is-main=true    │ is-main=false    │ type=       │ enable-
              │                 │                  │ release     │ notif=true
              ▼                 ▼                  ▼             ▼
     ┌────────────┐   ┌────────────┐   ┌──────────────┐  ┌──────────┐
     │deploy-prod │   │deploy-     │   │ integration- │  │ notify-  │
     │            │   │ staging    │   │ tests        │  │ deploy   │
     └────────────┘   └────────────┘   └──────────────┘  └──────────┘
```

### Production Examples

From the `alchemists-platform-resources` repo:

**Conditional notification based on param:**
```yaml
# Only send Slack notifications when enabled
- name: notify-slack
  when:
    - input: "$(params.enable-notifications)"
      operator: in
      values: ["true"]
```

**Conditional execution based on approval result:**
```yaml
# Only proceed if deployment is approved
- name: seek-slack-approval
  when:
    - input: "$(tasks.is-deployment-manifest-approved.results.is_approved)"
      operator: in
      values: ["false"]
```

### Key Takeaways

- **`when` expressions** skip tasks without failing the pipeline. The task status shows as "Skipped."
- **Two operators:** `in` (value must be in the list) and `notin` (value must NOT be in the list).
- **Multiple conditions** on the same task are ANDed -- all must be true for the task to run.
- **Skipped tasks propagate:** If task B has `runAfter: [A]` and A is skipped, B is also skipped. But if B references A's result, B will fail (the result doesn't exist).
- This is how production pipelines implement branch-specific behavior, feature flags, and approval gates.

### Further Reading

- [When Expressions](https://tekton.dev/docs/pipelines/pipelines/#using-the-when-field) -- Official reference for `when` syntax, operators, and skip behavior
- [Guard Task Execution](https://tekton.dev/docs/pipelines/pipelines/#guard-task-execution-using-when-expressions) -- Patterns for conditional execution in Pipelines

---

## Lab 7: Finally Blocks (Always-Run Tasks)

**Concepts:** `finally` block, `$(tasks.status)`, cleanup tasks, notification patterns

Finally tasks **always run**, regardless of whether the pipeline succeeded or failed. This is the Tekton equivalent of `try/finally` in code -- use it for cleanup, notifications, releasing locks, or reporting status.

### How Finally Works

```yaml
spec:
  tasks:
    - name: build       # regular task
    - name: test        # regular task

  finally:
    - name: cleanup     # ALWAYS runs, even if build or test failed
    - name: report      # Also ALWAYS runs (finally tasks run in parallel)
```

Finally tasks have access to a special variable `$(tasks.status)` which reflects the aggregate pipeline status:
- `Succeeded` -- all tasks succeeded
- `Failed` -- at least one task failed
- `Completed` -- at least one task was skipped (but none failed)
- `None` -- no tasks executed

### Apply and Run

```bash
# Apply all tasks + the pipeline
kubectl apply -f 13-finally-pipeline.yaml

# Run it (the build task randomly fails ~33% of the time)
kubectl create -f 13-finally-pipelinerun.yaml
```

### Observe

```bash
tkn pipelinerun describe --last
tkn pipelinerun logs --last
```

**When the build succeeds:**
```
 NAME       TASK NAME          STATUS
 build      flaky-build        Succeeded
 test       run-tests-finally  Succeeded
 cleanup    cleanup-resources  Succeeded    ← finally: always runs
 report     report-status      Succeeded    ← finally: always runs
```

**When the build fails:**
```
 NAME       TASK NAME          STATUS
 build      flaky-build        Failed       ← random failure
 test       run-tests-finally  ---          ← skipped (depends on build)
 cleanup    cleanup-resources  Succeeded    ← finally: STILL runs
 report     report-status      Succeeded    ← finally: STILL runs
```

The cleanup and report tasks run in both cases. The `$(tasks.status)` parameter tells them whether the pipeline succeeded or failed.

### Experiment

Run the pipeline several times to see both success and failure paths:

```bash
for i in 1 2 3 4 5; do
  kubectl create -f 13-finally-pipelinerun.yaml
  sleep 2
done
tkn pipelinerun list
```

### Production Examples

From the `alchemists-platform-resources` repo:

**Slack notification on completion:**
```yaml
finally:
  - name: notify-slack
    when:
      - input: "$(params.enable-notifications)"
        operator: in
        values: ["true"]
    taskRef:
      resolver: bundles
      params:
        - name: bundle
          value: "registry.example.com/tekton-catalog/send-to-webhook-slack:v0.1.0"
    params:
      - name: slack-channel
        value: "#platform-alerts"
      - name: message
        value: "Pipeline $(tasks.status): $(params.repo-url)"
```

**Lease release on completion:**
```yaml
finally:
  - name: release-lease
    taskRef:
      name: lease-manager
    params:
      - name: action
        value: "release"
```

### Key Takeaways

- **`finally` tasks always run**, even if regular tasks failed or were skipped.
- **`$(tasks.status)`** gives the aggregate status of all non-finally tasks.
- **Finally tasks run in parallel** with each other (they don't have an ordering relationship).
- **`when` expressions work in finally tasks** -- you can conditionally skip a finally task (e.g., only notify on failure).
- Finally tasks **cannot** reference results from failed tasks (the results don't exist).
- This is the standard pattern for Slack notifications, lease release, and cleanup in production.

### Further Reading

- [Finally Tasks](https://tekton.dev/docs/pipelines/pipelines/#adding-finally-to-the-pipeline) -- Official reference for `finally` syntax and behavior
- [Using Aggregate Pipeline Status](https://tekton.dev/docs/pipelines/pipelines/#using-aggregate-execution-status-of-all-tasks) -- `$(tasks.status)` variable reference

---

## Lab 8: Retries and Timeouts (Resilience)

**Concepts:** `retries`, `timeout` (task-level), `timeouts` (pipeline-level), resilience patterns

Network operations fail. Builds hang. Retries and timeouts are how production pipelines handle the real world.

### How Retries Work

```yaml
tasks:
  - name: fetch-data
    retries: 3          # try up to 4 times total (1 original + 3 retries)
    taskRef:
      name: unreliable-fetch
```

When a task fails, Tekton creates a new TaskRun for the retry. Each retry gets a fresh Pod. The task's `retries` counter decrements until either the task succeeds or all retries are exhausted.

### How Timeouts Work

```yaml
# Task-level: this task must finish within 10 seconds
tasks:
  - name: process-data
    timeout: "10s"
    taskRef:
      name: slow-process

# Pipeline-level: the entire pipeline must finish within these limits
# (set in the PipelineRun)
spec:
  timeouts:
    pipeline: "5m"      # total wall-clock time for the entire run
    tasks: "3m"         # total time for all regular tasks
    finally: "1m"       # total time for all finally tasks
```

### Apply and Run

```bash
# Apply the tasks + pipeline
kubectl apply -f 14-retry-timeout-pipeline.yaml

# Run it
kubectl create -f 14-retry-timeout-pipelinerun.yaml
```

### Observe

```bash
tkn pipelinerun describe --last

# Watch for retry attempts
tkn pipelinerun logs -f --last
```

Look for retry attempts in the `describe` output -- you'll see `Retries` next to each task that was retried. The logs show each attempt.

### Experiment: Trigger a Timeout

```bash
kubectl create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: timeout-test-
spec:
  pipelineRef:
    name: retry-timeout-demo
  timeouts:
    pipeline: "30s"
    tasks: "20s"
    finally: "10s"
EOF
```

With a 20-second task timeout and tasks that take longer (with retries), you'll see tasks time out.

### Production Examples

From the `alchemists-platform-resources` repo:

```yaml
# Git operations: retry on network failure
- name: fetch-jumpbox-repository
  retries: 2
  taskRef:
    resolver: bundles
    params:
      - name: bundle
        value: "registry.example.com/tekton-catalog/git-clone:v0.1.0"

# Heavy builds: generous timeout
- name: skaffold-build-no-cache
  timeout: "1h30m0s"
  taskRef:
    name: skaffold-build-no-cache

# Platform CI: different tasks have different timeouts
- name: run-e2e-tests
  timeout: "3h30m0s"
  retries: 1
```

### Key Takeaways

- **`retries: N`** means N additional attempts after the first failure (total = N+1 attempts).
- Each retry creates a **new Pod** -- it's a fresh attempt, not a restart.
- **Task-level `timeout`** limits individual tasks. If a task times out mid-retry, remaining retries are abandoned.
- **Pipeline-level `timeouts`** set overall limits: `pipeline` (total), `tasks` (all regular tasks), `finally` (all finally tasks).
- In production, **git-clone** and **network operations** get retries. **Build tasks** get generous timeouts.
- If `timeouts.tasks` is reached, regular tasks are cancelled and `finally` tasks begin.

### Further Reading

- [Configuring TaskRun Retries](https://tekton.dev/docs/pipelines/pipelines/#using-the-retries-field) -- Official reference for retry behavior
- [Configuring Timeouts](https://tekton.dev/docs/pipelines/pipelineruns/#configuring-a-failure-timeout) -- Pipeline and task timeout configuration

---

## Lab 9: Sidecars (Auxiliary Containers)

**Concepts:** Sidecars, auxiliary services, service readiness, Docker-in-Docker pattern

Sidecars are containers that run alongside your Task's Steps in the same Pod. They're used for services that Steps need to interact with: databases, mock APIs, Docker daemons (DinD), or proxy servers.

### How Sidecars Work

```yaml
spec:
  steps:
    - name: use-service
      image: alpine:3
      script: |
        curl http://localhost:8080/api    # access the sidecar via localhost

  sidecars:
    - name: mock-api
      image: my-mock-server:latest        # runs alongside steps
```

Sidecars start before Steps and are terminated after all Steps complete. Since Steps and Sidecars share the same Pod, they communicate via `localhost`.

### Apply and Run

```bash
# Apply the sidecar task
kubectl apply -f 15-sidecar-task.yaml

# Run it
kubectl create -f 16-sidecar-taskrun.yaml
```

### Observe

```bash
tkn taskrun logs --last

# You should see:
# [wait-for-server] Waiting for sidecar HTTP server to be ready...
# [wait-for-server] Sidecar is ready!
# [use-sidecar] GET /health:
# [use-sidecar] {"status": "healthy"}
# [use-sidecar] GET /data:
# [use-sidecar] {"items": ["alpha", "beta", "gamma"], ...}
```

### How It Maps to a Pod

```
Pod (shared network: localhost)
├── Container: step-wait-for-server   ← Step 1: waits for sidecar
├── Container: step-use-sidecar       ← Step 2: queries sidecar
└── Container: sidecar-mock-server    ← Sidecar: runs Python HTTP server
                                         (started first, killed after steps finish)
```

### Production Examples

The `alchemists-platform-resources` repo uses sidecars for Docker-in-Docker (DinD):

```yaml
# Kind E2E tests: need a Docker daemon for creating Kind clusters
sidecars:
  - name: dind
    image: docker:dind
    securityContext:
      privileged: true
    env:
      - name: DOCKER_TLS_CERTDIR
        value: ""
    volumeMounts:
      - name: dind-storage
        mountPath: /var/lib/docker
```

Other sidecar patterns:
- **repo-validator**: Sidecar for validation services
- **render-cli**: Sidecar for rendering tools
- **e2e-run-task**: Sidecar for test infrastructure

### Key Takeaways

- **Sidecars share the Pod** with Steps -- they communicate via `localhost` and shared volumes.
- **Sidecars start first** and are killed after all Steps complete.
- **Wait for readiness**: Steps should poll the sidecar's health endpoint before proceeding (race condition if you don't).
- **DinD (Docker-in-Docker)** is the most common production sidecar -- it provides a Docker daemon for image building and Kind cluster creation.
- Sidecars can use `securityContext: { privileged: true }` when needed (e.g., DinD), but this requires cluster-level permissions.

### Further Reading

- [Tekton Sidecars](https://tekton.dev/docs/pipelines/tasks/#using-a-sidecar-in-a-task) -- Official reference for sidecar configuration
- [Docker-in-Docker with Tekton](https://tekton.dev/docs/how-to-guides/kaniko-build-push/) -- Building images inside Tekton using DinD sidecars

---

## Lab 10: Matrix (Fan-Out Parallelism)

**Concepts:** `matrix.params`, `matrix.include`, cartesian product, fan-out/fan-in

Matrix lets you run a single task multiple times with different parameter combinations -- in parallel. It's the Tekton equivalent of a CI matrix build (e.g., "test on Linux, macOS, and Windows simultaneously").

### Two Matrix Modes

**Cartesian product (`matrix.params`):** Every combination of parameter values:
```yaml
matrix:
  params:
    - name: platform
      value: ["linux", "macos", "windows"]    # 3 values
    - name: env
      value: ["dev", "staging"]               # 2 values
# Creates 3 × 2 = 6 parallel TaskRuns
```

**Explicit combinations (`matrix.include`):** Named parameter sets:
```yaml
matrix:
  include:
    - name: linux-prod
      params:
        - name: platform
          value: "linux"
        - name: env
          value: "prod"
    - name: macos-prod
      params:
        - name: platform
          value: "macos"
        - name: env
          value: "prod"
# Creates exactly 2 TaskRuns (one per include entry)
```

### Apply and Run

```bash
# Apply the parameterized task
kubectl apply -f 17-matrix-task.yaml

# Apply the pipeline
kubectl apply -f 18-matrix-pipeline.yaml

# Run it (creates 6 + 2 = 8 parallel TaskRuns!)
kubectl create -f 18-matrix-pipelinerun.yaml
```

### Observe

```bash
# Watch pods spin up in parallel
kubectl get pods -w

# Describe shows all matrix instances
tkn pipelinerun describe --last

# View logs for all instances
tkn pipelinerun logs --last
```

You'll see 6 pods for `cross-platform-test` (one per platform/environment combination) running simultaneously, followed by 2 pods for `prod-smoke-test`.

### How Matrix Creates TaskRuns

```
Pipeline: matrix-demo
│
├── cross-platform-test (matrix.params: 3 platforms × 2 envs)
│   ├── TaskRun: linux/dev      ─┐
│   ├── TaskRun: linux/staging   │
│   ├── TaskRun: macos/dev       ├── all 6 run in PARALLEL
│   ├── TaskRun: macos/staging   │
│   ├── TaskRun: windows/dev     │
│   └── TaskRun: windows/staging─┘
│
└── prod-smoke-test (matrix.include: 2 explicit combos)
    ├── TaskRun: linux-prod      ─┐ run after cross-platform-test
    └── TaskRun: macos-prod      ─┘ (both in parallel)
```

### Production Examples

From the `alchemists-platform-resources` repo:

```yaml
# populate-namespace-registry: matrix across 10+ repositories
- name: populate-registries
  taskRef:
    name: registry-cli
  matrix:
    include:
      - name: scylla
        params:
          - name: repo-name
            value: "scylla"
          - name: repo-url
            value: "https://ghe.example.com/scylla.git"
      - name: platform-services
        params:
          - name: repo-name
            value: "platform-services"
          - name: repo-url
            value: "https://ghe.example.com/platform-services.git"
      # ... 8 more repos
```

### Key Takeaways

- **`matrix.params`** creates a cartesian product -- useful for testing across dimensions (platform × version × environment).
- **`matrix.include`** creates explicit combinations -- useful when the parameter sets aren't a clean grid.
- All matrix instances **run in parallel** and each gets its own Pod.
- **Results from matrix tasks** are returned as arrays (one result per instance).
- Be mindful of resource limits -- a 5×5 matrix creates 25 simultaneous Pods.
- This is how production pipelines process multiple repositories, clusters, or environments in parallel.

### Further Reading

- [Matrix](https://tekton.dev/docs/pipelines/matrix/) -- Official reference for matrix configuration, result aggregation, and fan-out patterns
- [Matrix Parameter Combinations](https://tekton.dev/docs/pipelines/matrix/#generating-combinations) -- Detailed examples of params vs include

---

## Lab 11: Service Accounts, RBAC, and Secrets

**Concepts:** ServiceAccount, Role, RoleBinding, Tekton-annotated Secrets, `taskRunTemplate.serviceAccountName`

Production pipelines don't run as the default service account. They use dedicated ServiceAccounts with specific RBAC permissions, linked to Secrets for Git authentication and container registry access. This is a security fundamental.

### How Tekton Uses Service Accounts

```
PipelineRun
  └── serviceAccountName: pipeline-runner
       └── ServiceAccount: pipeline-runner
            ├── Secret: git-basic-auth         (annotation: tekton.dev/git-0)
            ├── Secret: registry-credentials   (annotation: tekton.dev/docker-0)
            └── RoleBinding → Role: pipeline-role
                 └── Permissions: PVCs, ConfigMaps, Secrets, Pods
```

Tekton automatically injects annotated Secrets into task Pods:
- Secrets annotated with `tekton.dev/git-0: https://github.com` are mounted for Git operations targeting that host.
- Secrets annotated with `tekton.dev/docker-0: https://index.docker.io` are mounted for container registry operations.

### Apply the RBAC Setup

```bash
# Create the ServiceAccount, Role, RoleBinding, and placeholder Secrets
kubectl apply -f 19-rbac-setup.yaml
```

> **Note:** The secrets in `19-rbac-setup.yaml` contain placeholder values. Replace them with real credentials for actual Git/registry access. For this lab, the pipeline works with public repos.

### Apply and Run the Pipeline

```bash
# Apply the tasks + pipeline
kubectl apply -f 20-secret-pipeline.yaml

# Run it with the dedicated service account
kubectl create -f 20-secret-pipelinerun.yaml
```

### Observe

```bash
tkn pipelinerun describe --last
tkn pipelinerun logs --last

# Verify the pod ran with the correct service account
kubectl get pods -l tekton.dev/pipelineRun --sort-by=.metadata.creationTimestamp -o jsonpath='{range .items[*]}{.metadata.name}: sa={.spec.serviceAccountName}{"\n"}{end}'
```

### Secret Access Patterns

**Pattern 1: Tekton-annotated secrets (automatic injection):**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: git-basic-auth
  annotations:
    tekton.dev/git-0: https://github.com    # Tekton injects this for github.com URLs
type: kubernetes.io/basic-auth
stringData:
  username: "my-user"
  password: "my-token"
```

**Pattern 2: Environment variable from secret:**
```yaml
steps:
  - name: use-api
    env:
      - name: API_TOKEN
        valueFrom:
          secretKeyRef:
            name: my-api-secret
            key: token
```

**Pattern 3: Secret as workspace volume:**
```yaml
workspaces:
  - name: credentials
    secret:
      secretName: signing-key
```

### Production Examples

From the `alchemists-platform-resources` repo:

- **Per-pipeline ServiceAccounts**: `component-build`, `tekton-pipeline-validator`, `namespace-registry-bot`, `certbot`, etc.
- **RoleBindings per namespace**: Each pipeline namespace has its own RBAC granting the minimum required permissions.
- **Git auth**: `git-basic-auth` secret linked to internal GitHub Enterprise (`ghe.privatelinks.awswd`).
- **Registry auth**: `registry-credentials` secret for pulling task bundles from private registries.
- **Signing keys**: `approvable-resources` secret mounted as a volume for JWT RSA256 signing.
- **SecretsPolicy/SecretsAccess**: Custom CRDs for enterprise secret injection (organization-specific pattern).

### Key Takeaways

- **Every production pipeline should have its own ServiceAccount** with minimum required permissions.
- **Tekton-annotated secrets** (`tekton.dev/git-0`, `tekton.dev/docker-0`) are automatically injected -- no manual mounting needed.
- **`taskRunTemplate.serviceAccountName`** in the PipelineRun applies the SA to all tasks. Individual tasks can override with `taskRunTemplate` at the task level.
- **Never use the default service account** for pipelines that access Git repos, registries, or secrets.
- **Separate secrets per concern**: Git auth, registry auth, API tokens, and signing keys should be different secrets.

### Further Reading

- [Authentication for Tekton](https://tekton.dev/docs/pipelines/auth/) -- Official guide for configuring Git and Docker authentication
- [Using ServiceAccounts](https://tekton.dev/docs/pipelines/pipelineruns/#specifying-a-serviceaccount) -- Linking ServiceAccounts to PipelineRuns
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) -- Role, ClusterRole, RoleBinding, ClusterRoleBinding reference

---

## Lab 12: Advanced Workspaces (SubPath and Inline Tasks)

**Concepts:** `subPath`, inline `taskSpec`, multi-repo workspace sharing, workspace partitioning

Production pipelines often clone multiple repositories and combine their contents for a single build. The key pattern: **one PVC, multiple subPaths**. This lab also introduces **inline taskSpec** -- embedding task definitions directly in the pipeline.

### The SubPath Pattern

```
Single PVC (volumeClaimTemplate)
├── app/        ← subPath: clone-app writes here
├── config/     ← subPath: clone-config writes here
└── output/     ← subPath: merge-and-build writes here
```

Each task gets a different "view" of the same volume by specifying `subPath`:

```yaml
workspaces:
  - name: output
    workspace: resources
    subPath: app          # task sees /workspace/output → PVC/app/
```

### Apply and Run

```bash
# Apply the pipeline (all tasks are inline)
kubectl apply -f 21-subpath-pipeline.yaml

# Run it
kubectl create -f 21-subpath-pipelinerun.yaml
```

### Observe

```bash
tkn pipelinerun logs -f --last
tkn pipelinerun describe --last
```

The output shows:
1. Two repos cloned into separate subPaths (`app/` and `config/`)
2. A build task that reads from both subPaths and writes to a third (`output/`)
3. A report task that reads from the output subPath

### How It Compares to the Production Pattern

**This lab:**
```yaml
- name: clone-app
  workspaces:
    - name: output
      workspace: resources
      subPath: app

- name: clone-config
  workspaces:
    - name: output
      workspace: resources
      subPath: config
```

**Production `agr-jumpbox`:**
```yaml
- name: fetch-jumpbox-repository
  workspaces:
    - name: output
      workspace: resources
      subPath: repo

- name: fetch-venice-client
  workspaces:
    - name: output
      workspace: resources
      subPath: venice-client

- name: compile-venice-client
  workspaces:
    - name: source
      workspace: resources
      subPath: venice-client    # reads from source checkout
    - name: output
      workspace: resources
      subPath: repo             # writes compiled binary into main repo
```

The compile tasks read from one subPath and write to another -- this is how multiple compiled binaries end up in the main repo directory for the final container image build.

### Inline taskSpec vs Separate Tasks

This lab uses **inline taskSpec** instead of separate Task resources:

```yaml
# Inline: task definition embedded in the pipeline
- name: clone-app
  taskSpec:              # ← embedded definition
    steps:
      - name: clone
        image: alpine/git:latest
        script: |
          git clone ...

# vs. Separate: reference a Task that exists in the cluster
- name: clone-app
  taskRef:               # ← reference to existing Task
    name: git-clone
```

**When to use inline taskSpec:**
- One-off tasks specific to this pipeline
- Simple scripts that don't warrant a separate resource
- Quick prototyping

**When to use separate Tasks (taskRef):**
- Reusable tasks shared across pipelines
- Tasks maintained in a catalog
- Tasks distributed via bundles

### Key Takeaways

- **`subPath`** partitions a single PVC into isolated directories for each task.
- Tasks can **read from one subPath and write to another** -- this is how production pipelines combine multiple source repos into a single build.
- **Inline `taskSpec`** is convenient for one-off tasks but not reusable across pipelines.
- The production `agr-jumpbox` pipeline clones **8 repositories** into subPaths, compiles each, and builds a container image from the combined output.

### Further Reading

- [Workspace SubPaths](https://tekton.dev/docs/pipelines/workspaces/#using-subpath) -- Official reference for subPath configuration
- [Inline Task Definitions](https://tekton.dev/docs/pipelines/pipelines/#specifying-the-target-task) -- Using taskSpec in pipelines

---

## Lab 13: Bundle Resolvers and Task Catalogs

**Concepts:** Bundle resolver, OCI bundles, `tkn bundle push`, task catalogs, versioned tasks

Bundle resolvers are how production teams distribute and version Tekton Tasks. Instead of `kubectl apply -f task.yaml` on every cluster, you package the Task as an OCI image (like a Docker image) and push it to a container registry. Pipelines then reference it by registry URL and version tag.

### The Three TaskRef Styles

| Style | Syntax | Use Case |
|-------|--------|----------|
| **Cluster reference** | `taskRef: { name: my-task }` | Task exists in the same namespace |
| **Inline taskSpec** | `taskSpec: { steps: [...] }` | One-off task, no reuse needed |
| **Bundle resolver** | `taskRef: { resolver: bundles, params: [...] }` | Versioned task from a registry |

### How Bundle Resolvers Work

```
┌──────────────────┐     ┌───────────────────────────┐     ┌──────────────────┐
│ Task YAML        │     │ Container Registry         │     │ Pipeline         │
│ (git-clone.yaml) │ ──→ │ registry.example.com/      │ ←── │ resolver: bundles│
│                  │push │ tekton-catalog/git-clone   │pull │ bundle: ...      │
│                  │     │ :v0.1.0-abc1234            │     │ name: git-clone  │
└──────────────────┘     └───────────────────────────┘     └──────────────────┘
```

### Apply and Run

```bash
# Apply the bundleable task + demo pipeline
kubectl apply -f 22-bundle-pipeline.yaml

# Run it (demonstrates cluster ref + inline styles; bundle ref is commented)
kubectl create -f 22-bundle-pipelinerun.yaml
```

### Creating a Bundle (Reference)

To package and push a Task as a bundle:

```bash
# Package a task as an OCI bundle and push to a registry
tkn bundle push docker.io/myorg/tekton-catalog/git-clone:v1.0.0 \
  -f 22-bundle-pipeline.yaml

# List contents of a bundle
tkn bundle list docker.io/myorg/tekton-catalog/git-clone:v1.0.0
```

### Bundle Resolver Syntax

```yaml
taskRef:
  resolver: bundles
  params:
    - name: bundle
      value: "docker-images-release.example.com/tekton-catalog/git-clone:v0.1.0-e4c4b48"
    - name: name
      value: git-clone
    - name: kind
      value: Task
    - name: secret
      value: registry-credentials   # for private registries
```

### Production Pattern: Kustomize Patches for Bundle Migration

The `alchemists-platform-resources` repo uses **Kustomize JSON 6902 patches** to convert cluster-local `taskRef` to bundle resolvers per cluster:

```yaml
# kustomization.yaml
patches:
  - target:
      kind: Pipeline
      name: my-pipeline
    patch: |
      - op: replace
        path: /spec/tasks/0/taskRef
        value:
          resolver: bundles
          params:
            - name: bundle
              value: "registry.example.com/catalog/git-clone:v0.1.0"
            - name: name
              value: git-clone
            - name: kind
              value: Task
```

This lets you develop with cluster-local tasks and deploy with bundle resolvers -- same Pipeline definition, different taskRef at deploy time.

### Tekton Pipelines Bundle Resolver Configuration

Production clusters configure the bundle resolver with caching:

```yaml
# Tekton Pipelines config
bundleresolver:
  cachemode: always      # cache resolved bundles
resolver:
  maxsize: 1000          # max number of cached resolutions
  ttl: 72h               # cache TTL
```

### Key Takeaways

- **Bundle resolvers** enable versioned, distributable task catalogs stored in container registries.
- **`tkn bundle push`** packages Task YAML as an OCI image. **`resolver: bundles`** pulls it at runtime.
- **The `secret` param** authenticates against private registries (e.g., `registry-credentials`).
- Production teams maintain a **centralized task catalog** with versioned tasks. Pipelines pin to specific versions (e.g., `git-clone:v0.1.0-e4c4b48`).
- **Kustomize patches** can swap cluster-local taskRefs for bundle resolvers per environment.
- Bundle resolution is **cached** in production for performance (configured in Tekton Pipelines config).

### Further Reading

- [Bundles Resolver](https://tekton.dev/docs/pipelines/bundle-resolver/) -- Official bundle resolver reference
- [Remote Resolution](https://tekton.dev/docs/pipelines/resolution/) -- Framework for all resolvers (bundles, git, hub, cluster)
- [Tekton Bundle Contracts](https://tekton.dev/docs/pipelines/tekton-bundle-contracts/) -- OCI format specification for bundles
- [tkn bundle](https://tekton.dev/docs/cli/#tekton-cli-bundle) -- CLI reference for creating and inspecting bundles

---

## Lab 14: Production Operations (CronJobs, Cleanup, Kustomize)

**Concepts:** CronJob-triggered pipelines, PipelineRun cleanup, Kustomize overlays for Tekton, namespace-per-pipeline pattern

This lab covers the operational patterns that keep production Tekton clusters running smoothly. These aren't Tekton features per se -- they're Kubernetes patterns wrapped around Tekton.

### Pattern 1: CronJob-Triggered Pipelines

Production pipelines are triggered by **Prow** (webhook-based) or **CronJobs** (time-based). CronJobs handle scheduled work: nightly E2E tests, certificate renewals, periodic reports, and sync jobs.

The pattern:
1. CronJob runs a kubectl container on a schedule
2. Deletes any previous PipelineRun with the same name (idempotent)
3. Creates a new PipelineRun

```bash
# Review the CronJob + required RBAC
cat 23-cronjob-trigger.yaml

# Apply it (creates ServiceAccount, Role, RoleBinding, CronJob)
kubectl apply -f 23-cronjob-trigger.yaml

# Verify the CronJob is created
kubectl get cronjobs

# Manually trigger it to test (instead of waiting for the schedule)
kubectl create job --from=cronjob/scheduled-pipeline-trigger manual-trigger-test
```

### Key CronJob Configuration

```yaml
spec:
  schedule: "0 * * * *"          # when to run (cron syntax)
  concurrencyPolicy: Forbid      # don't start a new job if the previous is still running
  successfulJobsHistoryLimit: 3  # keep 3 completed jobs for debugging
  failedJobsHistoryLimit: 3      # keep 3 failed jobs for debugging
```

Production examples:
- `"0 */6 * * *"` -- every 6 hours (certificate renewal check)
- `"0 2 * * 1-5"` -- 2 AM weekdays (nightly E2E tests)
- `"*/30 * * * *"` -- every 30 minutes (sync jobs)

> **Note:** CronJob pods set `sidecar.istio.io/inject: "false"` because they're short-lived and don't need service mesh traffic management.

### Pattern 2: PipelineRun Cleanup

PipelineRuns accumulate over time. Each one creates Pods, PVCs, and metadata. Without cleanup, the namespace fills up. Production clusters run a daily CronJob to delete old runs.

```bash
# Review the cleanup CronJob
cat 24-cleanup-cronjob.yaml

# Apply it
kubectl apply -f 24-cleanup-cronjob.yaml

# Manually test the cleanup
kubectl create job --from=cronjob/cleanup-old-pipelineruns manual-cleanup-test
```

### Pattern 3: Kustomize for Tekton Resource Management

Production Tekton resources are managed with **Kustomize**, not raw `kubectl apply`. This enables:
- **Base definitions** shared across environments
- **Per-cluster overlays** for environment-specific configuration
- **JSON 6902 patches** to swap taskRefs for bundle resolvers

```bash
# Review the Kustomize structure
ls -la 25-kustomize/
ls -la 25-kustomize/base/
ls -la 25-kustomize/overlays/dev/
ls -la 25-kustomize/overlays/prod/

# Build and preview the dev overlay
kubectl kustomize 25-kustomize/overlays/dev/

# Build and preview the prod overlay
kubectl kustomize 25-kustomize/overlays/prod/

# Apply the dev overlay
kubectl apply -k 25-kustomize/overlays/dev/
```

### Kustomize Structure

```
25-kustomize/
├── base/
│   ├── kustomization.yaml     # resources + common labels
│   ├── task.yaml              # base task definition
│   └── pipeline.yaml          # base pipeline definition
└── overlays/
    ├── dev/
    │   └── kustomization.yaml # namespace: tekton-dev, retries: 1, timeout: 10m
    └── prod/
        └── kustomization.yaml # namespace: tekton-prod, retries: 3, timeout: 1h
```

### Production Kustomize Pattern

The `alchemists-platform-resources` repo uses this structure per team namespace:

```
component-config/
└── skates/
    └── skates-pipelines/
        └── namespaces/
            └── agr-jumpbox/
                ├── pipelines/
                │   ├── pipeline.yaml
                │   └── kustomization.yaml
                ├── service-accounts/
                │   ├── sa.yaml
                │   └── kustomization.yaml
                └── kustomization.yaml        # includes pipelines + service-accounts
```

With per-cluster overlays that patch bundle resolver URLs:

```
clusters/
├── cpe-004/
│   └── kustomization.yaml   # patches for cpe-004 cluster
├── cpe-005/
│   └── kustomization.yaml   # patches for cpe-005 cluster
└── s0050/
    └── kustomization.yaml   # patches for s0050 cluster
```

### Pattern 4: Namespace-per-Pipeline

Production Tekton resources are organized by namespace:

```
Namespace: agr-jumpbox
├── Pipeline: agr-jumpbox
├── ServiceAccount: component-build
├── Secret: git-basic-auth
├── Secret: registry-credentials
├── RoleBinding: component-build-binding
└── CronJob: (if scheduled)

Namespace: platform-validation
├── Pipeline: platform-services-ci
├── Pipeline: platform-ci-aws-e2e-tests
├── ServiceAccount: platform-test
├── Secret: git-basic-auth
└── RoleBinding: platform-test-binding
```

Each pipeline gets its own namespace with:
- Dedicated ServiceAccount and RBAC
- Pipeline-specific secrets
- Kustomization for that namespace
- Optional HNC (Hierarchical Namespaces) for shared parent config

### Key Takeaways

- **CronJobs** are the standard way to trigger scheduled pipeline runs in production.
- **`concurrencyPolicy: Forbid`** prevents overlapping runs.
- **Cleanup CronJobs** are essential -- without them, old PipelineRuns consume resources indefinitely.
- **Kustomize** manages environment-specific Tekton config: different namespaces, timeouts, retries, and bundle resolver URLs per cluster.
- **Namespace-per-pipeline** provides isolation: each pipeline's RBAC, secrets, and resources are scoped to its namespace.
- **HNC (Hierarchical Namespace Controller)** lets child namespaces inherit config from a parent (e.g., `tekton-pipelines`).

### Further Reading

- [Kustomize Documentation](https://kustomize.io/) -- Official Kustomize reference
- [Kubernetes CronJobs](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) -- CronJob configuration reference
- [Hierarchical Namespaces (HNC)](https://github.com/kubernetes-sigs/hierarchical-namespaces) -- Namespace hierarchy and policy inheritance

---

## Capstone: Real-World Rust Build (rto-rust)

**Concepts applied:** This capstone project ties together nearly every concept from the preceding labs -- Tasks, Pipelines, Params, Results, Workspaces, multi-step Tasks, parallel execution, and result-driven reporting. It builds a real Rust project with cross-compilation for three platforms.

> **Prerequisites:** Complete Labs 1-5 (at minimum) before attempting this capstone. Labs 6-14 will deepen your understanding of the patterns used here.

This capstone builds a real Rust project -- [rto-rust](https://github.com/MarkDHarris/rto-rust), a terminal-based Return-to-Office attendance tracker. The pipeline clones the repo, runs format checks + linting + 200+ tests, **cross-compiles release binaries for Linux x64, macOS ARM64, and Windows x64**, and produces a build report.

### What Makes This Different from Lab 5

| Lab 5 | Capstone |
|-------|----------|
| Lightweight tasks (alpine containers) | Heavy tasks (full Rust toolchain, ~1.5GB image) |
| Simulated tests | Real `cargo test` suite (200+ tests) |
| No actual compilation | Real `cargo build --release` with cross-compilation for 3 platforms |
| Generic tasks | Project-specific pipeline |
| Seconds to run | Minutes to run (real-world build times) |

### Pipeline Architecture

```
┌─────────┐     ┌──────────────────────────────┐     ┌──────────────────────────────┐     ┌──────────┐
│  clone  │ ──→ │  check                       │ ──→ │  build                       │ ──→ │  report  │
│         │     │  Step 1: cargo fmt --check   │     │  Step 1: build-linux-windows │     │          │
│ git     │     │  Step 2: cargo clippy        │     │   → Linux x64 (gcc cross)   │     │ summary  │
│ clone   │     │  Step 3: cargo test          │     │   → Windows x64 (mingw)     │     │ of all   │
│         │     │                              │     │  Step 2: build-macos         │     │ results  │
└─────────┘     └──────────────────────────────┘     │   → macOS ARM64 (osxcross)  │     └──────────┘
  alpine/git          rust:1.93 (3 steps)            │  Step 3: summary             │      alpine:3
                                                     └──────────────────────────────┘
                                                       rust:1.93 + rust-darwin-builder

Results:         Results:                       Results:
  commit-sha       test-count                     binary-sizes (3 platforms)
  short-sha        check-status
```

The `check` task is a **multi-step Task** (Lab 2) -- three quality checks run as separate Steps in the same Pod. Each step that needs a non-default toolchain component (`rustfmt`, `clippy`) installs it at the start of its script.

### Why Each Step Installs Its Own Tools (The Container Filesystem Gotcha)

This is a common Tekton pitfall that's worth understanding deeply.

We said earlier that "Steps share a Pod" -- so you might expect that installing software in Step 1 makes it available in Step 2. **That's not how it works.** Each Step runs as a separate **container** in the Pod. Containers share **mounted volumes** (workspaces) but each gets its own isolated **root filesystem** from the container image.

```
Pod (shared network, shared volumes)
├── Container: fmt-check    ← fresh rust:1.93 image filesystem
│   └── /usr/local/rustup/  ← installs rustfmt HERE (container-local)
│   └── /workspace/          ← WORKSPACE VOLUME (shared with all containers)
│
├── Container: clippy        ← fresh rust:1.93 image filesystem
│   └── /usr/local/rustup/  ← rustfmt is NOT here (fresh container)
│   └── /workspace/          ← SAME workspace volume (sees fmt-check's files)
│
└── Container: test          ← fresh rust:1.93 image filesystem
    └── /usr/local/rustup/  ← neither rustfmt nor clippy here
    └── /workspace/          ← SAME workspace volume
```

| What | Shared across Steps? | Why |
|------|---------------------|-----|
| Workspace volumes (`/workspace/...`) | Yes | Kubernetes volume mounts are per-Pod |
| `CARGO_HOME` (when pointed at workspace) | Yes | It's just a directory on the shared volume |
| Container filesystem (`/usr/local/...`) | **No** | Each Step is a new container from the base image |
| `rustup component add` results | **No** | Installs to `/usr/local/rustup/` (container-local) |
| `apt install` results | **No** | Same reason -- writes to the container filesystem |

So the `fmt-check` step runs `rustup component add rustfmt` at the start of its script, and the `clippy` step separately runs `rustup component add clippy`. The `test` step only needs `cargo test`, which is included in the base image, so it doesn't need to install anything extra.

There's a related gotcha: **runtime dependencies and configuration your tests need**. The `rust:1.93` image has `rustc` and `cargo` but NOT `git`. If your test suite calls `git` (like the `rto-rust` backup tests do), those tests will panic at runtime. The fix is `apt-get install -y git` at the top of the test step.

Even after installing `git`, one test (`test_perform_with_remote`) still fails because it calls `git init` and then pushes to a branch named `main`. In a clean container, git's default branch name is `master` (not `main`), so the push targets a branch that doesn't exist. The fix: `git config --global init.defaultBranch main` before running tests. This is a common CI pitfall -- your local machine has git configured one way, but CI containers start with factory defaults.

The test step now installs git and configures three global settings before running `cargo test`:

```bash
apt-get install -y git
git config --global user.name "Tekton CI"
git config --global user.email "tekton@localhost"
git config --global init.defaultBranch main
```

**Workarounds in production:**
- **Custom images:** Build a `rust:1.93-with-tools` image that includes `rustfmt`, `clippy`, `git`, and anything else your build needs. No runtime setup, faster pipelines.
- **Single step:** Combine fmt + clippy + test into one step (one container, one install). Loses per-check granularity in logs but simplifies setup.
- **Workspace install:** Set `RUSTUP_HOME` to a workspace path. The install persists across steps, but the initial setup is more complex.

This pipeline uses the simplest approach: install what you need at the top of each step.

### How Cross-Compilation Works (The Build Task)

The `build` task compiles release binaries for three platforms from a Linux container (ARM on your Apple Silicon Mac). Every target is a cross-compilation -- even Linux x64, since the container is ARM.

**The approach:**

| Target | Step | Image | Toolchain |
|--------|------|-------|-----------|
| Linux x64 | `build-linux-and-windows` | `rust:1.93` | `gcc-x86-64-linux-gnu` as cross-linker |
| Windows x64 | `build-linux-and-windows` | `rust:1.93` | MinGW (`gcc-mingw-w64-x86-64`) as cross-linker |
| macOS ARM64 | `build-macos` | `joseluisq/rust-linux-darwin-builder` | [osxcross](https://github.com/tpoechtrager/osxcross) (`oa64-clang`) with bundled macOS SDK |

**Why two Steps instead of one?** Linux and Windows can share a single `rust:1.93` container -- both just need `apt-get install` for their cross-linkers. macOS is different: it needs Apple's CoreFoundation framework (via `chrono` → `iana_time_zone` → `core_foundation_sys`), which requires the macOS SDK. The [`rust-linux-darwin-builder`](https://github.com/joseluisq/rust-linux-darwin-builder) image bundles osxcross + the macOS SDK, so we use it as a separate Step.

**The container filesystem gotcha still applies.** The `build-linux-and-windows` step installs `gcc-x86-64-linux-gnu` and `gcc-mingw-w64-x86-64` to the container filesystem -- they're gone when `build-macos` starts in its own container. That's fine because the macOS step uses a completely different toolchain (osxcross). Both steps share the workspace (Lab 4), so the compiled binaries from step 1 are visible to steps 2 and 3.

**Why can't cargo-zigbuild handle macOS?** We tried it initially. Zig can produce Mach-O binaries for pure Rust projects, but `rto-rust` links against Apple's CoreFoundation framework (via `chrono`). Zig's sysroot doesn't include proprietary Apple frameworks. The osxcross image solves this by bundling an actual macOS SDK.

> **Note:** The macOS step uses whatever Rust version ships with the `rust-linux-darwin-builder` image (currently ~1.87), which may differ from the 1.93 used for Linux/Windows. This is fine -- each target compiles to its own `target/<triple>/` directory, and the cargo registry cache in `CARGO_HOME` (on the shared workspace) is version-agnostic.

### How Cargo Cache Sharing Works (What IS Shared)

While `rustup` installs go to the container filesystem (not shared), the **cargo dependency cache** IS shared because we explicitly point `CARGO_HOME` to the workspace:

```
WORKSPACE PVC (5Gi, persists across all tasks)
├── rto-rust/              ← cloned source code
│   ├── target/
│   │   ├── x86_64-unknown-linux-gnu/release/   ← Linux x64 binary
│   │   ├── aarch64-apple-darwin/release/        ← macOS ARM64 binary
│   │   └── x86_64-pc-windows-gnu/release/       ← Windows x64 binary (.exe)
│   └── .cargo/config.toml                       ← cross-compilation linker config
└── .cargo/                ← CARGO_HOME: downloaded crate registry + sources
                              (shared across ALL tasks via env var)
```

Each Rust step sets `CARGO_HOME` to a path on the workspace:

```yaml
env:
  - name: CARGO_HOME
    value: "$(workspaces.source.path)/.cargo"
```

Without this, each Pod would re-download all dependencies from crates.io. With it, only the first step pays the download cost.

### Apply and Run

> **Note:** The first run pulls the `rust:1.93` image (~1.5GB). On Kind, this can take several minutes depending on your connection. Subsequent runs use the cached image.

```bash
# Apply all four tasks + the pipeline
kubectl apply -f 26-rto-rust-pipeline.yaml

# Start the build
kubectl create -f 27-rto-rust-pipelinerun.yaml
```

### Observe the Build

```bash
# Stream logs in real-time (the best way to watch a long build)
tkn pipelinerun logs -f --last

# Or check status periodically
tkn pipelinerun describe --last

# Watch the pods come and go (one per task)
kubectl get pods -w
```

The `check` task will take the longest on the first run (downloading and compiling all Rust dependencies). You'll see cargo output streaming in real-time.

### Expected Output

The `report` task produces a summary like:

```
╔══════════════════════════════════════════════════════════╗
║              rto-rust BUILD REPORT                      ║
╠══════════════════════════════════════════════════════════╣
║  Repo:      https://github.com/MarkDHarris/rto-rust.git
║  Commit:    a1b2c3d (a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0)
║  Checks:    PASS (fmt + clippy + test)
║  Tests:     202 passed
║  Targets:   Linux x64, macOS ARM64, Windows x64
║  Sizes:     linux-x64=4.5M, macos-arm64=4.2M, windows-x64=5.1M
║  Built at:  2026-03-03T15:30:00Z
╚══════════════════════════════════════════════════════════╝
```

### Retrieving the Built Binaries

The pipeline cross-compiles three binaries on the workspace PVC:

| Target | Binary Path | Runnable On |
|--------|------------|-------------|
| Linux x64 | `rto-rust/target/x86_64-unknown-linux-gnu/release/rto` | Any Linux x86_64 system |
| macOS ARM64 | `rto-rust/target/aarch64-apple-darwin/release/rto` | macOS Apple Silicon (M1/M2/M3/M4) |
| Windows x64 | `rto-rust/target/x86_64-pc-windows-gnu/release/rto.exe` | Windows 10/11 x64 |

Since `volumeClaimTemplate` PVCs are ephemeral (cleaned up after the run), you need to extract the binaries before they disappear.

**Option 1: Launch a debug pod to browse and copy artifacts**

```bash
# Find the PVC (it exists as long as the PipelineRun hasn't been garbage-collected)
kubectl get pvc

# Launch an interactive pod mounted to the PVC (replace <pvc-name>)
kubectl run artifact-browser --rm -it \
  --image=alpine:3 \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "artifact-browser",
        "image": "alpine:3",
        "command": ["sh"],
        "stdin": true,
        "tty": true,
        "volumeMounts": [{
          "name": "ws",
          "mountPath": "/workspace"
        }]
      }],
      "volumes": [{
        "name": "ws",
        "persistentVolumeClaim": {
          "claimName": "<pvc-name>"
        }
      }]
    }
  }'

# Inside the pod, explore the build output:
ls -lh /workspace/rto-rust/target/x86_64-unknown-linux-gnu/release/rto      # Linux x64 binary
ls -lh /workspace/rto-rust/target/aarch64-apple-darwin/release/rto          # macOS ARM64 binary
ls -lh /workspace/rto-rust/target/x86_64-pc-windows-gnu/release/rto.exe    # Windows x64 binary
ls /workspace/.cargo/registry/                                              # Cached crate downloads
```

**Option 2: Copy the binary to your local machine**

While the debug pod (or the last task pod) is still running:

```bash
# From the debug pod above -- copy all three binaries
kubectl cp artifact-browser:/workspace/rto-rust/target/x86_64-unknown-linux-gnu/release/rto ./rto-linux
kubectl cp artifact-browser:/workspace/rto-rust/target/aarch64-apple-darwin/release/rto ./rto-macos
kubectl cp artifact-browser:/workspace/rto-rust/target/x86_64-pc-windows-gnu/release/rto.exe ./rto.exe
```

> **Note:** The macOS ARM64 binary (`rto-macos`) can run directly on your Apple Silicon Mac. The Linux binary runs on any x86_64 Linux system. The Windows binary (`rto.exe`) runs on Windows 10/11 x64.

**Option 3 (production pattern): Add an artifact export task**

Add a final pipeline task that copies the binary somewhere persistent:

```yaml
    - name: export
      runAfter:
        - build
      taskSpec:
        workspaces:
          - name: source
        steps:
          - name: upload
            image: alpine:3
            script: |
              # In production, upload to S3, Artifactory, or a container registry.
              # For local testing, just verify the binaries exist:
              echo "Linux:"   && ls -lh $(workspaces.source.path)/rto-rust/target/x86_64-unknown-linux-gnu/release/rto
              echo "macOS:"   && ls -lh $(workspaces.source.path)/rto-rust/target/aarch64-apple-darwin/release/rto
              echo "Windows:" && ls -lh $(workspaces.source.path)/rto-rust/target/x86_64-pc-windows-gnu/release/rto.exe
      workspaces:
        - name: source
          workspace: source-code
```

This is why the production `agr-jumpbox` pipeline ends with `skaffold-build` -- it packages all compiled binaries into a container image and pushes it to a registry. The workspace PVC is just scratch space.

### Experiment: Build a Different Branch or Fork

The pipeline accepts parameters (Lab 2), so you can build any branch or fork:

```bash
kubectl create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: rto-rust-custom-
spec:
  pipelineRef:
    name: rto-rust-build
  params:
    - name: repo-url
      value: "https://github.com/MarkDHarris/rto-rust.git"
    - name: revision
      value: main
  workspaces:
    - name: source-code
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 5Gi
EOF
```

### Experiment: Add a Container Image Build Stage

In a real CI pipeline, after compiling the binary you'd package it into a container image. Here's how you'd extend this pipeline with a [Kaniko](https://github.com/GoogleContainerTools/kaniko) build step (requires a Dockerfile in the repo):

```yaml
    - name: image-build
      runAfter:
        - build
      taskRef:
        name: kaniko   # from Tekton Hub: https://hub.tekton.dev/tekton/task/kaniko
      params:
        - name: IMAGE
          value: "my-registry.com/rto:$(tasks.clone.results.short-sha)"
      workspaces:
        - name: source
          workspace: source-code
          subPath: rto-rust
```

This is exactly how the production `agr-jumpbox` pipeline works -- compile binaries, then build a container image with Skaffold.

### Troubleshooting

When a pipeline fails, the summary line tells you what happened at a high level:

```
Tasks Completed: 2 (Failed: 1, Cancelled 0), Skipped: 2
```

This means: 2 tasks ran (clone + check), 1 of them failed (check), and the remaining 2 (build + report) were skipped because the pipeline stopped.

Here's how to dig into what actually went wrong:

**Step 1: Find the failed PipelineRun name**

```bash
tkn pipelinerun list
# Look for the one with status "Failed"
```

**Step 2: See which task and step failed**

```bash
tkn pipelinerun describe --last
```

This shows each task's status. Look for the task marked `Failed` and which step within it failed. Example output:

```
 NAME       TASK NAME    STATUS
 clone      rto-clone    Succeeded
 check      rto-check    Failed       ← this task failed
 build      rto-build    ---          ← skipped (never ran)
 report     rto-report   ---          ← skipped
```

**Step 3: Get the logs for the failed task**

```bash
# Logs for a specific task within the pipeline run
tkn pipelinerun logs --last -t check

# Or get logs for ALL tasks (including successful ones, for context)
tkn pipelinerun logs --last --all
```

**Step 4: Get logs directly from the pod (more detail)**

If `tkn` truncates the output, go to the pod directly:

```bash
# Find the pod for the failed task
kubectl get pods -l tekton.dev/pipelineRun --sort-by=.metadata.creationTimestamp

# Get logs for a specific step (container) within the pod
kubectl logs <pod-name> -c step-fmt-check
kubectl logs <pod-name> -c step-clippy
kubectl logs <pod-name> -c step-test
```

**Step 5: Check pod events (for scheduling/resource issues)**

```bash
kubectl describe pod <pod-name>
```

Look at the `Events` section at the bottom. Common issues:
- `ImagePullBackOff` -- the `rust:1.93` image couldn't be pulled (network/tag issue)
- `OOMKilled` -- the container ran out of memory (Rust compilation is memory-hungry)
- `Evicted` -- the node ran out of disk space (build artifacts can be large)

**Step 6: Inspect the workspace (if the PVC still exists)**

```bash
# Check if the PVC is still around
kubectl get pvc

# If it is, browse the workspace for clues (build logs, partial output)
kubectl run debug --rm -it --image=alpine:3 \
  --overrides='{"spec":{"containers":[{"name":"debug","image":"alpine:3",
    "command":["sh"],"stdin":true,"tty":true,
    "volumeMounts":[{"name":"ws","mountPath":"/workspace"}]}],
    "volumes":[{"name":"ws","persistentVolumeClaim":{"claimName":"<pvc-name>"}}]}}'

# Inside the pod:
ls /workspace/rto-rust/                                              # Was the clone successful?
ls /workspace/.cargo/registry/                                       # Were dependencies downloaded?
ls /workspace/rto-rust/target/                                       # Did compilation start?
ls /workspace/rto-rust/target/x86_64-unknown-linux-gnu/release/      # Linux x64 binary?
ls /workspace/rto-rust/target/aarch64-apple-darwin/release/          # macOS ARM64 binary?
ls /workspace/rto-rust/target/x86_64-pc-windows-gnu/release/        # Windows x64 binary?
```

**Common failure causes and fixes:**

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `cargo-fmt is not installed` | `rust` image doesn't include `rustfmt` | Step should run `rustup component add rustfmt` first |
| `cargo-clippy is not installed` | Same as above | `rustup component add clippy` |
| Tests compile but fail | Actual test failure in the code | Check `cargo test` output for which test failed |
| Test fails with git-related panic | Tests that call `git` (e.g., backup tests) fail because `git` isn't in the `rust` image | Add `apt-get update && apt-get install -y git` before `cargo test` |
| `assertion failed: result.message.contains("pushed")` | Test does `git init` (creates `master` branch) then pushes to `main`. In CI containers, git's default branch is `master` unless configured | Add `git config --global init.defaultBranch main` before tests |
| No output after `cargo test` | Output was captured into a shell variable; if the command fails, the script exits before printing | Run `cargo test` directly with no pipes or captures so output streams to logs |
| `error: linker 'x86_64-w64-mingw32-gcc' not found` | MinGW cross-compiler not installed in the build step | Add `apt-get install -y gcc-mingw-w64-x86-64` before the Windows build |
| `error: linker 'x86_64-linux-gnu-gcc' not found` | Linux x64 cross-compiler not installed | Add `apt-get install -y gcc-x86-64-linux-gnu` before the Linux x64 build |
| `unable to find framework 'CoreFoundation'` | macOS target requires Apple's SDK (via osxcross) | Use the `joseluisq/rust-linux-darwin-builder` image which bundles osxcross + SDK |
| `oa64-clang: command not found` | macOS build step not using the darwin builder image | Ensure the `build-macos` step uses `joseluisq/rust-linux-darwin-builder:latest` |
| `OOMKilled` | Rust compilation needs lots of RAM (cross-compiling 3 targets amplifies this) | Give Kind more Docker memory (8GB+) or reduce parallelism with `CARGO_BUILD_JOBS=1` |
| `No space left on device` | 5Gi PVC is full (cross-compilation triples build output) | Increase PVC size in `27-rto-rust-pipelinerun.yaml` |
| Very slow / hanging | First-time dependency download | Be patient; check `tkn pipelinerun logs -f --last` for progress |
| `error[E0658]: edition 2024 is unstable` | Rust version too old | Ensure the image tag matches the project's required version |

**Re-running after a fix:**

```bash
# Re-apply the fixed pipeline definition
kubectl apply -f 26-rto-rust-pipeline.yaml

# Start a fresh run (each run is independent)
kubectl create -f 27-rto-rust-pipelinerun.yaml

# Clean up old failed runs (optional)
tkn pipelinerun delete --all -f
```

### Key Takeaways

- **Multi-step Tasks** (Lab 2) are the right pattern when steps need shared filesystem access (cargo cache, build artifacts).
- **`CARGO_HOME` on the workspace** (Lab 4) is a real-world technique for sharing dependency caches across tasks. The same pattern works for `GOPATH`, `npm_config_cache`, `pip cache`, etc.
- **Cross-compilation in CI** is practical with the right toolchains. MinGW handles Windows from Linux; `gcc-x86-64-linux-gnu` handles Linux x64 from ARM. macOS requires the Apple SDK (bundled in the `rust-linux-darwin-builder` image via osxcross). Different targets can use different container images within the same Task.
- **Real builds are slow.** The first run downloads ~200 crate dependencies, installs cross-compilation tools, and compiles for three targets. This is why production pipelines invest in caching, pre-built base images, and incremental builds.
- **The pipeline is parameterized** (Lab 2) -- the same definition can build any branch, tag, or fork by changing `repo-url` and `revision`.
- **Debugging pipelines** follows a funnel: PipelineRun → Task → Step → Pod → Container logs. The `tkn` CLI and `kubectl logs` are your primary tools.
- **Results** (Lab 3) carry metadata like commit SHAs, test counts, and binary sizes through the pipeline graph.
- **Workspaces** (Lab 4) carry the actual source code and compiled artifacts between tasks.

### Further Reading

- [Kaniko Task on Tekton Hub](https://hub.tekton.dev/tekton/task/kaniko) -- Build container images without Docker daemon (works inside Kubernetes pods)
- [Buildah Task on Tekton Hub](https://hub.tekton.dev/tekton/task/buildah) -- Alternative to Kaniko for OCI image builds
- [Caching Dependencies in Tekton](https://tekton.dev/docs/pipelines/workspaces/#using-persistentvolumeclaims-as-volumesource) -- Using persistent PVCs to cache dependencies across pipeline runs
- [Rust cross-compilation guide](https://rust-lang.github.io/rustup/cross-compilation.html) -- Official Rustup documentation on cross-compilation targets and toolchains
- [MinGW-w64](https://www.mingw-w64.org/) -- GNU toolchain for producing Windows executables from Linux
- [rust-linux-darwin-builder](https://github.com/joseluisq/rust-linux-darwin-builder) -- Docker image bundling Rust + osxcross + macOS SDK for cross-compiling to macOS from Linux
- [osxcross](https://github.com/tpoechtrager/osxcross) -- The underlying macOS cross-compilation toolchain used by the darwin builder image
- [cargo-zigbuild](https://github.com/rust-cross/cargo-zigbuild) -- Alternative for pure Rust projects (no Apple framework deps) using Zig as the linker

---

## Decoding a Production Pipeline

Now that you understand Tasks, Pipelines, Results, and Workspaces, let's decode the production `agr-jumpbox` pipeline. This section maps every concept you've learned to real-world usage.

### Architecture Overview

```
                         ┌──────────────┐
                         │ fetch-jumpbox │ (git-clone)
                         │ -repository   │
                         └──────┬───────┘
                                │
          ┌─────────┬───────────┼───────────┬──────────┬──────────┐
          ▼         ▼           ▼           ▼          ▼          ▼
     ┌─────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌─────────┐
     │ fetch-  │ │ fetch- │ │ fetch- │ │ fetch- │ │ fetch- │ │ fetch-  │
     │ venice  │ │ spc-   │ │ sso-   │ │ k8up-  │ │ agador │ │ alpaca- │
     │ -client │ │ cli    │ │ cli    │ │ grader │ │ -cli   │ │ tools   │
     └────┬────┘ └───┬────┘ └───┬────┘ └───┬────┘ └───┬────┘ └────┬────┘
          ▼          ▼          ▼          ▼          ▼     ┌──────┤
     ┌─────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌──────┐│ compile-
     │ compile-│ │compile-│ │compile-│ │compile-│ │compi-│├──────────┐
     │ venice  │ │ spc-   │ │ sso-   │ │ k8up-  │ │le-   ││ ca-valid │
     │ -client │ │ cli    │ │ cli    │ │ grader │ │agador││ pemtool  │
     └────┬────┘ └───┬────┘ └───┬────┘ └───┬────┘ └──┬───┘│ etc.    │
          └─────┬────┘──────────┘──────────┘─────────┘────┘──────────┘
                ▼                                          │
          ┌──────────────┐         ┌──────────────┐        │
          │ skaffold-    │ ◄───────│ generate-    │ ◄──────┘
          │ build-no-    │ version │ version      │ (parallel with all)
          │ cache        │         └──────────────┘
          └──────────────┘
```

The pipeline clones ~8 repos in parallel, compiles multiple Go binaries, then builds a container image containing everything.

### Pattern 1: Parallel Fan-Out

In the production pipeline, after the initial repository is cloned, **six fetch tasks run simultaneously**:

```yaml
tasks:
  - name: fetch-jumpbox-repository    # Stage 1: runs first
    ...

  - name: fetch-venice-client         # ┐
    runAfter:                          # │
      - "fetch-jumpbox-repository"    # │
    ...                                # │
                                       # │ Stage 2: all run in PARALLEL
  - name: fetch-spc-cli               # │ (each has runAfter: fetch-jumpbox)
    runAfter:                          # │
      - "fetch-jumpbox-repository"    # │
    ...                                # ┘
```

**Your lab equivalent:** In Lab 5, `version` and `test` run in parallel after `clone`.

### Pattern 2: Workspace SubPaths for Isolation

The production pipeline uses ONE workspace (`resources`) but gives each task its own subdirectory:

```yaml
spec:
  workspaces:
    - name: resources                 # Single workspace for the entire pipeline

tasks:
  - name: fetch-jumpbox-repository
    workspaces:
      - name: output
        workspace: resources
        subPath: repo                 # → /workspace/resources/repo/

  - name: fetch-venice-client
    workspaces:
      - name: output
        workspace: resources
        subPath: venice-client        # → /workspace/resources/venice-client/

  - name: compile-venice-client
    workspaces:
      - name: source
        workspace: resources
        subPath: venice-client        # reads from venice-client's checkout
      - name: output
        workspace: resources
        subPath: repo                 # writes compiled binary into repo dir
```

The compile tasks **read from one subPath** (the source code) and **write to another** (the output directory). The final skaffold build reads from the `repo` subPath, which by then contains the main repo plus all compiled binaries.

**Your lab equivalent:** Lab 4 introduced workspaces. SubPaths extend the concept to partition a single volume.

### Pattern 3: TaskRef Styles

The production pipeline uses three different ways to reference tasks:

**a) Bundle Resolver (OCI image containing the Task):**
```yaml
taskRef:
  resolver: bundles
  params:
    - name: bundle
      value: registry.example.com/tekton-task-catalog/git-clone:v0.1.0
    - name: name
      value: git-clone
    - name: kind
      value: Task
```
The Task YAML is packaged as an OCI image (like a Docker image) and stored in a container registry. The `resolver: bundles` tells Tekton to pull the Task definition from the registry at runtime. This enables versioned, distributable task catalogs.

**b) Direct cluster reference (Task installed in the same cluster):**
```yaml
taskRef:
  kind: Task
  name: git-clone
```
The Task must already exist in the same namespace (via `kubectl apply`). Simpler, but no versioning.

**c) Inline TaskSpec (Task definition embedded in the Pipeline):**
```yaml
taskSpec:
  workspaces:
    - name: source
    - name: output
  steps:
    - name: build
      image: golang:1.22
      script: |
        go build -o myapp main.go
```
The Task definition lives directly inside the Pipeline YAML. Not reusable, but convenient for one-off build steps.

**Your lab equivalent:** Labs 1-5 use direct cluster references (style b). Style (c) is just inlining what you'd normally put in a separate Task YAML.

### Pattern 4: Cross-Task Results

```yaml
- name: generate-version
  ...
  # This task writes a result called "version"

- name: skaffold-build-no-cache
  params:
    - name: tag
      value: $(tasks.generate-version.results.version)
  # The version string becomes the container image tag
```

**Your lab equivalent:** Lab 3 (result-chain) and Lab 5 (build-pipeline) both demonstrate this.

### Pattern 5: Retries for Unreliable Operations

```yaml
- name: fetch-jumpbox-repository
  retries: 2
```

Git clones over the network can fail. `retries: 2` means Tekton will try up to 3 times (1 original + 2 retries) before marking the task as failed.

### Pattern 6: Timeouts

```yaml
- name: skaffold-build-no-cache
  timeout: 1h30m0s
```

Container image builds can be slow. This sets a per-task timeout. Pipelines and PipelineRuns can also have overall timeouts.

### Summary: From Lab to Production

| Lab Concept | Production Usage |
|-------------|-----------------|
| Task with steps | Every fetch/compile/build step |
| Params | `PULL_PULL_SHA`, `REPO_NAME`, `golang_version`, etc. |
| Results | `generate-version.results.version` → image tag |
| Workspaces | Single `resources` workspace shared across all tasks |
| SubPaths | Each repo clone gets its own subPath |
| runAfter | Compile tasks wait for their fetch tasks |
| Parallel execution | All fetch tasks run simultaneously after the initial clone |
| Bundle resolver | Versioned task catalog stored in container registry |
| Inline taskSpec | Custom build steps that don't need reuse |
| Retries | Network operations (git-clone) |
| Timeouts | Long-running builds (skaffold) |

### Further Reading

- [Bundles Resolver](https://tekton.dev/docs/pipelines/bundle-resolver/) -- How bundle resolvers work, including authentication, caching, and configuration
- [Remote Resolution](https://tekton.dev/docs/pipelines/resolution/) -- The framework behind all resolvers (bundles, git, hub, cluster) and when to use each
- [Getting Started with Resolvers](https://tekton.dev/docs/pipelines/resolution-getting-started/) -- Hands-on guide to setting up and using remote resolvers
- [Tekton Bundles Contracts](https://tekton.dev/docs/pipelines/tekton-bundle-contracts/) -- OCI bundle format specification for packaging Tasks and Pipelines as container images

---

## Production Patterns Deep Dive

This section covers patterns from the `alchemists-platform-resources` repo that go beyond what can be demonstrated in a local Kind cluster. Understanding these is essential for working effectively in the production codebase.

### Prow Integration (Pipeline Triggering)

Production pipelines are triggered by **Prow**, not Tekton Triggers. Prow is a Kubernetes-native CI/CD system originally built for the Kubernetes project. It watches GitHub events (PRs, pushes, comments) and triggers Tekton PipelineRuns.

**How it works:**

```
GitHub PR opened/updated
  → Prow webhook receives event
    → Prow matches rules in .prow.yaml
      → Prow creates a PipelineRun with appropriate params
        → Tekton runs the pipeline
          → Prow reports status back to GitHub
```

**`.prow.yaml` structure:**

```yaml
presubmits:      # runs on PR (before merge)
  - name: platform-services-ci
    agent: tekton-pipeline
    pipeline_run_spec:
      pipelineRef:
        name: platform-services-ci
      params:
        - name: PULL_PULL_SHA
          value: "..."
      workspaces:
        - name: resources
          volumeClaimTemplate:
            spec:
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 10Gi

postsubmits:     # runs after merge to main
  - name: publish-on-merge
    agent: tekton-pipeline
    pipeline_run_spec:
      pipelineRef:
        name: publish-svc-manifests-on-merge
```

**Key Prow concepts:**
- **`presubmits`**: Run on every PR update (like CI checks)
- **`postsubmits`**: Run after merge to main (like CD triggers)
- **`agent: tekton-pipeline`**: Tells Prow to create a Tekton PipelineRun (vs. a Kubernetes Job)
- **Prow params**: `PULL_PULL_SHA`, `REPO_NAME`, `PULL_BASE_REF` etc. are injected by Prow
- **`timeout`**: Prow-level timeout (separate from Tekton's timeout)

> **Why Prow instead of Tekton Triggers?** The organization standardized on Prow before Tekton Triggers matured. Prow provides GitHub status reporting, `/test` and `/retest` comment commands, merge automation, and tide (automatic merging). Tekton Triggers RBAC is configured in the repo but the feature is disabled (`enable: false`).

### Slack Notifications

Production pipelines send notifications to Slack channels on completion (success or failure). This is implemented as a catalog task resolved via bundle.

**Pattern:**

```yaml
finally:
  - name: notify-slack
    when:
      - input: "$(params.enable-notifications)"
        operator: in
        values: ["true"]
    taskRef:
      resolver: bundles
      params:
        - name: bundle
          value: "registry.example.com/tekton-catalog/send-to-webhook-slack:v0.1.0"
        - name: name
          value: send-to-webhook-slack
        - name: kind
          value: Task
    params:
      - name: slack-channel
        value: "#platform-alerts"
      - name: message
        value: "Pipeline $(context.pipelineRun.name) $(tasks.status)"
      - name: webhook-secret
        value: scylla-slack-webhook
```

**Key points:**
- Notifications go in `finally` blocks so they always run
- `enable-notifications` param lets you disable them for testing
- The webhook URL is stored in a Kubernetes Secret
- Different channels for different severity levels (`#alerts` vs `#builds`)
- Multiple finally tasks can notify different channels about different failures

### Approval Workflows

Some production deployments require human approval before proceeding. The pattern:

1. Pipeline sends an approval request to Slack
2. A human approves or rejects via a console
3. Pipeline checks the approval status
4. If approved, deployment proceeds; if not, pipeline stops

```yaml
tasks:
  - name: seek-slack-approval
    taskRef:
      name: console-send-deployment-approval-request
    params:
      - name: slack-channel
        value: "#approvers"
      - name: diff-link
        value: "$(tasks.get-diff-link.results.url)"

  - name: check-approved
    taskRef:
      name: is-deployment-manifest-approved
    runAfter:
      - seek-slack-approval

  - name: deploy
    when:
      - input: "$(tasks.check-approved.results.is_approved)"
        operator: in
        values: ["true"]
    taskRef:
      name: kubectl-apply-replace
    runAfter:
      - check-approved
```

**Key points:**
- The approval task posts to Slack with a link to review changes
- A separate task polls for approval status
- `when` expression gates the deployment on approval
- This is used for production cluster changes, not routine builds

### Lease Management

When multiple pipelines compete for shared resources (like test clusters), lease management prevents conflicts:

```yaml
tasks:
  - name: acquire-lease
    taskRef:
      name: lease-manager
    params:
      - name: action
        value: "acquire"
      - name: lease-name
        value: "test-cluster-01"

  - name: run-e2e-tests
    runAfter:
      - acquire-lease
    taskRef:
      name: e2e-run-task

finally:
  - name: release-lease
    taskRef:
      name: lease-manager
    params:
      - name: action
        value: "release"
      - name: lease-name
        value: "test-cluster-01"
```

The lease is always released in a `finally` block, even if tests fail.

### Tekton Pipelines Configuration

Production clusters customize Tekton's behavior via ConfigMaps:

```yaml
# Feature flags
featureflags:
  coschedule: isolate-pipelinerun    # each PipelineRun gets its own node affinity

# Default pod template (applied to ALL TaskRun pods)
config_defaults:
  default-pod-template:
    securityContext:
      runAsUser: 0
      fsGroup: 0
    nodeSelector:
      affinity: tekton              # run on dedicated Tekton nodes
    tolerations:
      - key: workerrole
        operator: Equal
        value: tekton
        effect: NoSchedule           # Tekton nodes tainted to exclude non-Tekton pods

# Bundle resolver caching
bundleresolver:
  cachemode: always
resolver:
  maxsize: 1000
  ttl: 72h
```

**Key configurations:**
- **Node affinity/taints**: Tekton pods run on dedicated nodes, not mixed with application workloads
- **Security context**: `runAsUser: 0` (root) is common for build tasks that need to install packages
- **Bundle resolver caching**: Resolved bundles are cached for 72 hours to reduce registry pulls
- **`coschedule: isolate-pipelinerun`**: Tasks in the same PipelineRun are scheduled together for workspace affinity

### ArgoCD Integration (GitOps)

Some pipelines integrate with ArgoCD for deployments:

```yaml
- name: sync-argocd
  taskRef:
    name: gcp-argocd-sync-component
  params:
    - name: component-name
      value: "my-app"
    - name: cluster-name
      value: "prod-cluster"
```

Pattern: Tekton builds and tests (CI) → pushes to a Git repo → ArgoCD detects the change and deploys (CD).

### Resource Signing

The `signer` task creates JWT RSA256 signatures for Kubernetes resources that require approval:

```yaml
- name: sign-resources
  taskRef:
    name: signer
  params:
    - name: resource-path
      value: "$(workspaces.output.path)/manifests/"
    - name: annotation-key
      value: "jwtRSA256-public-2025-03-20.v1.approvable-resources-signature"
  workspaces:
    - name: signing-key
      secret:
        secretName: approvable-resources    # RSA private key
```

This is used for resources like Roles, RoleBindings, and ClusterRoles that could escalate privileges. The signature proves they were produced by an authorized pipeline.

### Skaffold for Image Building

Production pipelines use **Skaffold** instead of Kaniko/Buildah for container image builds:

```yaml
- name: build-image
  taskRef:
    resolver: bundles
    params:
      - name: bundle
        value: "registry.example.com/tekton-catalog/skaffold-build-no-cache:v0.1.0"
  params:
    - name: tag
      value: "$(tasks.generate-version.results.version)"
  workspaces:
    - name: source
      workspace: resources
      subPath: repo
```

Skaffold handles multi-artifact builds (multiple Dockerfiles in one repo), image tagging, and registry pushing.

### Migration Scripts

The repo contains Python scripts for migrating Tekton resources between API versions:

| Script | Purpose |
|--------|---------|
| `patch_pipelines.py` | Convert `taskRef` to bundle resolver format |
| `migrate_tasks_to_v1.py` | Migrate Tasks from v1beta1 to v1 |
| `migrate_pipelines_to_v1.py` | Migrate Pipelines to v1; `sidecarOverrides` → `sidecarSpecs` |
| `migrate_cronjobs_to_v1.py` | Migrate CronJobs to v1 |

These are run once during major upgrades. Understanding them helps when troubleshooting version-related issues.

### Kyverno Policy

Production clusters use **Kyverno** for policy enforcement:

```yaml
# Prevent Karpenter from evicting Tekton pods
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: karpenter-do-not-evict-tekton
spec:
  rules:
    - name: add-do-not-evict
      match:
        resources:
          namespaces: ["tekton-*"]
      mutate:
        patchStrategicMerge:
          metadata:
            annotations:
              karpenter.sh/do-not-evict: "true"
```

This ensures Tekton build pods aren't disrupted by cluster autoscaling.

---

## Concept Reference

### Quick Comparison: Steps vs Tasks vs Pipelines

| | Step | Task | Pipeline |
|---|------|------|----------|
| **Runs in** | A container | A Pod (all steps share it) | Multiple Pods |
| **Shares filesystem** | Yes (with other steps) | Within the Pod only | Via Workspaces |
| **Parallel execution** | No (sequential) | No (sequential steps) | Yes (tasks can run in parallel) |
| **Use for** | A single command/script | A logical unit (clone, build, test) | An entire workflow |

### Complete Feature Reference

| Feature | Lab | Description |
|---------|-----|-------------|
| **Task** | 1 | Reusable unit of work with one or more Steps |
| **TaskRun** | 1 | Single execution of a Task |
| **Pipeline** | 3 | DAG of Tasks |
| **PipelineRun** | 3 | Single execution of a Pipeline |
| **Params** | 2 | `$(params.name)` -- input parameters |
| **Results** | 3 | `$(results.name.path)`, `$(tasks.X.results.Y)` -- small data passing |
| **Workspaces** | 4 | Shared storage between Tasks (PVC, emptyDir, ConfigMap, Secret) |
| **runAfter** | 3 | Explicit task ordering |
| **when** | 6 | Conditional task execution |
| **finally** | 7 | Always-run tasks (cleanup, notifications) |
| **retries** | 8 | Automatic retry on failure |
| **timeout** | 8 | Per-task and pipeline-level time limits |
| **Sidecars** | 9 | Auxiliary containers in the same Pod |
| **Matrix** | 10 | Fan-out parallelism (cartesian product or explicit combos) |
| **ServiceAccount** | 11 | Dedicated identity and permissions for pipelines |
| **Secrets** | 11 | Git auth, registry creds, API tokens |
| **subPath** | 12 | Workspace partitioning for multi-repo pipelines |
| **Inline taskSpec** | 12 | Embedded task definitions in pipelines |
| **Bundle resolver** | 13 | Versioned tasks from OCI container registries |
| **CronJob triggers** | 14 | Scheduled pipeline execution |
| **Kustomize** | 14 | Environment-specific Tekton resource management |

### Variable Substitution Reference

| Syntax | Context | Example |
|--------|---------|---------|
| `$(params.name)` | Task or Pipeline params | `$(params.repo-url)` |
| `$(results.name.path)` | Write a result in a Task Step | `printf "value" > $(results.commit.path)` |
| `$(tasks.taskName.results.resultName)` | Read a result in a Pipeline | `$(tasks.clone.results.commit-sha)` |
| `$(workspaces.name.path)` | Workspace mount path | `cd $(workspaces.source.path)` |
| `$(tasks.status)` | Aggregate pipeline status (in finally) | `$(tasks.status)` → Succeeded/Failed |
| `$(context.pipelineRun.name)` | PipelineRun name | `$(context.pipelineRun.name)` |
| `$(context.pipeline.name)` | Pipeline name | `$(context.pipeline.name)` |
| `$(context.task.name)` | Task name | `$(context.task.name)` |

### Workspace Backing Options

| Type | Use Case | PipelineRun Syntax |
|------|----------|--------------------|
| **volumeClaimTemplate** | Temporary PVC, auto-cleaned | `volumeClaimTemplate: {spec: ...}` |
| **persistentVolumeClaim** | Reuse an existing PVC | `persistentVolumeClaim: {claimName: my-pvc}` |
| **emptyDir** | Fast ephemeral storage (no PVC overhead) | `emptyDir: {}` |
| **configMap** | Read-only config files | `configMap: {name: my-config}` |
| **secret** | Credentials, keys | `secret: {secretName: my-secret}` |

### TaskRef Styles

| Style | Example | When to Use |
|-------|---------|-------------|
| **Cluster ref** | `taskRef: { name: my-task }` | Task exists in cluster via `kubectl apply` |
| **Inline** | `taskSpec: { steps: [...] }` | One-off task, no reuse |
| **Bundle** | `taskRef: { resolver: bundles, params: [...] }` | Versioned catalog task |

### Useful tkn Commands

```bash
# Tasks
tkn task list
tkn task describe <name>

# TaskRuns
tkn taskrun list
tkn taskrun describe <name>
tkn taskrun logs <name>
tkn taskrun delete --all          # Clean up old runs

# Pipelines
tkn pipeline list
tkn pipeline describe <name>

# PipelineRuns
tkn pipelinerun list
tkn pipelinerun describe <name>
tkn pipelinerun logs <name>
tkn pipelinerun logs -f --last    # Stream logs for most recent run
tkn pipelinerun delete --all      # Clean up old runs

# Bundles
tkn bundle push <registry>/<name>:<tag> -f task.yaml
tkn bundle list <registry>/<name>:<tag>
```

---

## Cleanup

```bash
# Delete all runs
tkn pipelinerun delete --all -f
tkn taskrun delete --all -f

# Delete CronJobs (Lab 14)
kubectl delete cronjob scheduled-pipeline-trigger cleanup-old-pipelineruns 2>/dev/null

# Delete all pipelines from all labs
kubectl delete pipeline \
  build-pipeline workspace-demo result-chain rto-rust-build \
  conditional-deploy finally-demo retry-timeout-demo \
  matrix-demo rbac-secret-demo subpath-demo bundle-demo \
  2>/dev/null

# Delete all tasks from all labs
kubectl delete task \
  hello greeting generate-name display-result \
  write-file read-file git-clone-simple run-tests generate-version build-report \
  rto-clone rto-check rto-build rto-report \
  check-branch run-deploy run-integration-tests send-notification \
  flaky-build run-tests-finally cleanup-resources report-status \
  unreliable-fetch slow-process always-fails \
  sidecar-demo platform-test \
  clone-private-repo secret-env-demo \
  bundleable-git-clone \
  2>/dev/null

# Delete RBAC resources (Lab 11)
kubectl delete rolebinding pipeline-role-binding pipeline-trigger-binding 2>/dev/null
kubectl delete role pipeline-role pipeline-trigger-role 2>/dev/null
kubectl delete serviceaccount pipeline-runner cronjob-pipeline-trigger 2>/dev/null
kubectl delete secret git-basic-auth registry-credentials demo-api-token 2>/dev/null

# Delete Kustomize-managed resources (Lab 14)
kubectl delete -k 25-kustomize/overlays/dev/ 2>/dev/null
kubectl delete -k 25-kustomize/overlays/prod/ 2>/dev/null

# Delete any leftover PVCs from workspace demos
kubectl delete pvc -l tekton.dev/pipeline

# Uninstall Tekton Dashboard (if installed)
kubectl delete --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml

# Uninstall Tekton Pipelines
kubectl delete --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
```

---

## Additional Resources

### Official Documentation

- [Tekton Documentation](https://tekton.dev/docs/) -- Start here for the complete reference
- [Tekton Pipeline API Reference](https://tekton.dev/docs/pipelines/) -- Detailed spec for every resource type
- [Tekton Hub](https://hub.tekton.dev/) -- Browse and install community-maintained reusable Tasks
- [Tekton Dashboard](https://tekton.dev/docs/dashboard/) -- Visual UI for monitoring and managing pipelines
- [Tekton Triggers](https://tekton.dev/docs/triggers/) -- Event-driven pipeline execution (webhook listeners, GitHub events, etc.)
- [Tekton Results](https://tekton.dev/docs/results/) -- Long-term storage and querying of pipeline run history
- [Tekton Chains](https://tekton.dev/docs/chains/) -- Supply chain security: signs TaskRun results and generates provenance attestations
- [Bundle Resolver](https://tekton.dev/docs/pipelines/bundle-resolver/) -- Resolving tasks from OCI bundles
- [Matrix](https://tekton.dev/docs/pipelines/matrix/) -- Fan-out parallelism with parameter combinations

### Guides and Tutorials

- [Getting Started with Pipelines](https://tekton.dev/docs/getting-started/pipelines/) -- Tekton's official getting-started tutorial
- [Getting Started with Triggers](https://tekton.dev/docs/getting-started/triggers/) -- Learn to trigger pipelines from Git events
- [Step-by-Step: Setting Up a CI/CD Pipeline Using Tekton](https://hayorov.me/posts/tekton-cicd-pipeline-guide/) -- Practical end-to-end walkthrough
- [How to Get Started with Tekton Pipelines](https://oneuptime.com/blog/post/2026-01-26-tekton-pipelines-guide/view) -- Beginner-friendly guide with screenshots
- [How to Configure Tekton PipelineRuns](https://oneuptime.com/blog/post/2026-02-02-tekton-pipelineruns/view) -- Deep dive into PipelineRun options
- [How to Use Tekton Workspaces](https://oneuptime.com/blog/post/2026-02-02-tekton-workspaces/view) -- Workspace patterns and backing options
- [How to Build a Reusable Tekton Task Catalog](https://oneuptime.com/blog/post/2026-02-09-tekton-task-catalog-reusable/view) -- Designing tasks for reuse across teams
- [Authentication for Tekton](https://tekton.dev/docs/pipelines/auth/) -- Configuring Git and Docker authentication
- [Kustomize Documentation](https://kustomize.io/) -- Managing Kubernetes resources with overlays

### Architecture and Comparisons

- [Tekton vs Jenkins on OpenShift](https://redhat.com/en/blog/tekton-vs-jenkins-whats-better-cicd-pipelines-red-hat-openshift) -- Red Hat's case for Kubernetes-native CI/CD
- [CI/CD Tools Comparison: GitHub Actions, Jenkins, Tekton, Argo CD](https://jiminbyun.medium.com/ci-cd-tools-comparison-github-actions-jenkins-tekton-and-argo-cd-673d205f9fa8) -- Landscape overview
- [Is Tekton Still Alive?](https://mkdev.me/posts/is-tekton-still-alive-comparing-tekton-pipelines-with-argo-workflows-argocd-and-jenkins) -- Honest comparison with Argo Workflows and Jenkins

### Related Tools

- [Prow](https://docs.prow.k8s.io/) -- Kubernetes-native CI/CD system that triggers Tekton PipelineRuns from GitHub events
- [Skaffold](https://skaffold.dev/) -- Container image build and deploy tool used in production pipelines
- [Kyverno](https://kyverno.io/) -- Kubernetes policy engine used alongside Tekton clusters
- [ArgoCD](https://argo-cd.readthedocs.io/) -- GitOps continuous delivery tool often paired with Tekton CI
- [Hierarchical Namespaces (HNC)](https://github.com/kubernetes-sigs/hierarchical-namespaces) -- Namespace hierarchy and policy inheritance

### Community and Source Code

- [Tekton GitHub Organization](https://github.com/tektoncd) -- All Tekton repositories (pipeline, triggers, dashboard, catalog, CLI)
- [Tekton Task Catalog](https://github.com/tektoncd/catalog) -- Community-contributed reusable Tasks; study these for best practices in Task design
- [Tekton Enhancement Proposals (TEPs)](https://github.com/tektoncd/community/tree/main/teps) -- Design documents for new features; useful for understanding *why* Tekton works the way it does
- [CD Foundation](https://cd.foundation/) -- The Linux Foundation project that hosts Tekton alongside Jenkins, Spinnaker, and other CI/CD projects

### Learning Path Summary

| Phase | Labs | You Can Now... |
|-------|------|---------------|
| **Beginner** | 1-4 | Write Tasks, pass params, chain results, use workspaces |
| **Intermediate** | 5 | Build CI pipelines with parallel execution and DAG dependencies |
| **Advanced** | 6-10 | Use conditional logic, cleanup, retries, sidecars, and matrix parallelism |
| **Production-Ready** | 11-14 | Configure RBAC/secrets, use bundle resolvers, manage Tekton with Kustomize |
| **Capstone** | Capstone | Build a real cross-compilation pipeline tying all concepts together |
| **Expert** | Deep Dive sections | Understand Prow, approval workflows, signing, Tekton config, and all production patterns |

After completing all labs and the capstone, you'll have hands-on experience with every Tekton concept used in production. The "Production Patterns Deep Dive" section covers the remaining organizational patterns (Prow, Slack, approvals, signing, ArgoCD integration) that require infrastructure beyond a local Kind cluster.
