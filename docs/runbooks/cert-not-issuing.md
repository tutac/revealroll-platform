# Runbook — `SiteCertExpiringSoon`

## What this alert means

A TLS certificate is inside 21 days of expiry. cert-manager renews at 30 days, so if this
fired, **renewal has already failed at least once, silently.**

## Impact

None yet. At expiry, every browser shows a full-page security warning and the site is
effectively down — including `argocd.stg`, which is how you would fix it.

## Triage

```bash
export KUBECONFIG=~/.kube/revealroll-staging.yaml

# 1. Which certificate, and what does it say about itself?
kubectl get certificate -A
kubectl describe certificate <name> -n <ns>        # read the Conditions and Events

# 2. Renewal is a chain: Certificate → CertificateRequest → Order → Challenge.
#    Whichever is missing or stuck is where it broke.
kubectl get certificaterequest,order,challenge -A

# 3. A Challenge stuck in Pending is nearly always one of two things:
kubectl describe challenge <name> -n <ns>
#    "no such host" / NXDOMAIN     → DNS. Check Namecheap: *.stg must point at the node IP
#    connection timeout on :80     → HTTP-01 needs port 80 reachable from the internet
```

```bash
# 4. Prove the ACME path works from outside
curl -sI http://<hostname>/.well-known/acme-challenge/test | head -1
#    Refused/timeout → the same hostPort problem as app-down.md step 6

# 5. cert-manager's own view
kubectl logs -n cert-manager deploy/cert-manager --tail=50 | grep -i error
```

## Mitigation

```bash
# Force a renewal once the underlying cause is fixed
kubectl delete certificaterequest <name> -n <ns>   # cert-manager recreates it

# Or delete the Secret to restart the whole chain (the site serves the OLD cert until
# the new one is issued, so this is safe while the current cert is still valid)
kubectl delete secret <tls-secret> -n <ns>
```

**Watch the rate limits.** Let's Encrypt allows 5 duplicate certificates per week. If you
are iterating, switch the ingress annotation to `letsencrypt-staging` first — untrusted in
browsers, unlimited in practice — and switch back once issuance succeeds.

## Escalation / if that didn't work

1. `kubectl get clusterissuer` — is `letsencrypt-prod` Ready? An expired ACME account
   registration blocks every certificate at once.
2. Rate-limited already: wait it out on `letsencrypt-staging`, and set a calendar reminder
   for the real switch back. Do not "try again" — that consumes the remaining quota.
3. If expiry is imminent (< 48h) and issuance is still failing, the fastest safe fallback
   is putting the hostname behind Cloudflare's proxy for its edge certificate. Note it in
   the incident; it is a workaround, not a fix.

## Prevention

The 21-day threshold is deliberately generous: it gives ~3 weeks to notice, diagnose and
survive a rate limit. Do not lower it to reduce noise — if it is noisy, renewal is broken.
