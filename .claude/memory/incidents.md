# Incident Log

Every outage, every game day, every "why is this broken" that cost you more than fifteen minutes.

**This file is the actual product of the project.** Anyone can build a cluster. A written record of
things that broke, how long you took to notice, and what you changed afterwards is what separates
"I did a tutorial" from "I've operated this." In an interview, "tell me about a time something broke"
is a question you will be able to answer from notes rather than memory.

Write them up even when the cause is embarrassing. *Especially* then — those are the ones you
remember, and the blameless framing is a habit worth building while the only person to blame is you.

---

## How to write an entry

Copy the template at the bottom. Four fields do most of the work:

- **Detected** — *how* you found out, and how long after it started. If the answer is "I noticed by
  accident," that's the most valuable line in the entry: it means your monitoring missed it.
- **Root cause** — the actual mechanism, not the symptom. "The pod died" is a symptom. "The liveness
  probe timeout was shorter than the app's cold-start time under memory pressure" is a cause.
- **What would have caught this sooner** — this is where the next alert or runbook comes from.
- **Action items** — with dates, and closed out when done. An incident with no action item was either
  trivial or under-analysed.

**MTTD** = time from the problem starting to you knowing.
**MTTR** = time from you knowing to service restored.
Estimate honestly rather than leaving them blank; a rough number you can defend beats no number.

---

## Entries

*(newest first)*

## 2026-08-12 — SSH stopped listening on staging-1 immediately after the first hardening run

**Type:** real incident
**Severity:** total loss of remote administration (no user impact — nothing is served from this
host yet)

**Detected:** immediately, and by luck rather than design. `site.yml` finished clean
(`ok=49 changed=24 failed=0`), and a verification probe from a second machine got
`Connection refused` on port 22 seconds later. Nothing on the host reported a problem: the
playbook's own `99-verify.yml` had already passed, because it asserts on `sshd -T` output —
the *configuration* sshd would use — not on whether anything is actually bound to the port.

**Impact:** ~15 minutes with no new SSH logins possible. An already-open `deploy` session
survived (established connections belong to an already-forked child) and was the only route
back in.

**Timeline:**
- 21:5x — `ansible-playbook site.yml` completes successfully, 24 changed
- +0m — external probe returns `Connection refused` on 22 (host up, firewall passing: a
  default-drop rule would have timed out, so a RST meant nothing was listening)
- +2m — recovery attempted through the still-open session
- +5m — `systemctl start ssh.socket` issued
- +15m — SSH restored from the operator's terminal

**Root cause:** the `ssh-hardening` role wrote `/etc/systemd/system/ssh.socket.d/override.conf`
containing `ListenStream=` followed by `ListenStream=22`. The empty assignment clears the vendor
unit's listener list — which defines a *pair* of sockets, IPv4 and IPv6 — and the single
replacement bound **IPv6 only**. Every IPv4 connection then got a TCP RST, which surfaces as
`Connection refused`. The host looked healthy from inside throughout: `sshd -T` was correct,
nftables had `tcp dport 22 accept`, the fail2ban ban set was empty, and `ss` showed a listener —
just `[::]:22` with no `0.0.0.0:22` beside it. That missing second line was the whole incident.

The override should never have been written at all: the configured port was 22, which is what the
vendor unit already listens on. A change with no effect still carries all of its risk.

A second, latent bug was found while debugging: the role notified both a `Restart sshd` handler
(starting `ssh.service`) and a `Restart ssh socket` handler, and on a socket-activated host those
two units conflict over the port. It did not cause this outage but would eventually have caused
one of its own.

**Diagnostic note — why this took 15 minutes instead of 2:** `Connection refused` and
`Connection timed out` mean different things and we reasoned from that correctly (a `policy drop`
firewall times out; an RST means something answered). But the first two hypotheses — a fail2ban
ban, then a provider-level firewall — were both plausible and both wrong, and each took a round
trip to disprove. The evidence that identified the cause was in the very first `ss` output:
one address family where there should have been two.

