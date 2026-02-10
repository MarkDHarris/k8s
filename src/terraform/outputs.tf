# =============================================================================
# ROOT MODULE: outputs.tf
# =============================================================================
# Outputs defined here are displayed after `terraform apply` completes and
# can be queried anytime with `terraform output`.
#
# TERRAFORM CONCEPT: Root Module Outputs
# Root module outputs serve three purposes:
#   1. Display useful information to the operator after apply
#   2. Expose values for use by other Terraform configurations (remote state)
#   3. Provide machine-readable data for scripts (terraform output -json)
#
# Outputs marked `sensitive = true` are hidden in CLI output but accessible
# via `terraform output -raw <name>` or `terraform output -json`.
# =============================================================================


# -----------------------------------------------------------------------------
# Cluster Connection Details
# -----------------------------------------------------------------------------

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint URL for the Kind cluster"
  value       = module.k8s_cluster.endpoint
}

output "cluster_name" {
  description = "Name of the Kind cluster (kubectl context: kind-<name>)"
  value       = var.cluster_name
}

output "kubeconfig" {
  description = <<-EOT
    Full kubeconfig YAML for the cluster. Write to a file to use with kubectl:
      terraform output -raw kubeconfig > ~/.kube/kind-config
      export KUBECONFIG=~/.kube/kind-config
      kubectl get nodes
  EOT
  value       = module.k8s_cluster.kubeconfig
  sensitive   = true
}


# -----------------------------------------------------------------------------
# Demo NGINX Web Server
# -----------------------------------------------------------------------------

output "nginx_url" {
  description = "URL to reach the demo NGINX web server from the host"
  value       = "http://localhost"
}


# -----------------------------------------------------------------------------
# Post-Apply Instructions
# -----------------------------------------------------------------------------

output "instructions" {
  description = "Quick-start instructions displayed after cluster creation"
  value       = <<-EOT

    ╔══════════════════════════════════════════════════════════════════╗
    ║  Kind Cluster '${var.cluster_name}' created successfully!            ║
    ╚══════════════════════════════════════════════════════════════════╝

    QUICK START:
    ─────────────────────────────────────────────────────────────────
    1. Set kubectl context:
       kubectl cluster-info --context kind-${var.cluster_name}

    2. Check all nodes are Ready:
       kubectl get nodes -o wide

    3. Verify HA (you should see 2 control-plane nodes):
       kubectl get nodes -l node-role.kubernetes.io/control-plane

    4. Check node labels:
       kubectl get nodes --show-labels

    5. Check taints on the GPU worker:
       kubectl describe nodes | grep -A2 Taints

    6. Test the demo NGINX web server:
       kubectl -n demo get pods
       curl http://localhost

    7. Export kubeconfig to a file:
       terraform output -raw kubeconfig > ~/.kube/kind-${var.cluster_name}

    USEFUL COMMANDS:
    ─────────────────────────────────────────────────────────────────
    - View cluster: kubectl get all -A
    - View events:  kubectl get events -A --sort-by='.lastTimestamp'
    - Delete:       terraform destroy
    - Recreate:     terraform destroy && terraform apply

  EOT
}
