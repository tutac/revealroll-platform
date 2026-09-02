# RevealRoll Platform — Infrastructure Guide

This repository operates the **staging environment** for RevealRoll on a Contabo VPS running k3s.
It does not contain application code. Application code lives in `tutac/revealroll`.

**Production is Vercel. This is staging — and the environment where operational practice happens.**

---

## System overview

```
Terraform (01-infra)      →  Contabo VPS (imported)       (things with an API before a cluster exists)
Ansible                   →  OS users, SSH, firewall, k3s       (things inside the operating system)
Terraform (02-bootstrap)  →  ingress-nginx, cert-manager,       (the minimum needed for Argo CD to exist)
                             sealed-secrets, Argo CD
Argo CD (app-of-apps)     →  RevealRoll, monitoring, logging    (everything with a Kubernetes API)
```

**The layer-ownership rule.** Every component belongs to exactly one layer, and the rule is mechanical:

| If the thing… | Owner |
|---|---|
| has a provider API and must exist before the cluster does | Terraform `01-infra` |
| is a file, package, service, or kernel setting on the host | Ansible |
| is one of the four bootstrap components Argo CD needs to run | Terraform `02-cluster-bootstrap` |
| is any other Kubernetes object | Argo CD, via Git |

Violating this is how these stacks rot. If you find yourself installing a Helm chart from Ansible, or
`kubectl apply`-ing something by hand that Argo CD should own, stop — the layer is wrong, not the tool.

Terraform's bootstrap stack installs **only** ingress-nginx, cert-manager, sealed-secrets, and Argo CD.
The moment Argo CD is up, Terraform stops adding cluster resources. Everything after that is a commit.

---

## Repository layout

| Path | What lives here | Owner layer |
|---|---|---|
| `terraform/stacks/01-infra/` | Contabo instance (imported); state in Cloudflare R2 | Terraform |
| `terraform/stacks/02-cluster-bootstrap/` | 4 `helm_release`s + ClusterIssuers + Argo CD root app | Terraform |
| `terraform/modules/` | Reusable `contabo-instance` | Terraform |
| `ansible/playbooks/` | `00-bootstrap` → `10-harden` → `20-k3s` → `99-verify` | Ansible |
| `ansible/roles/` | `common`, `users`, `ssh-hardening`, `firewall`, `fail2ban`, `node-exporter`, `k3s-server` | Ansible |
| `charts/revealroll/` | Your own Helm chart for the app | Argo CD |
| `gitops/` | `root-app.yaml` (app-of-apps), AppProjects, Application manifests | Argo CD |
| `observability/` | Grafana dashboard JSON, `PrometheusRule` alerts | Argo CD |
| `secrets/staging/` | Committed **SealedSecrets** (encrypted — safe in Git) | Argo CD |
| `scripts/` | `fetch-kubeconfig.sh`, `seal-env.sh`, `smoke.sh`, `backup-etcd.sh` | — |
| `docs/runbooks/` | One runbook per alert. Written before the alert fires. | — |
| `.Codex/codemap.md` | "I want to change X → touch this file." First stop before grepping. | — |

---

## First-run order

Nothing here is optional or reorderable. Each step consumes an output of the previous one.

```bash
# 1. Infra — imports the existing VPS (R2 buckets are created by hand; see Stage 01)
cd terraform/stacks/01-infra && terraform init && terraform plan && terraform apply
terraform output -raw ipv4          # → goes into ansible/inventory/staging.yml

# 2. Machine — first contact as root, then everything as the deploy user
cd ../../../ansible
ansible-playbook -i inventory/staging.yml playbooks/00-bootstrap.yml   # once, as root
ansible-playbook -i inventory/staging.yml site.yml                     # idempotent, re-runnable

# 3. Kubeconfig onto your laptop
../scripts/fetch-kubeconfig.sh && kubectl get nodes

# 4. Cluster bootstrap — the last thing Terraform installs into the cluster
cd ../terraform/stacks/02-cluster-bootstrap && terraform init && terraform apply

# 5. Argo CD takes over. From here on, deploying = committing.
```

---

## URL map

| URL | What | Auth |
|---|---|---|
| `https://stg.revealroll.com` | RevealRoll staging | app login (Supabase staging) |
| `https://argocd.stg.revealroll.com` | Argo CD | admin; initial password is a Terraform output |
| `https://grafana.stg.revealroll.com` | Grafana | admin; password from a sealed secret |
| `https://alertmanager.stg.revealroll.com` | Alertmanager | basic-auth via ingress annotation |

DNS is a **wildcard `*.stg` A record on Namecheap** pointing at the VPS IPv4, added by hand.
Terraform does not manage DNS. If a hostname doesn't resolve, check Namecheap before you debug ingress.

---

## Secret handling — the one rule