**Fix:** removed `override.conf` from the surviving session, `daemon-reload`, stopped
`ssh.service`, restarted `ssh.socket` — `ss` then showed both `0.0.0.0:22` and `[::]:22` and
access returned. Then in the role: both handlers now
`listen: Restart ssh` and are mutually exclusive on a `ssh_hardening_socket_activated` fact, so
exactly one runs; and the port override is only written when the configured port actually
differs from 22, and is removed otherwise.

**MTTD:** ~0m (probe was already running) **MTTR:** ~15m

**What would have caught this sooner:** `99-verify.yml` validated intent, not reality. It read
`sshd -T` and never asked whether port 22 was *bound*. A `wait_for` on the port from the control
node would have failed the run at the moment of breakage instead of passing while SSH was down.
**Validating configuration is not validating service** — and note that even an on-host `ss` check
would have passed here, because a listener did exist. Only a probe from *outside*, over IPv4,
distinguishes "a socket is open" from "the socket users need is open."

**What went well:** the second SSH session was open before the hardening run, exactly as the
stage instructions require, and it was the entire reason this was a 15-minute annoyance rather
than a trip through the Contabo rescue system — which had already cost an hour earlier the same
day, before any key existed on the box.

**Action items:**
- [x] Make the ssh restart handlers mutually exclusive — done 2026-08-12
- [x] Stop writing a socket port override when the port is unchanged — done 2026-08-12
- [ ] Add a port-reachability assertion to `99-verify.yml` (`wait_for` port 22 from the control
      node, plus `ss -ltn` on the host) — by 2026-08-19
- [ ] Add the workstation IP to `fail2ban_ignoreip`; repeated probes during the outage tripped
      the `maxretry 3` jail and the reject action made diagnosis harder — by 2026-08-19

---

## 2026-08-17 — Everything on 80/443 refused after a routine Ansible run

**Type:** real incident
**Severity:** total outage — `stg.revealroll.com`, `argocd.stg`, and `grafana.stg` all unreachable
from the internet, while the cluster reported itself entirely healthy

**Detected:** by accident, ~20 minutes in, and not by anything designed to detect it. A `curl`
against the newly-created Grafana hostname failed; the first assumption was that Grafana's ingress
or certificate was wrong. Only when the *app's* hostname failed the same way did it become clear
this was not about Grafana at all. Nothing alerted, and `kubectl` showed a green cluster the entire
time: every pod `Running`, node `Ready`, no memory or disk pressure, ingress-nginx up for 2d23h
with zero restarts.

**Impact:** total loss of public access for roughly 20 minutes. Nothing inside the cluster was
damaged or restarted; the site was simply unreachable.

**Timeline:**
- ~16:10 — `make ansible-site` run to apply the node-exporter rebind (Stage 08.1)
- ~16:10 — public access to 80/443 stops. No signal anywhere.
- 16:33 — `curl https://grafana.stg.revealroll.com` fails; suspected a Grafana ingress/cert problem
- 16:34 — the app and Argo CD hostnames fail identically → not Grafana, and not TLS
- 16:35 — raw TCP to `:80` and `:443` refused; cluster confirmed healthy, so the fault is on the host
- 16:36 — `nft list table ip nat` on the host: `KUBE-*` chains present, **zero `CNI-HOSTPORT` chains**
- 16:38 — `kubectl rollout restart daemonset ingress-nginx-controller` → access restored
- 16:45 — template fixed, `make ansible-site` re-run, `smoke.sh` still passing → fix confirmed

**Root cause:** `roles/firewall/templates/nftables.conf.j2` began with `flush ruleset`, which
deletes **every** nftables table on the host, not only the one Ansible owns. ingress-nginx reaches
the internet through `hostPort` 80/443, which is implemented by the CNI portmap plugin as DNAT
rules in `table ip nat`. Those rules are written **once, when the pod sandbox is created, and never
reconciled**. Flushing them is therefore permanent until something recreates the pod.

What made this invisible for so long is that almost everything else the flush destroyed *does*
self-heal: kube-proxy continuously rebuilds its `KUBE-*` chains within seconds. So the ruleset
looks correct moments later, and the only casualty is the one component whose rules nobody rewrites.

