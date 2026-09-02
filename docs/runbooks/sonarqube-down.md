# Runbook — `SonarQubeUnavailable`

## What this alert means

Prometheus has not been able to scrape SonarQube's `/api/monitoring/metrics` for ten
minutes. Either the pod is not running, or it is running and not healthy.

## Impact

**No user impact — but deploys stop.** The quality gate is a `needs:` dependency of the
image build in `tutac/revealroll`, so while SonarQube is down a merge to `main` produces
no image and therefore no tag bump. The CI failure reads as a scanner error, which sends
people looking in the application repository. It is this.

If you need to ship during an outage, that is a deliberate decision: temporarily drop
`sonar` from the `docker` job's `needs:` in the app repo, ship, and revert the workflow
change in the same session. Write it up in `incidents.md`.

## Triage

```bash
kubectl -n sonarqube get pods
kubectl -n sonarqube describe pod -l app=sonarqube      # read EVENTS, not status
kubectl -n sonarqube logs -l app=sonarqube --tail=100
```

The four things that actually go wrong here, in order of likelihood:

**1. OOMKilled.** This is the expected failure on an 8 GB node.

```bash
kubectl -n sonarqube get pod -l app=sonarqube \
  -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason}'
```
`OOMKilled` means the three JVM heaps plus overhead exceeded the 3Gi limit. Do **not**
raise the limit blindly — check `kubectl top nodes` first. If the node has no headroom,
the right move is to accept that this instance is too small for the analysis being run,
not to let it evict Prometheus.

**2. Elasticsearch bootstrap check.** Logs mention `max virtual memory areas
vm.max_map_count [65530] is too low`. The host sysctl is missing, which means Ansible has
not run on this node since the setting was added:

```bash
ssh deploy@<node-ip> sysctl vm.max_map_count      # expect 524288
cd ansible && ansible-playbook -i inventory/staging.yml site.yml
```
Do not re-enable `initSysctl` in the chart values to work around this — that reintroduces
a privileged container to fix a host that Ansible already owns.

**3. Database.** Logs mention JDBC, `connection refused`, or a failed migration.

```bash
kubectl -n sonarqube get pods -l app.kubernetes.io/name=sonarqube-postgres
kubectl -n sonarqube logs sonarqube-postgres-0 --tail=50
```
If PostgreSQL is fine but authentication fails, the sealed `postgres-password` and the
password inside the existing database have diverged — re-sealing the Secret does not
change the database. Fix with `ALTER ROLE sonarqube WITH PASSWORD …` from inside the pod,
or delete the PVC and let it re-initialise (analysis history is lost; it is rebuildable).

**4. Disk.** local-path PVCs are directories on the node's root filesystem. See
`disk-pressure.md` — a full disk presents here as a database that will not start.

## Mitigation

```bash
# Recycle the pod — legitimate manual action, it does not fight Argo CD
kubectl -n sonarqube rollout restart statefulset/sonarqube

# Genuinely need the node's memory back right now (incident, not tidiness):
kubectl -n sonarqube scale statefulset/sonarqube --replicas=0
# then revert it in Git, or Argo CD's selfHeal will do it for you within 3 minutes
```

## Recovery of the admin account

The admin password is not stored in this repository — it is set at first login and lives
in the password manager. If it is lost, reset it against the database directly (SonarQube
documents the `update users set crypted_password=…` procedure) — there is no sealed secret
to re-read.

## What would have caught this sooner

The scrape alert fires ten minutes after the fact. A `NodeMemoryPressure` warning usually
precedes an OOMKill here by longer than that — if this alert fires and that one did not,
the memory alert's threshold is the thing to revisit.
