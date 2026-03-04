# =============================================================================
# APP DEMO: main.tf
# =============================================================================
# Deploys a demo NGINX web application with full ingress routing into an
# EXISTING Kind cluster created by the sibling ../cluster/ terraform.
#
# WHAT THIS CREATES:
#   1. NGINX Ingress Controller (via Helm)
#   2. Demo namespace
#   3. NGINX Deployment (2 replicas with health checks)
#   4. ClusterIP Service
#   5. Ingress resource routing localhost:80 → NGINX pods
#
# PREREQUISITES:
#   The Kind cluster must already be running. Deploy it first:
#     cd ../cluster && terraform init && terraform apply
#
# USAGE:
#   cd app_demo/
#   terraform init
#   terraform apply
#   curl http://localhost
#
# TRAFFIC FLOW:
#   Browser → localhost:80 → Docker port mapping → Kind node:80 →
#   NGINX Ingress Controller → Kubernetes Service → Pod
#
# TERRAFORM CONCEPT: Separate State Files
# By splitting cluster and application into separate Terraform root modules,
# each has its own state file. This means:
#   - You can destroy and redeploy the app without touching the cluster
#   - You can recreate the cluster without managing app state
#   - Different teams can own different root modules
#   - Blast radius of changes is reduced
#
# TERRAFORM CONCEPT: Provider Configuration via kubeconfig
# Instead of passing raw certificates (as you would with remote state), this
# module connects to the cluster using the kubeconfig file that Kind
# automatically maintains. This is simpler and mirrors how developers
# actually interact with clusters using kubectl.
# =============================================================================


# =============================================================================
# SECTION 1: Provider Configuration
# =============================================================================
# Connect the kubernetes and helm providers to the Kind cluster using the
# kubeconfig file. Kind automatically updates ~/.kube/config when you create
# a cluster, so the default values work out of the box.
#
# TERRAFORM CONCEPT: config_path vs host/client_certificate
# There are two ways to configure the kubernetes/helm providers:
#   1. config_path + config_context  — reads from a kubeconfig file (simpler)
#   2. host + client_certificate + client_key + cluster_ca_certificate (explicit)
# We use option 1 here because it's simpler and doesn't require wiring
# outputs between root modules. Option 2 is used when you need tighter
# control, such as in CI/CD pipelines or when using terraform_remote_state.
# =============================================================================

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kubeconfig_context
  }
}


# =============================================================================
# SECTION 2: NGINX Ingress Controller (Helm)
# =============================================================================
# An Ingress Controller processes Kubernetes Ingress resources and routes
# external HTTP/HTTPS traffic to backend Services.
#
# WHY NGINX INGRESS ON KIND?
# Kind doesn't have a cloud load balancer, so we use NodePort + hostPort
# to expose the Ingress Controller. The extra_port_mappings on the cluster's
# control-plane node forward ports 80/443 from your machine into the cluster
# where NGINX listens and routes traffic.
# =============================================================================

resource "helm_release" "ingress_nginx" {
  name = "ingress-nginx"

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"

  namespace        = "ingress-nginx"
  create_namespace = true

  # Use NodePort instead of LoadBalancer (Kind has no cloud LB).
  set {
    name  = "controller.service.type"
    value = "NodePort"
  }

  # Enable hostPort so NGINX binds directly to the node's ports 80/443.
  set {
    name  = "controller.hostPort.enabled"
    value = "true"
  }

  # Schedule only on the node labeled "ingress-ready=true" (the control-plane
  # node that has extra_port_mappings for ports 80/443).
  set {
    name  = "controller.nodeSelector.ingress-ready"
    value = "true"
    type  = "string"
  }

  # Tolerate the control-plane taint so the controller can be scheduled there.
  set {
    name  = "controller.tolerations[0].key"
    value = "node-role.kubernetes.io/control-plane"
  }
  set {
    name  = "controller.tolerations[0].operator"
    value = "Exists"
  }
  set {
    name  = "controller.tolerations[0].effect"
    value = "NoSchedule"
  }

  set {
    name  = "controller.admissionWebhooks.patch.nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }
}


# =============================================================================
# SECTION 3: Demo NGINX Web Server
# =============================================================================
# A simple NGINX web server exposed via Ingress. This demonstrates the full
# Kubernetes deployment pattern:
#
#   Deployment  → Creates and manages Pod replicas
#   Service     → Stable internal DNS name + load balancing across replicas
#   Ingress     → External HTTP routing from localhost to the Service
#
# WHY ClusterIP (not NodePort or LoadBalancer)?
# The Ingress Controller handles external traffic on ports 80/443. Our
# Service only needs to be reachable inside the cluster. This is the
# standard pattern: external traffic → Ingress → ClusterIP Service → Pods.
# =============================================================================

resource "kubernetes_namespace" "demo" {
  metadata {
    name = "demo"
  }
}

resource "kubernetes_deployment_v1" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace.demo.metadata[0].name
    labels = {
      app = "nginx"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "nginx"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }

      spec {
        container {
          name  = "nginx"
          image = "nginx:stable"

          port {
            container_port = 80
            protocol       = "TCP"
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 3
            period_seconds        = 5
          }
        }
      }
    }
  }

  depends_on = [helm_release.ingress_nginx]
}

resource "kubernetes_service_v1" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace.demo.metadata[0].name
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "nginx"
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_ingress_v1" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace.demo.metadata[0].name
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.nginx.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