This has almost certainly happened on **every `site.yml` run since k3s was installed in Stage 03**.
It went unnoticed because until Stage 06 there was nothing behind the ingress to notice, and
because ingress-nginx pods were being recreated frequently while the platform was being built.

**Fix:** the template now declares and deletes only its own table (`table inet filter` /
`delete table inet filter`) instead of flushing the ruleset. Declaring before deleting keeps it
idempotent on a host where the table does not exist yet. Verified by re-running `site.yml` and
confirming both that `smoke.sh` still passes and that the `CNI-HOSTPORT` chains survive.

**MTTD:** ~20m (accidental) **MTTR:** ~5m once correctly identified, ~3m of that being the pod restart

**What would have caught this sooner:** anything probing the site from **outside** the cluster.
Every signal available at the time was internal, and every internal signal said "healthy" — this is
the textbook case for black-box monitoring, and it is a far better argument for Stage 08.3 and
08.10 than the course text's. A `wait_for` on 443 from the control node at the end of `site.yml`
would have failed the run at the moment of breakage, which is the same lesson the 2026-08-12 SSH
incident produced and the same action item still open from it.

**Diagnostic note:** the first hypothesis was resource pressure from the monitoring stack that had
just been installed — plausible, since the outage coincided with it, and wrong. `kubectl describe
node` disproved it in one command (34% memory requested, no pressure conditions). Coincidence in
time is the weakest form of evidence and it was the first thing reached for.

**What went well:** `scripts/smoke.sh`, written the same afternoon, was what confirmed both the
breakage and the fix. A one-command answer to "is the site actually up?" is worth writing before
you need it.

**Action items:**
- [x] Stop flushing the whole ruleset in `roles/firewall` — done 2026-08-17
- [ ] Add an external `wait_for` on 443 to the end of `site.yml`, so an Ansible run that breaks
      public access fails loudly — by 2026-08-24
- [ ] Blackbox-exporter probe of `https://stg.revealroll.com` with an alert (Stage 08.3) — by 2026-08-24
- [ ] External uptime check that survives the whole node dying (Stage 08.10) — by 2026-08-24
- [ ] Check whether anything else on this host depends on rules written once and never reconciled
      (k3s servicelb is disabled, so hostPort is believed to be the only one) — by 2026-08-24

---

## Planned game days (Stage 10)

Tick these off as you run them. Write the hypothesis **before** you break anything — otherwise you
can't be surprised, and being surprised is the entire point.

| | Drill | Hypothesis (fill in before running) | Run on |
|---|---|---|---|
| `[ ]` | 10.5 Full restore drill — destroy k3s, rebuild from backup + Git | | |
| `[ ]` | 10.6 Kill the node under load | | |
| `[ ]` | 10.7 Fill the disk | | |
| `[ ]` | 10.8 Revoke the Supabase key | | |
| `[ ]` | 10.9 Ship a deliberately broken image | | |

Recurring cadence once the build is done: **a game day monthly, a restore drill quarterly.**

---

## Measurements

Keep the current best numbers here so they're easy to find when updating your CV.

| Metric | Value | Measured on | From |
|---|---|---|---|
| MTTD — crash-looping pod | | | game day 10.6/10.9 |
| MTTR — bad deploy rollback | | | game day 10.9 |
| RTO — full cluster rebuild | | | restore drill 10.5 |
| Lead time — push → live | | | Stage 09.5 |

---

## Template

```markdown
## YYYY-MM-DD — <one-line title, symptom-first>

**Type:** game day | real incident
**Severity:** total outage | degraded | no user impact

**Detected:** how you found out, and how long after it began.

**Impact:** what a user would have experienced, and for how long.

**Timeline:**
- HH:MM — what happened
- HH:MM — first signal
- HH:MM — you started looking
- HH:MM — cause identified
- HH:MM — mitigated
- HH:MM — resolved

**Root cause:** the mechanism, not the symptom.

**Fix:** what you actually did.

**MTTD:** Xm  **MTTR:** Xm

**What would have caught this sooner:**

**What went well:** (there's always something — say it)

**Action items:**
- [ ] <thing> — by YYYY-MM-DD
```
