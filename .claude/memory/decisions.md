# Architecture Decisions

ADR-lite. One entry per decision that a reasonable person could have made differently.

**Why this file exists:** in six months, in an interview, someone will ask "why k3s and not kubeadm?"
The honest answer written on the day you decided is far better than the one you reconstruct on the
spot. Write the real reasoning, including the unflattering parts — "nginx has more StackOverflow
answers at midnight" is a legitimate operational argument.

**Format:** copy the shape of the entries below. Append new ones; don't rewrite old ones. If a
decision is reversed, add a new entry that supersedes it and say so.

---

## 001 — Kubernetes distribution: k3s

**Date:** 2026-08-11
**Status:** accepted

**Context:** One Contabo VPS (4 vCPU / 8 GB / 100 GB) running an observability stack plus the
application. Full kubeadm control-plane components would consume a meaningful fraction of that budget
before a single workload is scheduled.

**Decision:** k3s, installed via an Ansible role, with `--disable=traefik --disable=servicelb`.

**Alternatives considered:**
- *kubeadm* — closer to the CKA exam and to what large shops run; more manual etcd and certificate
  work. Rejected on memory footprint and setup time. The operational skills this project is really
  about (GitOps, observability, incident response) are identical on either.
- *Managed (EKS / GKE / AKS)* — removes the entire layer being learned, and costs more per month than
  the VPS.
- *k0s / MicroK8s* — comparable technically; k3s has the largest community and the best documentation,
  which matters most when debugging alone.

**Consequences:**
- Same kubectl / YAML / API as any conformant cluster, so the skills transfer directly.
- Must disable the bundled Traefik and servicelb or they contend with ingress-nginx for :80/:443.
- `kube-prometheus-stack` needs its etcd / scheduler / controller-manager scrape jobs disabled,
  because k3s doesn't expose them the way the chart expects.
- Single node means no real HA and no meaningful pod anti-affinity until a second node exists. The
  Ansible inventory and Terraform module are structured so adding one is a variable change.

---

## 002 — Secrets management: Sealed Secrets

**Date:** 2026-08-11
**Status:** accepted

**Context:** GitOps requires the desired state of the cluster to live in Git, but the application needs
~40 secrets (Supabase, Stripe, APNs, Resend, VAPID). Either they're in Git (unacceptable) or the system
isn't really GitOps.

**Decision:** bitnami-labs Sealed Secrets. `kubeseal` encrypts with the controller's public key; the
resulting `SealedSecret` is committed; only the in-cluster private key can decrypt it.

**Alternatives considered:**
- *SOPS + age* — good ergonomics for encrypting Helm values, but requires a custom Argo CD
  config-management-plugin. More moving parts than one controller.
- *External Secrets Operator + Vault* — the most production-realistic answer, and what a real company
  would run. Rejected because Vault would want ~500 MB of RAM on a single node, and the operational
  lesson (never commit plaintext) is the same either way.
- *Plain Kubernetes Secrets applied by hand* — breaks GitOps; the cluster would hold state that Git
  doesn't know about.

**Consequences:**
- The repository can be public without leaking anything.
- **The controller's private key is a single point of catastrophic failure.** Lose it and every
  `SealedSecret` in this repo is permanently undecryptable. It is backed up in the password manager,
  and re-backed-up after any controller reinstall. Verified during the Stage 10 restore drill.
- Rotating a secret means re-sealing and committing; pods pick it up via the `checksum/secret`
  annotation on the Deployment, which changes the pod spec and triggers a rollout.
- SealedSecrets are bound to namespace + name by default, so moving one requires re-sealing.

---

## 003 — Ingress controller: ingress-nginx over the bundled Traefik

**Date:** 2026-08-11
**Status:** accepted

**Context:** k3s ships Traefik enabled by default. Something has to terminate TLS and route
hostnames, and there is no cloud load balancer available on Contabo.

**Decision:** disable Traefik at k3s install time and deploy ingress-nginx via Helm, binding
`hostPort` 80/443 with `externalTrafficPolicy: Local`.

