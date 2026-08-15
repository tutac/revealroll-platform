# The two ClusterIssuers, delivered as a local Helm chart rather than kubernetes_manifest.
#
# WHY, because this looks odd and the reason is the whole lesson:
#
# `kubernetes_manifest` reads the target resource's schema from the cluster at PLAN time.
# The ClusterIssuer CRD does not exist until cert-manager is applied. So on a fresh
# cluster, `terraform plan` fails before it can propose creating the thing that would fix
# it -- and depends_on cannot help, because the dependency is on the plan, not the apply.
# This is a genuine, well-known chicken-and-egg in the kubernetes provider, not a mistake.
#
# The documented workaround is a two-pass apply: `terraform apply -target=helm_release.cert_manager`
# first, then a normal apply. It works. It is also a footgun: it means a rebuilt cluster
# cannot be brought up by `terraform apply` alone, and Stage 10's destroy-and-restore drill
# is exactly the moment nobody remembers the special first pass.
#
# helm_release does not introspect CRDs at plan time -- it renders templates and hands
# YAML to the API server during apply. So packaging two small manifests as a chart buys a
# single-command, repeatable bootstrap. The cost is one directory of Helm boilerplate,
# which is a good trade for a bootstrap that survives being forgotten for six months.

resource "helm_release" "cluster_issuers" {
  name  = "cluster-issuers"
  chart = "${path.module}/charts/cluster-issuers"

  # cert-manager's namespace, though ClusterIssuers are cluster-scoped -- the namespace
  # here only decides where Helm keeps its release metadata.
  namespace = helm_release.cert_manager.namespace

  # Ordering still matters at APPLY time: the CRD must exist before the objects. This is
  # the dependency that helm_release CAN express, because it is not a plan-time one.
  depends_on = [helm_release.cert_manager]

  values = [yamlencode({
    email            = var.acme_email
    ingressClassName = "nginx"

    # Two issuers, always. letsencrypt-staging has generous rate limits and issues certs
    # no browser trusts; letsencrypt-prod issues real ones and will lock you out for an
    # hour after 5 failed validations. Debug against staging, switch to prod when the
    # challenge succeeds -- that is what task 04.8 is for.
    issuers = [
      {
        name   = "letsencrypt-staging"
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
      },
      {
        name   = "letsencrypt-prod"
        server = "https://acme-v02.api.letsencrypt.org/directory"
      },
    ]
  })]
}
