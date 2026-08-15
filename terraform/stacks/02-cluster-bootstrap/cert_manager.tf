# cert-manager: watches Ingress objects for a cert-manager.io/cluster-issuer annotation,
# requests a certificate from Let's Encrypt, proves control of the hostname over HTTP-01,
# and renews it forever. Without this every hostname in this cluster is plain HTTP.

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_chart_version

  namespace        = "cert-manager"
  create_namespace = true

  wait    = true
  timeout = 600

  values = [yamlencode({
    # Helm installs the CRDs as part of the release. The alternative -- applying them
    # separately -- means an upgrade can leave CRDs and controller at different versions,
    # which fails in ways that look like cert-manager being broken rather than mismatched.
    #
    # `installCRDs` was the old spelling; it is deprecated from chart 1.15 onward. This
    # chart is v1.21, so `crds.enabled` is correct.
    crds = {
      enabled = true
      # Keep CRDs if the release is ever removed. Deleting a CRD deletes every object of
      # that kind cluster-wide -- every Certificate and every issued cert with it.
      keep = true
    }

    # Scrape target for Stage 08. The ServiceMonitor stays off until the Prometheus CRDs
    # exist; turning it on now would fail the apply for the same reason the ClusterIssuers
    # below need their own release.
    prometheus = {
      enabled = true
      servicemonitor = {
        enabled = false
      }
    }

    resources = {
      requests = {
        cpu    = "10m"
        memory = "64Mi"
      }
      limits = {
        memory = "256Mi"
      }
    }
  })]
}
