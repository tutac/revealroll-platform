# Runbook — `SiteDown`, `PodCrashLooping`, `PodNotReady`, `PrometheusTargetDown`

## What this alert means

Something a user depends on is not answering. `SiteDown` means an HTTP probe to the public
URL failed twice in a row; the others mean a pod or a scrape target is unhealthy, which
usually precedes or explains it.

## Impact

`SiteDown` on `stg.revealroll.com` — staging is fully unavailable. On `argocd.stg` or
`grafana.stg` — you have lost a tool, not the service, so it is urgent but not an outage.

## Triage

Run these in order. Most outages here are answered by step 2 or 3.

```bash
# 0. Do you have cluster access at all?
make tunnel                                  # separate terminal, leave it open
export KUBECONFIG=~/.kube/revealroll-staging.yaml

# 1. Is it actually down, or is it the monitoring?
./scripts/smoke.sh                           # passes → the alert is wrong, go to step 6
```

```bash
# 2. Does Git agree with the cluster?
kubectl get applications -n argocd
#    OutOfSync/Degraded → read the message: kubectl describe app <name> -n argocd
```

```bash
# 3. What is not Running?
kubectl get pods -A | grep -v 'Running\|Completed'
kubectl describe pod <pod> -n <ns>           # read EVENTS, not just status
#    ImagePullBackOff   → tag or registry credential. Check secrets/staging/ghcr-sealed.yaml
#    CrashLoopBackOff   → the app is failing to start; go to step 4
#    Pending            → nothing can schedule it; go to step 5
```

```bash
# 4. Why is it crashing?
kubectl logs <pod> -n revealroll --previous   # --previous = the run that died
#    Missing env var → the SealedSecret did not apply: kubectl get secret revealroll-env -n revealroll
```

```bash
# 5. Can anything schedule?
kubectl describe node | grep -A8 'Allocated resources'
kubectl get events -A --sort-by=.lastTimestamp | tail -20
#    Insufficient memory → see disk-pressure.md / node-reboot.md
```

```bash
# 6. The site is refused at the TCP level, but the cluster is healthy
#    (this is the 2026-08-17 failure — see .claude/memory/incidents.md)
nc -z <node-ip> 443 || echo "nothing listening"
ssh deploy@<node-ip> 'sudo nft list table ip nat | grep -c CNI-HOSTPORT'
#    0 → the CNI hostPort rules were wiped. Mitigation below.
```

## Mitigation — stop the bleeding first

```bash
# hostPort rules gone (step 6): recreate the ingress pod so the CNI rewrites them
kubectl rollout restart daemonset ingress-nginx-controller -n ingress-nginx

# a bad release: revert the commit that bumped the tag, and let Argo do the rest
git revert <sha> && git push        # see rollback.md

# a wedged pod, cause unknown and the site is down NOW
kubectl rollout restart deployment revealroll -n revealroll
```

Then confirm with `./scripts/smoke.sh` before you start diagnosing properly.

## Escalation / if that didn't work

1. `kubectl logs -n ingress-nginx ds/ingress-nginx-controller --tail=100` — is nginx
   rejecting the route, or never receiving the request?
2. `kubectl get certificate,order,challenge -A` — TLS failure looks like a site outage in
   a browser. See `cert-not-issuing.md`.
3. Host level: `ssh deploy@<node-ip>`, then `df -h`, `free -m`,
   `journalctl -u k3s -n 100`. On a single node a full disk presents as ten unrelated
   Kubernetes symptoms at once.
4. If k3s itself is unhealthy and the node needs restarting → `node-reboot.md`.

**Write it up in `.claude/memory/incidents.md` afterwards, including how long it took you
to notice.** That number is the point.