**Alternatives considered:**
- *Traefik (keep the default)* — one less thing to install, and its CRDs are pleasant. Rejected
  primarily on job-market grounds: ingress-nginx appears in far more postings, and — the honest
  operational argument — has a much deeper pool of existing answers when something breaks at midnight
  and there's nobody to ask.
- *Gateway API implementation* — where the ecosystem is heading, and worth revisiting. Rejected for
  now because Ingress is still what most existing systems use, and learning the incumbent first makes
  the successor easier to understand.

**Consequences:**
- Requires `--disable=traefik` and `--disable=servicelb` at k3s install. These are install-time flags;
  getting them wrong means reinstalling.
- `hostPort` rather than `type: LoadBalancer`, because there is no cloud LB to provision one.
- `externalTrafficPolicy: Local` preserves real client IPs — without it, access logs, rate limits, and
  fail2ban all see only node IPs.
- Annotation-based configuration (e.g. `proxy-body-size` for photo uploads) rather than Traefik CRDs.

---

## 004 — Repository layout: separate platform repo

**Date:** 2026-08-11
**Status:** accepted

**Context:** Application code lives in `tutac/revealroll`. The infrastructure that runs it needs to
live somewhere, and Argo CD needs a repository to watch.

**Decision:** a separate repository, `tutac/revealroll-platform`, containing Terraform, Ansible, Helm
charts, and Argo CD manifests. The app repo only builds images and writes a tag-bump commit here.

**Alternatives considered:**
- *Monorepo (infra inside the app repo)* — fewer moving parts, one clone. Rejected because Argo CD
  watching the same repo that application CI writes to invites feedback loops, and it muddies the
  platform repo's history — which is meant to be a clean deployment log.
- *Three repos (terraform / gitops / charts)* — the most "correct" separation for a large org, and the
  most overhead for one person.

**Consequences:**
- `git log charts/revealroll/values-staging.yaml` is a complete, auditable deployment history.
- Cross-repo commits require a fine-grained PAT (`PLATFORM_REPO_TOKEN`), scoped to Contents:write on
  this repo only — a credential to manage, but a far smaller one than a kubeconfig.
- Two repos to keep in sync when something spans both (e.g. adding `ARG NEXT_PUBLIC_*` to the
  Dockerfile for Stage 06).

---

## 005 — Terraform state and backups: Cloudflare R2

**Date:** 2026-08-11
**Status:** accepted

**Context:** Terraform state must not live on a laptop — it contains every sensitive value in
plaintext and is one `git add .` from being permanent. Contabo Object Storage is a separate paid
product and is not enabled on this account.

**Decision:** Cloudflare R2, free tier. Two buckets: `revealroll-tfstate` and `revealroll-backups`.
Buckets created by hand in the dashboard; credentials supplied via `AWS_*` environment variables.

**Alternatives considered:**
- *Contabo Object Storage* (~€3/month) — keeps everything with one provider and one bill. Rejected on
  cost, given a free option exists that does the same job.
- *Backblaze B2* — equivalent free tier; slightly fiddlier S3 endpoint configuration.
- *HCP Terraform* — free remote state with locking and a nice UI, but solves only state; etcd
  snapshots would still need object storage, so it would mean adopting two things instead of one.

**Consequences:**
- Two R2-specific quirks that must be in the backend config: `skip_s3_checksum = true` (R2 rejects the
  `x-amz-checksum-*` headers newer AWS SDKs send) and `use_lockfile = true` for locking, since there
  is no DynamoDB.
- Multi-provider setup — arguably more realistic than single-vendor, and it forces the credentials to
  be genuinely externalised rather than implicitly available.
- Strictly, R2 is a Cloudflare resource and belongs in a Terraform stack using the `cloudflare`
  provider. The bootstrap bucket is managed by hand as a deliberate exception, because the bucket
  that stores the state cannot be created by the stack whose state it stores.

---

## 006 — Database: existing Supabase staging project

**Date:** 2026-08-11
**Status:** accepted

**Context:** The application depends on Supabase for Postgres, auth, and storage. The cluster needs a
database to talk to.

**Decision:** point the staging deployment at the **existing Supabase staging project**. No in-cluster
Postgres.

