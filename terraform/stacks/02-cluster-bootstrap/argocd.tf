# Argo CD -- the last thing Terraform installs into this cluster.
#
# After this applies, every further Kubernetes object arrives as a commit. If you find
# yourself adding a fifth helm_release here, the layer is wrong (see CLAUDE.md).

locals {
  argocd_host = "argocd.${var.base_domain}"
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  namespace        = "argocd"
  create_namespace = true

  wait = true
  # Longer than the others on purpose: this pulls seven images onto a node with a single
  # 4-vCPU uplink, and the application-controller is slow to report ready.
  timeout = 900

  # Both are apply-time dependencies with real failure modes: without ingress-nginx the
  # Ingress below matches no controller and is silently inert, and without the issuers the
  # cert-manager annotation names a ClusterIssuer that does not exist -- which surfaces as
  # a Certificate stuck in `False`, not as an error here.
  depends_on = [
    helm_release.ingress_nginx,
    helm_release.cluster_issuers,
  ]

  values = [yamlencode({
    global = {
      domain = local.argocd_host
    }

    configs = {
      params = {
        # Argo CD's server speaks TLS itself by default. Behind nginx that means TLS
        # terminated twice -- nginx would have to re-encrypt to a certificate it does not
        # trust, and you get a 502 that looks like Argo CD being down. `server.insecure`
        # makes it serve plain HTTP inside the cluster; the only TLS is the real
        # Let's Encrypt certificate nginx presents to the browser.
        "server.insecure" = true
      }
    }

    server = {
      ingress = {
        enabled          = true
        controller       = "generic"
        ingressClassName = "nginx"
        hostname         = local.argocd_host
        path             = "/"
        pathType         = "Prefix"

        # With tls: true the chart writes a tls block referencing the FIXED secret name
        # `argocd-server-tls` -- not <hostname>-tls. cert-manager sees the annotation
        # below, solves HTTP-01, and populates exactly that secret.
        tls = true

        annotations = {
          "cert-manager.io/cluster-issuer" = var.acme_issuer
        }
      }
    }

    # No SSO, so dex is seven pods' worth of nothing. Notifications belong to a workflow
    # that does not exist yet. Both are trivially re-enabled when they earn their memory
    # on an 8 GB single node.
    dex = {
      enabled = false
    }
    notifications = {
      enabled = false
    }
  })]
}
