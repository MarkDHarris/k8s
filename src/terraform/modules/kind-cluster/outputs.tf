# =============================================================================
# MODULE: kind-cluster -- outputs.tf
# =============================================================================
# Outputs are the "return values" of a Terraform module. After the kind_cluster
# resource is created, these computed attributes become available to the
# calling (root) module.
#
# These outputs are essential for configuring other providers (kubernetes, helm)
# to communicate with the newly created cluster. Without them, you'd have to
# manually extract connection details from the kubeconfig file.
#
# TERRAFORM CONCEPT: Output Sensitivity
# Outputs marked `sensitive = true` are redacted in CLI output (shown as
# "<sensitive>") but are still available in state and to other modules.
# This prevents accidental exposure of credentials in CI/CD logs.
#
# ALL COMPUTED ATTRIBUTES from kind_cluster resource:
#   - endpoint              : The Kubernetes API server URL (e.g., https://127.0.0.1:6443)
#   - client_certificate    : Base64-encoded PEM client certificate for TLS auth
#   - client_key            : Base64-encoded PEM client private key for TLS auth
#   - cluster_ca_certificate: Base64-encoded PEM CA certificate to verify the API server
#   - kubeconfig            : Complete kubeconfig YAML string for kubectl access
# =============================================================================


output "endpoint" {
  description = <<-EOT
    Kubernetes API server endpoint URL (e.g., "https://127.0.0.1:6443").
    Use this to configure the kubernetes and helm providers' "host" argument.
  EOT
  value       = kind_cluster.this.endpoint
}

output "client_certificate" {
  description = <<-EOT
    Base64-encoded PEM client certificate for authenticating to the cluster.
    This is the TLS client cert that proves identity to the API server.
    Used in provider configuration: client_certificate = module.x.client_certificate
  EOT
  value       = kind_cluster.this.client_certificate
  sensitive   = true # Contains authentication credentials
}

output "client_key" {
  description = <<-EOT
    Base64-encoded PEM client private key for authenticating to the cluster.
    This is the private key paired with client_certificate for mutual TLS.
    NEVER expose this value in logs or version control.
  EOT
  value       = kind_cluster.this.client_key
  sensitive   = true # Contains authentication credentials -- must be protected
}

output "cluster_ca_certificate" {
  description = <<-EOT
    Base64-encoded PEM CA certificate used to verify the API server's identity.
    The client uses this to confirm it's talking to the real cluster and not
    a man-in-the-middle. Used in provider configuration:
      cluster_ca_certificate = module.x.cluster_ca_certificate
  EOT
  value       = kind_cluster.this.cluster_ca_certificate
  sensitive   = true # Part of the cluster's trust chain
}

output "kubeconfig" {
  description = <<-EOT
    Complete kubeconfig YAML string for the cluster. Contains all connection
    details (server URL, certs, keys) needed for kubectl access.
    
    You can write this to a file and use it with:
      export KUBECONFIG=/path/to/kubeconfig
      kubectl get nodes
    
    Or use it programmatically in Terraform with yamldecode().
  EOT
  value       = kind_cluster.this.kubeconfig
  sensitive   = true # Contains embedded certificates and keys
}

output "cluster_name" {
  description = <<-EOT
    The name of the Kind cluster that was created. Useful for passing to
    the kind_load resource to load Docker images into this specific cluster.
    The kubectl context will be "kind-<cluster_name>".
  EOT
  value       = kind_cluster.this.name
}