**Alternatives considered:**
- *Postgres StatefulSet in-cluster* — real database operations practice (PVCs, backup/restore drills,
  connection pooling). Rejected for now because the app uses Supabase auth and storage, not just
  Postgres, so porting would be substantial application work rather than infrastructure work.

**Consequences:**
- Zero data migration; the app works on day one of Stage 06.
- No stateful-workload practice in the cluster — the backup/restore drill in Stage 10 covers etcd and
  the sealing key, not application data.
- A new failure domain: the app can be perfectly healthy while every request fails because Supabase is
  unreachable or a key was rotated. This is deliberately exercised in game day 10.8.
- **Hard rule:** production Supabase credentials must never enter this cluster.

---

## 007 — Deployment: GitOps tag bump, not `helm upgrade` from CI

**Date:** 2026-08-11
**Status:** accepted

**Context:** CI needs to get a newly built image running in the cluster.

**Decision:** CI pushes the image to GHCR with an immutable `sha-<commit>` tag, then commits that tag
into `charts/revealroll/values-staging.yaml`. Argo CD pulls and applies.

**Alternatives considered:**
- *CI runs `helm upgrade`* — simpler, one fewer repository interaction. Rejected because it requires a
  kubeconfig stored in GitHub secrets: a credential that can do anything in the cluster, held in a
  system reachable by any workflow file or compromised action.
- *Argo CD Image Updater* — watches the registry and writes back to Git automatically. Less machinery
  than a CI job, but it makes the deployment trigger implicit; an explicit commit is easier to reason
  about and to explain.

**Consequences:**
- No cluster credentials ever leave the cluster.
- Rollback is `git revert` — an operation already familiar under stress.
- "What is running right now?" is answered by reading one line in one file.
- A cross-repo PAT is required, and the bump job must be idempotent (no empty commits) and
  concurrency-safe (pushes can race).

---

## 008 — `NEXT_PUBLIC_*` as build args: images are environment-specific

**Date:** 2026-08-11
**Status:** accepted, with known limitation

**Context:** Next.js inlines `NEXT_PUBLIC_*` variables into the client bundle at **build** time. They
cannot be supplied as runtime environment variables.

**Decision:** pass them as Docker `--build-arg`s in CI, declared as `ARG`/`ENV` in the Dockerfile's
builder stage.

**Consequences:**
- **The image is bound to one environment.** An image built with staging's `NEXT_PUBLIC_APP_URL` is a
  staging image and cannot be promoted to production unchanged. This breaks the "build once, deploy
  everywhere" principle.
- The failure mode is silent: setting these only at runtime produces an app that starts fine and
  points at the wrong Supabase project. Verified with
  `curl -s https://stg.revealroll.com | grep -o 'https://[a-z0-9]*\.supabase\.co'`.
- *If this ever needs fixing:* move to runtime configuration — the client fetches config from an API
  route on load instead of reading `NEXT_PUBLIC_*`. That's an application change, not an
  infrastructure one, and is out of scope for this project.

---

## 009 — Repository visibility: public

**Date:** 2026-08-11
**Status:** accepted

**Context:** This repository is two things at once: the working control plane for the RevealRoll
staging environment, and a portfolio artifact meant to be read by people deciding whether I know
how to run infrastructure. Those two purposes pull in opposite directions on visibility. The
repository holds no application source — it holds Terraform, Ansible, Helm charts, Argo CD
manifests, and SealedSecrets — so what is exposed is *method*, not product.

**Decision:** public.

**Alternatives considered:**
- *Private* — removes secret-leak blast radius almost entirely, and would let me be sloppier about
  what lands in a commit. Rejected because a portfolio project nobody can read is not a portfolio
  project, and because "assume a stranger is reading every commit" is precisely the operating
  discipline this project exists to build. Making the rule optional would defeat it.
- *Public, but with `secrets/` in a separate private repo* — Argo CD would then need credentials for
  a second repository, and the app-of-apps stops being readable from one place. Rejected: it trades
  a real architectural simplification for protection that Sealed Secrets already provides (see 002),
  since the committed ciphertext is only decryptable by the controller's in-cluster private key.

**Consequences:**
- The "no plaintext secret ever enters this repository" rule in `CLAUDE.md` is load-bearing rather
  than aspirational. A key committed to a public repo is scraped by bots in minutes, not hours.
