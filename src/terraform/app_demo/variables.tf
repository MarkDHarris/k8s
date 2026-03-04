# =============================================================================
# APP DEMO: variables.tf
# =============================================================================
# Input variables for the demo application deployment.
#
# TERRAFORM CONCEPT: Decoupling via Variables
# By parameterizing the kubeconfig path and context, this module is not
# hard-coded to any specific cluster. You could point it at a different Kind
# cluster, a remote cluster, or even a cloud-managed cluster by changing
# these variables.
# =============================================================================


variable "kubeconfig_path" {
  description = <<-EOT
    Path to the kubeconfig file for cluster access. Kind automatically
    updates ~/.kube/config when you create a cluster.
    
    Override this if you wrote the kubeconfig to a custom location:
      terraform apply -var='kubeconfig_path=/tmp/my-kind-config'
    
    TERRAFORM CONCEPT: pathexpand()
    The "~" in the default is expanded by Terraform's pathexpand() function.
    If you pass a custom path with "~", wrap it:
      kubeconfig_path = pathexpand("~/custom-config")
  EOT
  type    = string
  default = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = <<-EOT
    The kubectl context name to use for connecting to the cluster.
    Kind clusters use the format "kind-<cluster_name>".
    
    This must match the cluster_name used in ../cluster/terraform.tfvars.
    For example, if cluster_name = "dev", use context "kind-dev".
  EOT
  type    = string
  default = "kind-dev"
}
