# =============================================================================
# APP DEMO: outputs.tf
# =============================================================================
# Outputs displayed after the demo application is deployed.
# =============================================================================


output "nginx_url" {
  description = "URL to reach the demo NGINX web server from the host"
  value       = "http://localhost"
}

output "instructions" {
  description = "Post-deploy instructions for verifying the demo application"
  value       = <<-EOT

    ╔══════════════════════════════════════════════════════════════════╗
    ║  Demo NGINX App deployed successfully!                          ║
    ╚══════════════════════════════════════════════════════════════════╝

    VERIFY:
    ─────────────────────────────────────────────────────────────────
    1. Check the demo pods are running:
       kubectl -n demo get pods

    2. Check the ingress controller is running:
       kubectl -n ingress-nginx get pods

    3. Test the demo app (wait ~30s for pods to be ready):
       curl http://localhost

    4. View all resources in the demo namespace:
       kubectl -n demo get all

    CLEANUP:
    ─────────────────────────────────────────────────────────────────
    To remove only the demo app (keep the cluster):
       terraform destroy

    To remove everything (cluster + app):
       terraform destroy              # Remove app first
       cd ../cluster && terraform destroy  # Then remove cluster

  EOT
}