- `gitleaks detect --no-git` runs locally before every push and in CI on every push — not only when
  I remember. It is in `make lint` for that reason.
- Incident response for a leak is **rotate at source first**. History rewriting is secondary and
  never sufficient: anyone who cloned or forked already has the value, and GitHub retains dangling
  objects.
- The real IP address of the VPS stays out of Git (`ansible/inventory/staging.yml` is gitignored;
  only `.example` is committed). The host is on the public internet regardless, but there is no
  reason to hand an inventory file to a scanner.
- Everything committed here is written to be read cold by a stranger. That is a constraint on
  naming and comments, not just on secrets.

---

## 010 — Node definitions as committed `variables.tf` defaults, not a gitignored `.tfvars`

**Date:** 2026-08-12
**Status:** accepted

**Context:** Stage 01.8 moved `contabo_instance.this` into a reusable module driven by a `nodes` map.
That map has to be *supplied* somewhere. The repo's `.gitignore` blanket-ignores `*.tfvars`, and the
scaffold shipped a `terraform/envs/staging.tfvars.example`, so the obvious path was a gitignored
`terraform/envs/staging.tfvars`. The values in question are a Contabo product SKU (`V153`), an OS
image UUID, an add-on ID, and a role string. None of them are credentials.

**Decision:** the `nodes` map carries a committed `default` in `terraform/stacks/01-infra/variables.tf`.
`terraform/envs/staging.tfvars.example` and `terraform/stacks/01-infra/terraform.tfvars.example` were
deleted rather than left as misleading dead files. The blanket `*.tfvars` ignore stays exactly as it is.

**Alternatives considered:**
- *Gitignored `terraform/envs/staging.tfvars`* — matches the scaffold's implied layout and the original
  codemap row. Rejected: a fresh clone could not `terraform plan` at all, and "what is running in
  staging?" would stop being answerable by reading Git — the same property the image-tag rule in
  `CLAUDE.md` exists to protect. It also hides non-secret config behind a rule meant for secrets,
  which erodes what the rule means.
- *Committed `terraform/envs/staging.tfvars` with a `!` un-ignore exception* — keeps the intended
  directory layout and the values in Git. Rejected as the worse of the two working options: it needs a
  negation in `.gitignore` plus `-var-file` threaded through `make tf-plan` / `tf-apply`
  (`Makefile:29`), so two more places must stay in sync to buy nothing over a default. A `*.tfvars`
  ignore with a hole in it is also exactly the pattern that eventually lets a real secret through.

**Consequences:**
- `make tf-plan` and `make tf-apply` work with no `-var-file` and no Makefile change.
- Adding a worker node is editing one map in one committed file, reviewable in a PR diff — which was
  the point of extracting the module.
- The rule to remember: **`*.tfvars` stays universally ignored, and nothing non-secret is ever put
  there.** If a value belongs in Git, it goes in `variables.tf`; if it does not, it goes in `.envrc`.
  There is deliberately no third category.
- The VPS's public IP is still *not* committed (decision 009 holds): it is a computed output resolved
  at plan time from the provider, never a literal in config.
- `.claude/codemap.md` rows 18–19 were repointed at `variables.tf` in the same commit.

---

## 011 — kube-apiserver reached over an SSH tunnel, not an allowlisted 6443

**Date:** 2026-08-13
**Status:** accepted

**Context:** `kubectl` has to reach the API server from a laptop, but `roles/firewall` is
default-drop and opens only SSH, 80 and 443 — and `playbooks/99-verify.yml` *asserts* that 6443 never
appears in the ruleset. Something had to give: either the kubeconfig goes through a tunnel, or the
firewall grows a hole and the assertion is relaxed. This is a single-node cluster with one operator on
a residential connection, so there is no VPN or bastion already in the picture.

**Decision:** 6443 stays closed to the internet. `scripts/fetch-kubeconfig.sh` writes a kubeconfig
pointing at `https://127.0.0.1:6443`, and `make tunnel` forwards that through SSH. The kube-apiserver
is reachable only by someone who already holds an SSH key for the `deploy` user.

