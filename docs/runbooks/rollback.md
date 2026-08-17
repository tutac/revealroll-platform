# Runbook — Rolling back

Not tied to one alert. This is the answer to "the last change broke it", and it is
deliberately the same operation you already know: `git revert`.

## The rule

**Roll back first, diagnose second.** A revert is cheap and reversible. Debugging a broken
release while it is serving users is neither.

## Rolling back the application

The deployed image tag is one line in `charts/revealroll/values-staging.yaml`, written by
CI. Reverting that commit reverts the deploy.

```bash
git log --oneline -- charts/revealroll/values-staging.yaml    # find the bump commit
git revert <sha>
git push
```

Argo CD picks it up within its sync interval (3 min). To not wait:

```bash
export KUBECONFIG=~/.kube/revealroll-staging.yaml
kubectl annotate app revealroll -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl rollout status deployment revealroll -n revealroll --timeout=120s
./scripts/smoke.sh
```

**Do not** `kubectl set image` or `helm rollback`. `selfHeal` will revert your change back
to what Git says within three minutes, and you will lose time to a fight you cannot win.

## Rolling back a platform component

Same operation, different file — the chart version or values in `gitops/apps/`:

```bash
git revert <sha> && git push
```

If a chart upgrade left CRDs behind, reverting the version does not remove them. Usually
harmless; if a CRD schema change is the actual problem, delete the offending CR (not the
CRD) and let Argo recreate it.

## If Argo CD itself cannot reconcile

The recovery path, in order:

```bash
git revert <bad-sha> && git push
kubectl apply -f gitops/projects/            # AppProjects must exist first
kubectl apply -f gitops/root-app.yaml        # force the root app to a known state
argocd app sync root-app --force
```

This is the only sanctioned manual apply in the repo (decision 013).

## Emergency actions that are allowed

Per `CLAUDE.md`, during an incident these are legitimate even though they bypass Git —
because they are faster than a commit and are reverted by the next sync anyway:

```bash
kubectl scale deployment revealroll -n revealroll --replicas=4    # absorb load
kubectl rollout restart deployment revealroll -n revealroll       # recycle wedged pods
kubectl cordon <node>                                             # stop scheduling
```

**Put the change into Git afterwards, or undo it.** An emergency change that outlives the
emergency is drift, and `selfHeal` will remove it at a moment you are not watching.

## Verify a rollback actually happened

```bash
kubectl get deployment revealroll -n revealroll \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl get applications -n argocd            # Synced/Healthy
./scripts/smoke.sh
```

Then write it up in `.claude/memory/incidents.md` — what shipped, what broke, and what
would have caught it before it reached staging.