**No plaintext secret ever enters this repository.** Not in a values file, not in a tfvars file, not
"temporarily" in a commit you plan to amend. `git` remembers.

- App secrets → `scripts/seal-env.sh` → a `SealedSecret` in `secrets/staging/`. Encrypted, committed, safe.
- Ansible secrets → `ansible-vault` in `inventory/group_vars/vault.yml`.
- Terraform credentials → environment variables (`CNTB_*`, `AWS_*`), never `.tfvars`.
- The **sealed-secrets controller private key is backed up in the password manager.** Losing it makes
  every `SealedSecret` in this repo permanently undecryptable. Re-backup after any controller reinstall.

`NEXT_PUBLIC_*` values are **build-time** in Next.js. They are baked into the client bundle by
`npm run build`, so they must be passed as Docker `--build-arg`s in CI. Setting them only as runtime
env in the Deployment silently produces a bundle pointing at the wrong URL. See `docs/env-mapping.md`.

---

## Image tags

Always `ghcr.io/tutac/revealroll:sha-<commit>`. Never `latest`, never a moving tag.

The tag currently deployed is a single line in `charts/revealroll/values-staging.yaml`, written there
by CI. That is deliberate: "what is running in staging?" is answered by reading one file, and
rollback is `git revert` of the bump commit. A mutable tag destroys both properties.

---

## Before you push

```bash
terraform fmt -recursive -check      # formatting
terraform validate                   # in each stack
ansible-lint                         # playbooks + roles
helm lint charts/revealroll
helm template charts/revealroll -f charts/revealroll/values-staging.yaml | kubeconform -strict -
gitleaks detect --no-git             # nothing secret-shaped is staged
```

CI (`.github/workflows/validate.yml`) runs exactly these. Running them locally first saves a round trip.

---

## Operating conventions

- **Never `kubectl apply` into the cluster.** If it isn't in Git, Argo CD will delete it (prune) or
  fight you (selfHeal). Manual `kubectl` is for *reading* — `get`, `describe`, `logs`, `top`, `events`.
  The two legitimate exceptions: emergency `scale`/`cordon` during an incident (revert to Git after),
  and `rollout restart` to recycle pods.
- **Every alert has a `runbook_url` annotation** pointing at a file in `docs/runbooks/`. An alert
  without a runbook is a page with no instructions — write the runbook first, then the alert.
- **Every incident goes in `.Codex/memory/incidents.md`**: what you saw, when you detected it, root
  cause, fix, and what would have detected it sooner. This file is the actual product of the project.
- **Architecture decisions go in `.Codex/memory/decisions.md`** — why k3s over kubeadm, why
  sealed-secrets over ESO, why nginx over Traefik. You will be asked these in interviews.
- Keep `.Codex/codemap.md` accurate. If you move or rename something listed there, fix the row in
  the same commit.

---

## Triage order when something is broken

Work down this list. Do not skip to the bottom — most outages are answered by step 2.

1. **Argo CD** — is the Application `Synced` and `Healthy`? Out-of-sync means Git and cluster disagree.
2. **Pods** — `kubectl get pods -A | grep -v Running`. Then `describe` the offender; read **Events**,
   not just the status. `ImagePullBackOff`, `CrashLoopBackOff`, and `Pending` have completely different causes.
3. **Ingress + certs** — `kubectl get certificate,order,challenge -A`. A `Pending` challenge is nearly
   always DNS or a blocked port 80.
4. **Logs** — Loki in Grafana, or `kubectl logs --previous` for a pod that already restarted.
5. **Metrics** — Grafana golden signals; is this saturation (memory/disk) or an error spike?
6. **Host** — SSH in. `df -h`, `free -m`, `journalctl -u k3s -n 100`. On a single node, a full disk
   presents as ten unrelated Kubernetes symptoms at once.

---

## Environment facts

| | |
|---|---|
| App repo | `tutac/revealroll` (Next.js 16, `output: 'standalone'`, port 3000, non-root uid 1001) |
| Node | Contabo Cloud VPS 4 — 4 vCPU, 8 GB RAM, 100 GB SSD, single node |
| Domain | `revealroll.com` (Namecheap). Staging is `*.stg.revealroll.com`; the apex is Vercel production. |
| Image registry | `ghcr.io/tutac/revealroll` |
| Database | Supabase **staging** project — this cluster must never hold prod Supabase keys |
| Node arch | VPS is `linux/amd64`; your Mac is `arm64`. Always build with `--platform linux/amd64`. |
| Kubernetes | k3s, installed with `--disable=traefik --disable=servicelb` |
| Ingress | ingress-nginx via `hostPort` 80/443 (single node, no cloud load balancer) |
| Certificates | cert-manager, HTTP-01. Two issuers: `letsencrypt-staging` and `letsencrypt-prod`. |
