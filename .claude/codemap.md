# RevealRoll Platform — Code Map

**"I want to change X → touch this file."** Your first stop before grepping.

Rows name **files and symbols, not line numbers** — line numbers go stale on the very next edit and
then actively mislead. If you move or rename something listed here, fix the row in the same commit.

The **Stage** column says when that file first gets real content. Rows marked ⏳ don't exist yet —
they're the plan, and that's deliberate: the map was written before the code so the shape is decided
in advance rather than by whatever was nearest at 11 p.m.

---

## 🌍 INFRASTRUCTURE (Terraform)

| What | File | Symbol / key | Stage |
|------|------|--------------|-------|
| Change the VPS size or image | `terraform/stacks/01-infra/main.tf` | `module "staging_nodes"` → `var.nodes` | ⏳ 01 |
| **Add a second node (worker)** | `terraform/envs/staging.tfvars` | one more entry in `nodes` map, `role = "agent"` | ⏳ 01 |
| Node definition itself | `terraform/modules/contabo-instance/main.tf` | `contabo_instance.this` | ⏳ 01 |
| Rotate Contabo API credentials | *(environment only)* | `CNTB_OAUTH2_*` in your gitignored `.envrc` | 01 |
| Where Terraform state lives | `terraform/stacks/*/backend.tf` | Cloudflare R2, `skip_s3_checksum = true` | ⏳ 01 |
| Rotate R2 credentials | *(environment only)* | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | 01 |
| Get the VPS IP for anything | `terraform/stacks/01-infra/outputs.tf` | `output "ipv4"` | ⏳ 01 |

⚠️ The R2 buckets themselves are **created by hand** in the Cloudflare dashboard. The bucket that
holds the state can't be managed by the stack whose state it holds. See Stage 01.2.

---

## 🖥 HOST CONFIGURATION (Ansible)

| What | File | Symbol / key | Stage |
|------|------|--------------|-------|
| **Open a firewall port** | `ansible/roles/firewall/templates/nftables.conf.j2` | `chain input` accept rules | ⏳ 02 |
| Change the SSH port | `ansible/inventory/group_vars/all.yml` | `ssh_port` (then `ansible_port` in inventory) | ⏳ 02 |
| Harden / unharden sshd | `ansible/roles/ssh-hardening/templates/99-hardening.conf.j2` | all | ⏳ 02 |
| Install a package on the host | `ansible/roles/common/tasks/main.yml` | the `apt` task's `loop` | ⏳ 02 |
| Journald / log size caps | `ansible/roles/common/tasks/main.yml` | `SystemMaxUse`, `SystemMaxFileSize` | ⏳ 02 |
| fail2ban tuning, unban an IP | `ansible/roles/fail2ban/templates/jail.local.j2` | `maxretry`, `bantime`, `ignoreip` | ⏳ 02 |
| **Change k3s install flags** | `ansible/roles/k3s-server/defaults/main.yml` | `k3s_version`, `k3s_disable`, `k3s_tls_sans` | ⏳ 03 |
| Add a TLS SAN (new hostname for the API) | `ansible/inventory/group_vars/all.yml` | `k3s_tls_sans` | ⏳ 03 |
| The host inventory (IP, user, port) | `ansible/inventory/staging.yml` | **gitignored**; `.example` is committed | ⏳ 02 |
| Ansible secrets | `ansible/inventory/group_vars/vault.yml` | `ansible-vault edit` | ⏳ 02 |
| Assertions that hardening held | `ansible/playbooks/99-verify.yml` | `ansible.builtin.assert` tasks | ⏳ 02 |

⚠️ **Order matters** in `ansible/playbooks/10-harden.yml`: `firewall` runs *before* `ssh-hardening`,
so the new SSH port is open before sshd moves to it. Swapping them locks you out.

---

## ☸️ CLUSTER BOOTSTRAP (Terraform, stack 02)

| What | File | Symbol / key | Stage |
|------|------|--------------|-------|
| Ingress controller settings | `terraform/stacks/02-cluster-bootstrap/ingress_nginx.tf` | `helm_release.ingress_nginx` values | ⏳ 04 |
| **Switch staging → prod certificates** | `terraform/stacks/02-cluster-bootstrap/variables.tf` | `var.acme_issuer` | ⏳ 04 |
| Add / edit a ClusterIssuer | `terraform/stacks/02-cluster-bootstrap/cert_manager.tf` | `local.issuers` | ⏳ 04 |
| Argo CD URL, resources, SSO | `terraform/stacks/02-cluster-bootstrap/argocd.tf` | `helm_release.argocd` values | ⏳ 04 |
| Sealed-secrets controller | `terraform/stacks/02-cluster-bootstrap/sealed_secrets.tf` | `helm_release.sealed_secrets` | ⏳ 04 |
| Argo CD initial admin password | `terraform/stacks/02-cluster-bootstrap/outputs.tf` | `output "argocd_initial_password"` | ⏳ 04 |

