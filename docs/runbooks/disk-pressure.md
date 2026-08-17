# Runbook — `NodeDiskFillingUp`, `NodeDiskWillFillIn24h`

## What this alert means

The root filesystem on the single node is running out of space. `WillFillIn24h` is the
early warning (still a chore); `FillingUp` at under 15% is the emergency.

## Impact

Below ~10% free, kubelet starts evicting pods and refuses to schedule new ones. On a
single node that means the site goes down, Argo CD cannot fix it, and the failure presents
as ten unrelated Kubernetes symptoms none of which mention the disk. **Assume any bizarre
cluster behaviour is a full disk until you have checked.**

## Triage

```bash
ssh deploy@<node-ip>
df -h /                                     # how bad, and how fast
sudo du -xh --max-depth=1 / 2>/dev/null | sort -rh | head -10
```

The usual culprits, in the order they are usually guilty:

```bash
# 1. Container images — each Next.js image is ~400 MB and old tags linger
sudo k3s crictl images | wc -l
sudo du -sh /var/lib/rancher/k3s/agent/containerd

# 2. Prometheus / Loki PVCs (local-path = ordinary directories on this disk)
sudo du -sh /var/lib/rancher/k3s/storage/*

# 3. Journal logs
journalctl --disk-usage
```

## Mitigation

```bash
# 1. Reclaim unused images — safest and usually enough
sudo k3s crictl rmi --prune

# 2. Trim the journal
sudo journalctl --vacuum-size=200M

# 3. Loki or Prometheus growing past its budget: retention is misconfigured, not "big".
#    Check that BOTH settings are present — retention_period alone is a silent no-op:
kubectl -n monitoring get cm loki -o jsonpath='{.data.config\.yaml}' | grep -A3 compactor
#    retention_enabled: true must be there.
```

Do **not** delete files under `/var/lib/rancher/k3s/server/db` — that is etcd, i.e. the
cluster itself.

## Escalation / if that didn't work

1. Shrink retention in Git and let Argo apply it: `retention`/`retentionSize` in
   `gitops/apps/_values/kube-prometheus-stack.yaml`, `retention_period` in
   `gitops/apps/_values/loki.yaml`. Prometheus needs a pod restart to pick it up.
2. If a PVC must shrink, it is delete-and-recreate — metrics/logs history is lost. That is
   an acceptable trade at 2 a.m.; note it in the incident.
3. Still full with nothing obvious: `sudo lsof +L1` finds deleted-but-open files holding
   space, which a process restart releases.

## Prevention

`NodeDiskWillFillIn24h` exists so this is never an emergency. If you only ever see
`NodeDiskFillingUp`, the 24h alert is not working — fix that before anything else.
