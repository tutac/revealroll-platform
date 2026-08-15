# ingress-nginx, bound directly to the node's ports 80 and 443 via hostPort.
#
# There is no cloud load balancer here and k3s was installed with --disable=servicelb, so
# nothing exists to hand a Service an external IP. hostPort is the honest answer on a
# single node: the DaemonSet pod binds :80/:443 on the host itself, and the wildcard
# *.stg A record points straight at it.
#
# The consequence to remember: only ONE pod can hold those ports per node. That is why
# this is a DaemonSet with no replica count, and why a second ingress controller (or the
# Traefik k3s ships with, which is why we disabled it) would fail to start rather than
# load balance.

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_nginx_chart_version

  namespace        = "ingress-nginx"
  create_namespace = true

  # Bootstrap is allowed to be slow; it is not allowed to be ambiguous. Waiting means a
  # failed apply reports the real reason instead of succeeding and leaving you to find
  # out from a 502 later.
  wait    = true
  timeout = 600

  values = [yamlencode({
    controller = {
      # One pod per node, owning the host's ports.
      kind = "DaemonSet"

      hostPort = {
        enabled = true
        ports = {
          http  = 80
          https = 443
        }
      }

      # ClusterIP, not LoadBalancer: with servicelb disabled a LoadBalancer Service would
      # sit <pending> forever. Traffic arrives via hostPort, not through this Service.
      #
      # Note there is deliberately no externalTrafficPolicy here. It only applies to
      # NodePort/LoadBalancer Services, and with hostPort the client's real address is
      # already preserved -- setting it would be cargo cult.
      service = {
        type = "ClusterIP"
      }

      ingressClassResource = {
        name    = "nginx"
        enabled = true
        # Ingresses that omit ingressClassName still work. On a single-controller cluster
        # that is convenience; the day a second controller exists, remove this.
        default = true
      }

      config = {
        # k3s terminates nothing in front of us, but keep the parsing honest for when
        # something eventually does.
        use-forwarded-headers = "true"
        # Default is 1m and Next.js uploads exceed it. Raise once, here, rather than
        # per-Ingress annotations scattered across charts.
        proxy-body-size = "16m"
      }

      # Scrape target for Stage 08. Enabling the port now costs nothing and means the
      # ServiceMonitor later is a one-line change rather than a chart upgrade.
      metrics = {
        enabled = true
      }

      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          memory = "512Mi"
        }
      }
    }
  })]
}