⚠️ These four charts are the **only** things Terraform installs into the cluster. Anything else
belongs to Argo CD. See the layer-ownership rule in [`../CLAUDE.md`](../CLAUDE.md).

---

## 🚀 THE APPLICATION (Helm)

| What | File | Symbol / key | Stage |
|------|------|--------------|-------|
| **Which image is deployed** | `charts/revealroll/values-staging.yaml` | `image.tag` — **CI writes this line** | ⏳ 06 |
| Replica count | `charts/revealroll/values-staging.yaml` | `replicaCount` | ⏳ 06 |
| CPU / memory requests & limits | `charts/revealroll/values.yaml` | `resources` | ⏳ 06 |
| Probe paths and timings | `charts/revealroll/values.yaml` | `probes` | ⏳ 06 |
| Pod spec: security, volumes, strategy | `charts/revealroll/templates/deployment.yaml` | all | ⏳ 06 |
| **Upload size limit (413 errors)** | `charts/revealroll/templates/ingress.yaml` | `proxy-body-size` annotation | ⏳ 06 |
| Hostname the app serves on | `charts/revealroll/values-staging.yaml` | `ingress.host` | ⏳ 06 |
| Autoscaling | `charts/revealroll/templates/hpa.yaml` | `autoscaling.*` in values | ⏳ 06 |
| Disruption budget | `charts/revealroll/templates/pdb.yaml` | `podDisruptionBudget.*` | ⏳ 06 |
| Prometheus scrape config for the app | `charts/revealroll/templates/servicemonitor.yaml` | `serviceMonitor.enabled` | ⏳ 08 |
| Label definitions (⚠ selector is immutable) | `charts/revealroll/templates/_helpers.tpl` | `revealroll.labels`, `revealroll.selectorLabels` | ⏳ 06 |

⚠️ Never put a changing value (like `image.tag`) in `revealroll.selectorLabels` —
`Deployment.spec.selector` is immutable and `helm upgrade` will fail permanently.

---

## 🔄 GITOPS (Argo CD)

| What | File | Symbol / key | Stage |
|------|------|--------------|-------|
| **Add a new platform component** | `gitops/apps/<name>.yaml` | a new `Application` — that's the whole process | ⏳ 07 |
| The app-of-apps root | `gitops/root-app.yaml` | `Application.spec.source.path: gitops` | ⏳ 07 |
| What the app is allowed to create | `gitops/projects/apps.yaml` | `namespaceResourceWhitelist` | ⏳ 07 |
| What platform charts are allowed | `gitops/projects/platform.yaml` | `sourceRepos`, `destinations` | ⏳ 07 |
| Turn auto-sync / prune / selfHeal on or off | `gitops/apps/revealroll.yaml` | `syncPolicy.automated` | ⏳ 07 |
| Silence a permanent OutOfSync | `gitops/apps/<name>.yaml` | `spec.ignoreDifferences` | ⏳ 07 |
| Upstream chart versions & values | `gitops/apps/_values/*.yaml` | per chart | ⏳ 08 |

⚠️ **Recovery path if Argo CD can't fix itself:** `kubectl apply -f gitops/root-app.yaml`.
That is the only sanctioned manual apply in this repo.

---

## 📊 OBSERVABILITY

