# Runbook — `KubeNodeNotReady`, `NodeMemoryPressure`

## What this alert means

The one node is unhealthy: either the kubelet has stopped reporting Ready, or memory is
nearly exhausted and the kernel is about to start killing processes.

## Impact

`KubeNodeNotReady` — everything is down and nothing can be rescheduled, because there is
no second node. `NodeMemoryPressure` — the OOM killer is choosing victims, and its choices
will look arbitrary (it often picks the largest process, not the guilty one).

## Triage

```bash
# Cluster's view (needs the tunnel)
kubectl describe node | sed -n '/Conditions/,/Addresses/p'

# Host's view — this is where the answer usually is
ssh deploy@<node-ip>
free -m
uptime                                  # load average vs 4 vCPU
sudo journalctl -u k3s -n 100 --no-pager
sudo dmesg -T | grep -i 'out of memory\|oom-killer' | tail -20
df -h /                                 # a full disk also shows up as NotReady
```

Read it in this order:

- OOM kills present → something grew. Usually Prometheus (series count) or the app.
- Disk near full → this is really `disk-pressure.md`.
- k3s logs full of etcd or apiserver errors, disk and memory fine → k3s itself is wedged.

## Mitigation

```bash
# 1. Restart k3s before restarting the machine. Faster, and it usually works.
sudo systemctl restart k3s
kubectl get nodes -w                    # Ready within ~60s

# 2. Reclaim memory from the biggest offender rather than rebooting
kubectl top pods -A --sort-by=memory | head
kubectl rollout restart deployment <name> -n <ns>

# 3. Last resort: reboot the host
sudo reboot
```

After **any** reboot, verify what does not come back by itself:

```bash
./scripts/smoke.sh                      # public access, end to end
kubectl get applications -n argocd      # all Synced/Healthy
ssh deploy@<node-ip> 'sudo nft list table ip nat | grep -c CNI-HOSTPORT'   # must be > 0
```

That last check is not paranoia: hostPort DNAT rules are written once at pod creation, and
losing them is invisible from inside the cluster (see the 2026-08-17 incident).

## Escalation / if that didn't work

1. Node does not come back after a reboot → Contabo panel, VNC console, check whether it
   booted at all before assuming a Kubernetes problem.
2. k3s starts but the API never becomes ready → `journalctl -u k3s` for etcd corruption.
   That is the restore drill: `scripts/backup-etcd.sh` snapshot + Stage 10's procedure.
3. Repeated OOM with no single culprit → the node is genuinely undersized for what is
   installed. Reduce Prometheus retention or drop a component; do not just reboot weekly.

## Prevention

Memory requests are reservations, not limits — real usage exceeds them. `kubectl describe
node | grep -A6 'Allocated resources'` before installing anything new. Prometheus grows
toward its limit as series accumulate, so it is the component to watch over time.
