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

*(newest first — nothing here yet. The first entry will probably be from Stage 02 or 03,
because that's where things start being able to break.)*

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