| What | File | Symbol / key | Stage |
|------|------|--------------|-------|
| **Add or edit an alert** | `observability/alerts/platform.yaml` | `PrometheusRule.spec.groups` | ⏳ 08 |
| SLO burn-rate alerts | `observability/alerts/app-slo.yaml` | recording rules + `…ErrorBudgetBurn*` | ⏳ 10 |
| Argo CD health alerts | `observability/alerts/argocd.yaml` | | ⏳ 08 |
| **Add a dashboard** | `observability/dashboards/*.json` | exported Grafana JSON model | ⏳ 08 |
| Prometheus retention / scrape interval | `gitops/apps/_values/kube-prometheus-stack.yaml` | `prometheus.prometheusSpec.retention` | ⏳ 08 |
| Grafana hostname, datasources | `gitops/apps/_values/kube-prometheus-stack.yaml` | `grafana.ingress`, `additionalDataSources` | ⏳ 08 |
| Where alerts are delivered | `gitops/apps/_values/kube-prometheus-stack.yaml` | `alertmanager.config.receivers` | ⏳ 08 |
| **Log retention** | `gitops/apps/_values/loki.yaml` | `limits_config.retention_period` **and** `compactor.retention_enabled` | ⏳ 08 |
| Which logs get collected | `gitops/apps/_values/alloy.yaml` | the discovery/relabel rules | ⏳ 08 |
| Host metrics (survive cluster death) | `ansible/roles/node-exporter/` | systemd unit, binds `127.0.0.1:9100` | ⏳ 02 |
| SLO definitions | `docs/slo.md` | the PromQL, not the prose | ⏳ 10 |

⚠️ Loki retention needs **both** `retention_period` and `compactor.retention_enabled: true`.
The first alone is a silent no-op and your disk fills.

---

## 🔐 SECRETS

| What | File | Symbol / key | Stage |
|------|------|--------------|-------|
| **Add or change an app secret** | local `.env.staging` (gitignored) → `scripts/seal-env.sh` | | ⏳ 05 |
| The committed, encrypted secret | `secrets/staging/revealroll-sealed.yaml` | `spec.encryptedData` | ⏳ 05 |
| How sealing works / rotation policy | `secrets/README.md` | all | ⏳ 05 |
| Which env var goes where | `docs-course/reference/env-mapping.md` | the mapping table | ✅ |
| **Restore the sealing key** | *(password manager)* | see `secrets/README.md` → Disaster recovery | 04 |

⚠️ `NEXT_PUBLIC_*` are **build-time** — Docker `--build-arg`, not Secret keys. Setting them only at
runtime silently produces a bundle pointing at production.
⚠️ Losing the sealed-secrets private key makes **every** `SealedSecret` in this repo permanently
undecryptable. It is backed up in the password manager. Re-back-up after any controller reinstall.

---

## 🔁 CI/CD

| What | File | Symbol / key | Stage |
|------|------|--------------|-------|
| Image build & push | `tutac/revealroll` → `.github/workflows/ci.yml` | job `docker` | ⏳ 09 |
| **The tag-bump that deploys** | `tutac/revealroll` → `.github/workflows/ci.yml` | job `bump-staging` | ⏳ 09 |
| `NEXT_PUBLIC_*` build args | `tutac/revealroll` → `.github/workflows/ci.yml` | `build-args:` block | ⏳ 09 |
| Where the ARGs are declared | `tutac/revealroll` → `Dockerfile` | builder stage | ⏳ 06 |
| Platform repo validation | `.github/workflows/validate.yml` | tf / ansible / helm / gitleaks jobs | ⏳ 09 |
| The cross-repo token | `tutac/revealroll` → repo secrets | `PLATFORM_REPO_TOKEN` (fine-grained, Contents:write) | ⏳ 09 |

---

## 🧰 SCRIPTS & OPERATIONS

| What | File | Stage |
|------|------|-------|
| Get a kubeconfig on your laptop | `scripts/fetch-kubeconfig.sh` | ⏳ 03 |
| Seal a whole `.env` into one SealedSecret | `scripts/seal-env.sh` | ⏳ 05 |
| Is the site up and is the cert healthy | `scripts/smoke.sh` | ⏳ 06 |
| Back up etcd + the sealing key to R2 | `scripts/backup-etcd.sh` | ⏳ 10 |
| Common command shortcuts | `Makefile` | ✅ |
| **What to do when an alert fires** | `docs/runbooks/*.md` | ⏳ 10 |
| Why things are the way they are | `.claude/memory/decisions.md` | ✅ |
| What has broken before | `.claude/memory/incidents.md` | ⏳ 10 |

---

## Where to look when you don't know

| Symptom | Start here |
|---|---|
| Something is broken and you don't know what | Triage order in [`../CLAUDE.md`](../CLAUDE.md) |
| A specific error message | `docs-course/reference/troubleshooting.md` |
| "What's the command for…" | `docs-course/CHEATSHEET.md` |
| "What even is this tool" | `docs-course/GLOSSARY.md` |
| "How does the whole thing fit together" | `docs-course/ARCHITECTURE.md` |
| "What am I supposed to be doing" | `docs-course/PROGRESS.md` |