**Alternatives considered:**
- *Allow 6443 from a single home IP in the nftables role* — one line, no tunnel, no second terminal.
  Rejected on three counts: a residential IP is not static, so the rule silently stops matching and
  the fix always happens under pressure; it puts the API server's authentication on the internet where
  a client-cert bug is remotely reachable rather than merely locally reachable; and it forces
  `99-verify.yml` to stop asserting 6443 is closed, which removes the check that would notice if it
  were opened by accident later. The tunnel costs one terminal and gives up nothing.
- *Tailscale or a WireGuard mesh* — the right answer for a team, and genuinely nicer to use. Rejected
  as scope: it adds a daemon, an account, and a second identity system to a single-node staging box,
  none of which this project is trying to teach.

**Consequences:**
- Every `kubectl` session needs `make tunnel` running. That friction is real and is the price.
- Terraform's `02-cluster-bootstrap` stack talks to the cluster through the same tunnel, so it must be
  up before `terraform apply` in Stage 04. Expect to be reminded of this exactly once.
- The reversal is deliberately cheap and pre-built: the public IP and both hostnames are already in
  `k3s_tls_sans`, so the certificate is valid for direct access *today*. Opening 6443 later is a
  firewall change plus `K3S_DIRECT=1` on the fetch script — not a k3s reinstall. That is the whole
  reason the SANs were listed at install time even though nothing uses them yet.
- The thing to remember: **SANs are an install-time decision, everything else about this is not.**

---

## 012 — Sealed secrets as their own Application, not files inside the chart

**Date:** 2026-08-17
**Status:** accepted

**Context:** The app's credentials live in `secrets/staging/` as SealedSecrets (decision 002's
machinery). Stage 07 had to put them somewhere Argo CD would apply them. Two obvious homes: move the
sealed files into `charts/revealroll/templates/`, or point a second Application at the directory.

**Decision:** a second Application, `gitops/apps/revealroll-secrets.yaml`, with a directory source on
`secrets/staging`. The chart renders no secrets at all; it only names the Secret it consumes with
`envFrom`.

**Alternatives considered:**
- *Sealed files in the chart's `templates/`* — one Application instead of two, and the secret is
  versioned with the code that reads it. Rejected on two counts. Rotating a credential would become a
  chart change, so it would show up in the same diff as an image bump and be reviewed with the same
  (low) attention. And a bad secret and a bad release could no longer fail independently — one
  Application would go unhealthy and you would not immediately know which half caused it.
- *A Helm-managed Secret with values from CI* — puts plaintext in the CI system and in the release
  history. Excluded by the repo's one secret rule.

**Consequences:**
- Credentials are reviewable on their own: a PR touching `secrets/staging/` touches nothing else.
- Two Applications must both be Healthy for the app to work, and a missing Secret presents as a
  CrashLoopBackOff in `revealroll` while `revealroll-secrets` looks fine. Worth knowing before 2 a.m.
- Only the SealedSecret is ever committed. The plaintext Secret the controller derives from it must
  never be, or Argo and the controller will each keep rewriting it and the app will flap OutOfSync.

---

## 013 — Bootstrap is two applies: AppProjects, then the root app

**Date:** 2026-08-17
**Status:** accepted

**Context:** The app-of-apps (`gitops/root-app.yaml`) is declared in project `platform`, and the
`platform` AppProject is itself a file under `gitops/` — so the root app is supposed to create the
project it belongs to. Argo validates an Application's project reference *before* it reads the
repository, so the first `kubectl apply -f gitops/root-app.yaml` landed as
`Unknown / Unknown` with `InvalidSpecError: Application referencing project platform which does not
exist`. It cannot create its way out of that.

**Decision:** the documented bootstrap is `kubectl apply -f gitops/projects/` followed by
`kubectl apply -f gitops/root-app.yaml`. Both project files stay in Git; root-app adopts them on its
first sync and owns them from then on. The manual apply is a one-time seed, not an ongoing exception.

**Alternatives considered:**
- *Put root-app in the built-in `default` project* — one command instead of two, and the ordering
  problem disappears because `default` always exists. Rejected because `default` permits every source
  repo, every destination and every resource kind: the one Application with authority over all the
  others would be the one with no boundary on it.
