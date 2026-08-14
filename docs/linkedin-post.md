# LinkedIn post kit — RevealRoll staging platform

## Context

Copy for a personal LinkedIn post about this platform: post text, an image-generation prompt for the
architecture diagram, and a long-form project description (how it's used, the tooling, the cost).

Editorial decisions baked in:
- **Angle:** build-in-public and honest — Stage 01 complete, Ansible ~80%, of a 10-stage plan. The
  post says so rather than implying the whole thing is running.
- **Naming:** RevealRoll and `stg.revealroll.com` are named openly; infrastructure *vendors* stay
  soft ("a €13/month European VPS", "S3-compatible object storage"). Swaps to name them are below.
- **Diagram:** clean flat vector, dark background.

Everything below is copy to paste. Nothing here is executed by CI.

---

## 1. The LinkedIn post

> Two notes before pasting: LinkedIn cuts the preview at roughly the first 140 characters, so the
> first two lines carry the whole click. And LinkedIn strips markdown — the copy below is written
> with plain characters and line breaks only, no `**bold**`, no bullets that need rendering.

```
Production runs on Vercel. One click, it just works.

So I spent the last month rebuilding the same app the hard way — on a single €13/month VPS I have to
operate myself.

Here's why that's not a waste of time.

RevealRoll's production deploy is a managed platform doing the thinking for me. That's the right
call for production. It's a terrible way to learn what the platform is actually doing.

So I'm building the staging environment (stg.revealroll.com) as a real, self-managed platform:

→ Terraform for the infrastructure — the box and its state
→ Ansible for the machine — users, SSH hardening, nftables default-drop, fail2ban, k3s
→ Terraform again, once, for the four things Argo CD needs to exist: ingress-nginx, cert-manager,
   sealed-secrets, and Argo CD itself
→ Argo CD for everything after that — the app, Prometheus, Grafana, Loki, dashboards, alerts

The rule I keep coming back to: every component belongs to exactly one layer. Ansible can run
helm install. Terraform has a kubectl provider. Both are traps. Each layer reconciles differently —
Terraform on demand, Ansible on demand, Argo CD continuously — so a resource with two owners
becomes a fight you didn't schedule, at 2am, on the thing you touched last.

Deploying is a commit. CI builds ghcr.io/…:sha-<commit>, writes that tag into one line of a values
file in the platform repo, and Argo CD picks it up. "What's running in staging?" is answered by
reading one file. Rollback is git revert.

Where I actually am: infrastructure layer done, machine layer about 80%. Cluster bootstrap,
observability, and the SRE work — SLOs, burn-rate alerts, runbooks, game days — are still ahead.
Ten stages, three of them behind me.

The part I'm most looking forward to is the last one: breaking it on purpose, on a schedule, and
writing down how long it took me to notice. Anyone can build this. Far fewer can tell you their
MTTD.

Total running cost: about €14/month and a domain.

Building in public — I'll post the failures too. There will be failures.

#DevOps #SRE #Kubernetes #Terraform #GitOps #ArgoCD #Ansible #PlatformEngineering
```

**Length:** ~1,900 characters — inside LinkedIn's 3,000 limit, long enough to signal substance.

**Optional swaps:**
- To name vendors (more credible cost, less privacy): replace "a single €13/month VPS" with
  "a single Contabo VPS", and add "Cloudflare R2 for state and backups, Supabase for the database".
- Softer opener if the current one feels too punchy:
  `"My production deploy is one click. I just spent a month rebuilding the same app the hard way."`

**Engagement mechanics that matter more than the copy:**
- Post Tue–Thu, 08:00–10:00 your local time.
- Put nothing but the image in the post; no external link in the body (LinkedIn suppresses reach on
  posts with outbound links). If you want to share the repo, put it in the **first comment**.
- Reply to every comment in the first 90 minutes — early comment velocity drives the feed.
- End-of-post question alternative to the last line, if you want more comments:
  `"If you've run k3s on a single node in anger — what broke first for you?"`

---

## 2. Diagram image prompt

Paste this into Claude (or any image model). **Important:** image models garble long text, so this
prompt deliberately uses very few, very short labels and asks for large type. Generate 2–3 variants
and pick the one whose text came out clean.

```
Create a clean, flat-vector technical architecture diagram for a LinkedIn post. Landscape,
1200x628 pixels, dark background (#0F1720 deep navy), no photorealism, no 3D, no glow, no gradients
beyond a subtle one. Style: modern developer-documentation illustration — thin 2px rounded-rectangle
outlines, generous negative space, crisp geometric sans-serif type, large and highly legible.

Layout: four horizontal bands stacked top to bottom, each a wide rounded rectangle, connected by
thin downward arrows on the left side. Each band has a small number badge on its left edge and a
short title, with two or three tiny icon+word items inside it.

Band 1, badge "1", title "TERRAFORM", accent color soft violet (#8B7FD4).
Items: "VPS", "State".

Band 2, badge "2", title "ANSIBLE", accent color warm coral (#E8836B).
Items: "Hardening", "Firewall", "k3s".

Band 3, badge "3", title "BOOTSTRAP", accent color soft amber (#E0B25C).
Items: "Ingress", "Certs", "Secrets", "Argo CD".

Band 4, badge "4", title "GITOPS", accent color mint green (#5FC9A0), drawn slightly larger than the
others to signal it owns the most.
Items: "App", "Metrics", "Logs", "Alerts".

To the right of the four bands, set apart with clear space, draw a single tall rounded rectangle
outlined in mint green labelled "k3s" at the top, containing four small evenly spaced boxes
labelled "app", "prometheus", "grafana", "loki". A thin arrow curves from band 4 into this box.

A small curved arrow loops from band 4 back onto itself, suggesting continuous reconciliation.

Text rules: use ONLY the words listed above, spelled exactly, all uppercase for band titles and
lowercase for item labels. No other text anywhere. No paragraphs, no captions, no watermark, no
logos, no company marks. Every word must be sharp and correctly spelled.

Overall feel: calm, precise, engineering-grade. Something that looks like it came out of a real
platform team's design system, not out of an AI image generator.
```

**If the generated text comes out wrong** (the usual failure): fall back to a real diagram instead
of a generated one. The mermaid source already exists in this repo at `README.md` lines 18–29 and
`docs/architecture.md`. The `excalidraw` skill in this session can render mermaid to a clean
Excalidraw canvas and export a PNG — accurate labels, hand-drawn-but-professional look, ~5 minutes.
That is the safer path if you want the diagram to be *correct* as well as pretty.

---

## 3. Project description (long form)

For the repo README's intro, a portfolio page, the "Featured" section of your LinkedIn profile, or
the first comment on the post.

### What it is

RevealRoll is a Next.js application. Production runs on Vercel — managed, fast, and boring, which is
what production should be. This project is its **staging environment**, deliberately rebuilt as a
self-managed platform on a single VPS running k3s, so that there is a system I own end to end:
provision it, harden it, deploy to it, watch it, break it, and restore it.

The application code lives in one repository. This platform repository holds no application code at
all — only Terraform, Ansible, Helm charts, Argo CD manifests, dashboards, alerts, and runbooks.
That separation is the point: infrastructure has its own lifecycle, its own review, its own history.

### How I use it

- Every push to the app repo builds an image tagged `sha-<commit>`, never `latest`, and CI commits
  that tag into a single line of a values file in the platform repo.
- Argo CD notices the commit and reconciles the cluster. I never run `kubectl apply` or
  `helm upgrade` by hand — if it isn't in Git, Argo CD deletes it.
- "What is running in staging?" is answered by reading one line of one file. Rollback is
  `git revert` of the bump commit.
- Grafana, Prometheus, Loki and Alertmanager run in the same cluster; node-exporter runs on the host
  via Ansible rather than Helm, so host metrics survive the cluster being the broken thing.
- Every alert links to a runbook written *before* the alert was created. Every incident gets written
  up with a measured detection time and the answer to "what would have caught this sooner?"

### The tooling — all open source, no paid tier anywhere

| Layer | Tool | Job |
|---|---|---|
| Infrastructure | **Terraform** | the VPS, and remote state |
| Machine | **Ansible** | deploy user, SSH hardening, nftables default-drop, fail2ban, unattended-upgrades, journald caps, k3s |
| Kubernetes | **k3s** | single-node cluster, Traefik and servicelb disabled |
| Ingress | **ingress-nginx** | hostPort 80/443, `externalTrafficPolicy: Local` to preserve client IPs |
| TLS | **cert-manager** | Let's Encrypt HTTP-01, staging and prod issuers |
| Secrets | **Sealed Secrets** | encrypted secrets committed to Git, decrypted only in-cluster |
| Delivery | **Argo CD** | app-of-apps, self-managing, continuous reconciliation |
| Packaging | **Helm** | one chart for the app |
| Metrics | **Prometheus + Grafana** | golden signals, SLO burn-rate alerts |
| Logs | **Loki + Grafana Alloy** | 7-day retention |
| Alerting | **Alertmanager** | every alert carries a `runbook_url` |
| CI | **GitHub Actions** | build, scan, bump the tag |
| Quality gates | ansible-lint, tflint, helm lint, kubeconform, gitleaks | run locally and in CI |

Nothing in that list costs money. The only paid pieces are the machine it runs on and the domain.

### What it costs

| Item | Monthly |
|---|---|
| VPS — 4 vCPU / 8 GB RAM / 100 GB SSD | ~€13 |
| Object storage (Terraform state, etcd snapshots, log chunks) | €0 — inside the free tier |
| Container registry | €0 — free for this usage |
| Database (managed Postgres, staging project) | €0 — free tier |
| DNS | €0 — included with the domain |
| Domain | ~€1 (≈€12/year, shared with production) |
| TLS certificates | €0 — Let's Encrypt |
| External uptime check | €0 — free tier |
| **Total** | **≈ €14/month** |

> Verify the VPS line against your actual invoice before posting — the €13 figure is the list price
> for that tier, not a number read off your bill. Everything else is genuinely €0 at this scale.

For comparison: the smallest realistic managed-Kubernetes equivalent (control plane + one node +
load balancer) lands around €70–100/month, and removes exactly the layers this project exists to
teach.

### Where it stands

Ten stages planned. Stage 01 (infrastructure) is complete; Stage 02–03 (machine hardening and k3s
via Ansible) are roughly 80% done. Cluster bootstrap, GitOps handover, observability, the CI/CD
pipeline, and the SRE practice stage — SLOs, error budgets, burn-rate alerting, restore drills, and
scheduled game days — are still ahead.

The last stage is the one that matters most and the one most portfolios skip: deliberately breaking
the system on a schedule and writing down how long it took to notice.

---

## Checklist before posting

1. Confirm the VPS price against a real invoice (see the note under the cost table).
2. Generate the diagram, then read every word in the image out loud. If any label is misspelled,
   regenerate or switch to the Excalidraw path described in section 2.
3. Paste the post into the LinkedIn composer and check where the "…see more" cut lands — it should
   fall after the second line, not before.
4. Confirm `stg.revealroll.com` resolves and looks presentable if anyone actually visits it. If it
   isn't up yet, drop the hostname from the post and just say "the staging environment".
