# =============================================================================
# CLUSTER MODULE: outputs.tf
# =============================================================================
# Outputs displayed after `terraform apply` and queryable via `terraform output`.
#
# TERRAFORM CONCEPT: Root Module Outputs
# Root module outputs serve three purposes:
#   1. Display useful information to the operator after apply
#   2. Expose values for use by other Terraform configurations (remote state)
#   3. Provide machine-readable data for scripts (terraform output -json)
#
# IMPORTANT: The cluster_context output is used by the sibling app_demo/
# terraform to connect to this cluster. After running `terraform apply` here,
# note the cluster_context value and use it when configuring app_demo/.
# =============================================================================


output "cluster_endpoint" {
  description = "Kubernetes API server endpoint URL for the Kind cluster"
  value       = module.k8s_cluster.endpoint
}

output "cluster_name" {
  description = "Name of the Kind cluster (kubectl context: kind-<name>)"
  value       = var.cluster_name
}

output "cluster_context" {
  description = "kubectl context name for this cluster (use with app_demo/)"
  value       = "kind-${var.cluster_name}"
}

output "kubeconfig" {
  description = <<-EOT
    Full kubeconfig YAML for the cluster. Write to a file to use with kubectl:
      terraform output -raw kubeconfig > ~/.kube/kind-config
      export KUBECONFIG=~/.kube/kind-config
      kubectl get nodes
  EOT
  value     = module.k8s_cluster.kubeconfig
  sensitive = true
}

output "client_certificate" {
  description = "TLS client certificate for authenticating to the cluster"
  value       = module.k8s_cluster.client_certificate
  sensitive   = true
}

output "client_key" {
  description = "TLS client private key for authenticating to the cluster"
  value       = module.k8s_cluster.client_key
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate for verifying API server identity"
  value       = module.k8s_cluster.cluster_ca_certificate
  sensitive   = true
}

output "node_count" {
  description = "Total number of nodes in the cluster"
  value       = var.control_plane_count + var.worker_count
}

output "instructions" {
  description = "Quick-start instructions displayed after cluster creation"
  value       = <<-EOT

    ╔══════════════════════════════════════════════════════════════════╗
    ║  Kind Cluster '${var.cluster_name}' created successfully!            ║
    ╚══════════════════════════════════════════════════════════════════╝

    TOPOLOGY: ${var.control_plane_count} control-plane + ${var.worker_count} worker = ${var.control_plane_count + var.worker_count} nodes
    ─────────────────────────────────────────────────────────────────

    QUICK START:
    ─────────────────────────────────────────────────────────────────
    1. Set kubectl context:
       kubectl cluster-info --context kind-${var.cluster_name}

    2. Check all nodes are Ready (expect ${var.control_plane_count + var.worker_count} nodes):
       kubectl get nodes -o wide

    3. Verify control-plane nodes (expect ${var.control_plane_count}):
       kubectl get nodes -l node-role.kubernetes.io/control-plane

    4. Check node labels:
       kubectl get nodes --show-labels
${var.worker_count >= 2 ? "\n    5. Check taints on the GPU worker:\n       kubectl describe nodes | grep -A2 Taints\n" : ""}
    6. Export kubeconfig to a file:
       terraform output -raw kubeconfig > ~/.kube/kind-${var.cluster_name}

    DEPLOY THE DEMO APP:
    ─────────────────────────────────────────────────────────────────
    To deploy a demo NGINX app with ingress, run the sibling terraform:
       cd ../app_demo
       terraform init
       terraform apply

    USEFUL COMMANDS:
    ─────────────────────────────────────────────────────────────────
    - View cluster: kubectl get all -A
    - View events:  kubectl get events -A --sort-by='.lastTimestamp'
    - Delete:       terraform destroy
    - Recreate:     terraform destroy && terraform apply

  EOT
}