- *Sync waves on the project files* — waves order resources *within* a sync, and this failure happens
  before the sync starts. Wrong tool.

**Consequences:**
- Rebuilding the cluster from scratch is two applies, and they must be in that order. Written down
  here because it is exactly the kind of step that gets lost between rebuilds.
- The recovery path is unchanged and still works: `kubectl apply -f gitops/root-app.yaml`, then
  `argocd app sync root-app --force`.
- `root-app` deliberately carries no `resources-finalizer` — deleting it must not cascade into
  deleting every Application and therefore the platform.

---

## 014 — Code quality gate: self-hosted SonarQube, not SonarCloud

**Date:** 2026-09-02
**Status:** accepted

**Context:** The pipeline had gates for types, tests, manifests and secrets, but nothing
looking at the code itself. Adding one is straightforward; where it runs is the decision.

**Decision:** SonarQube Community Build, self-hosted in this cluster via Argo CD, with its
own PostgreSQL as plain manifests, gating the image build in `tutac/revealroll`.

**Alternatives considered:**
- *SonarCloud* — zero infrastructure, free for public repos, working in an afternoon. It
  is the correct answer for a team that wants the gate and not the operational exercise.
  Rejected because this environment exists to *be operated*: SonarQube is the first
  component here that is stateful, memory-hungry and on the deploy path at once, which
  makes it the most instructive thing in the repository to run.
- *The Bitnami PostgreSQL chart* — Bitnami moved its public catalogue to `bitnamilegacy`
  images during 2025. A Helm release whose image can be withdrawn is not a dependency
  worth taking for one internal consumer. One StatefulSet using the official image is
  ~70 lines and cannot be taken away.
- *Developer Edition* — would give pull-request decoration. Not free, and the gate on
  `main` is the part that actually blocks a bad deploy.

**Consequences:**
- **Community Build analyses one branch.** The gate protects `main`; individual pull
  requests are not annotated. Known limitation, not a misconfiguration.
- **Memory is the real risk.** Three JVMs in one pod on a node that already runs
  Prometheus, Loki and the app. Heaps are pinned in the values file well below the
  chart's defaults (512m web, 512m CE, 768m search against defaults of 1G/2G/2G) and the
  pod is capped at 3Gi. The chart's default ephemeral-storage *limit* of 512000M would
  also make the pod unschedulable on a 100 GB disk; it is overridden. If the node starts
  evicting pods, the rollback is deleting the Application and reverting these commits —
  SonarQube is the component this cluster can most afford to lose.
- **The host sysctl went to Ansible, not to the chart.** The chart's default is a
  privileged init container running as uid 0 to set `vm.max_map_count`. Setting it in
  `roles/common` instead keeps the layer rule intact and means this cluster runs no
  privileged container at all. The cost is a real ordering dependency: the Ansible run
  must happen before the first sync, or Elasticsearch fails its bootstrap check.
- **The instance is publicly reachable**, because GitHub-hosted runners must reach it.
  Forced authentication and a strong admin password are the compensating controls; a
  self-hosted runner inside the network is the answer that would remove the exposure, and
  is what a regulated environment would require.
- **Its PVCs are node-local.** A lost node loses analysis history, which is rebuildable by
  re-scanning. Accepted rather than adding a `pg_dump` job to the etcd backup path — worth
  revisiting if the instance ever holds anything that is not reproducible from source.
- **The admin password is deliberately not in Git.** The chart's password-setting Job
  re-runs on every sync and fails 401 once the password has changed, leaving the
  Application permanently Degraded. It is set at first login and kept in the password
  manager, which means it is also the one credential here that a cluster rebuild cannot
  restore.



---

## Template for new entries

```markdown
## NNN — <short decision title>

**Date:** YYYY-MM-DD
**Status:** accepted | superseded by NNN

**Context:** what forced a choice — constraints, costs, what was already true.

**Decision:** what you chose, specifically.

**Alternatives considered:**
- *Option* — what it offered, and the real reason you rejected it.

**Consequences:** what this makes easy, what it makes hard, and what you now have
to remember forever.
```
