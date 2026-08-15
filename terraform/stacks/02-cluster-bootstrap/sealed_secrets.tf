# sealed-secrets: the controller holds an RSA private key; `kubeseal` encrypts a Secret
# against the matching public key, producing a SealedSecret that is safe to commit. Argo CD
# syncs the SealedSecret from Git and the controller decrypts it into a real Secret in the
# cluster. That is what makes "no plaintext secret ever enters this repository" workable
# rather than aspirational.
#
# NOTE the repository URL: bitnami.github.io, NOT bitnami-labs.github.io. The -labs Pages
# site now returns "Site not found"; the project itself is alive and the chart moved.

resource "helm_release" "sealed_secrets" {
  name       = "sealed-secrets"
  repository = "https://bitnami.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  version    = var.sealed_secrets_chart_version

  # kube-system, not a namespace of its own, and the name below is not cosmetic:
  # the `kubeseal` CLI defaults to --controller-namespace kube-system and
  # --controller-name sealed-secrets-controller. Matching those defaults means
  # scripts/seal-env.sh and every ad-hoc kubeseal you ever type just work. Installing
  # this anywhere else costs two flags on every single invocation, forever, and the
  # error when you forget them ("cannot fetch certificate") does not mention namespaces.
  namespace = "kube-system"

  wait    = true
  timeout = 600

  values = [yamlencode({
    fullnameOverride = "sealed-secrets-controller"

    metrics = {
      serviceMonitor = {
        # Stage 08, once the Prometheus CRDs exist.
        enabled = false
      }
    }

    resources = {
      requests = {
        cpu    = "10m"
        memory = "64Mi"
      }
      limits = {
        memory = "128Mi"
      }
    }
  })]
}
