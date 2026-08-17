#!/usr/bin/env bash
#
# Post-deploy smoke test: is the site actually serving, on a certificate that will still
# be valid next week?
#
#   ./scripts/smoke.sh                              # https://stg.revealroll.com
#   ./scripts/smoke.sh https://stg.revealroll.com   # explicit
#   CERT_MIN_DAYS=30 ./scripts/smoke.sh             # stricter expiry margin
#
# Exits non-zero on the first failure, so it works as a CI gate (Stage 09 runs it after
# Argo CD reports Synced/Healthy) and as the first thing you run during an incident.
#
# It deliberately uses NO cluster credentials. Everything here is what a user sees from
# the outside: DNS, ingress, TLS, and HTML. A check that needs kubectl cannot tell you
# whether the site is up -- it can only tell you what the cluster believes.
set -euo pipefail

URL="${1:-https://stg.revealroll.com}"
HOST="${URL#https://}"
HOST="${HOST%%/*}"
CERT_MIN_DAYS="${CERT_MIN_DAYS:-14}"

pass() { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*" >&2; exit 1; }

printf '\nsmoke: %s\n\n' "$URL"

# ── 1. HTTP 200 ────────────────────────────────────────────────────────────────
#
# No -k. An invalid certificate must fail this script, not be worked around by it --
# that is half of what is being tested. --max-time bounds a hung ingress; without it a
# CI job waits forever instead of failing.
BODY="$(mktemp)"; trap 'rm -f "$BODY"' EXIT

code="$(curl -sS --max-time 20 -o "$BODY" -w '%{http_code}' "$URL")" \
  || fail "could not connect to ${URL} (DNS, ingress, or TLS -- curl said so above)"

[[ "$code" == "200" ]] \
  || fail "${URL} returned HTTP ${code}, expected 200"
pass "HTTP 200"

# ── 2. It is OUR app, not someone's default page ───────────────────────────────
#
# 200 alone is a weak assertion: an ingress misroute, a stale cached page, or nginx's
# own welcome page all return 200. Two markers, because either alone has a plausible
# false pass -- the title could survive a broken build, and _next/static appears on any
# Next.js site including the Vercel production one if DNS ever pointed there.
grep -qi '<title>RevealRoll' "$BODY" \
  || fail "response is a 200 but does not look like RevealRoll (wrong backend? cached error page?)
  first line was: $(head -c 120 "$BODY")"
pass "page identifies as RevealRoll"

grep -q '/_next/static' "$BODY" \
  || fail "no /_next/static references -- the Next.js build did not render"
pass "Next.js assets referenced"

# ── 3. Certificate valid, and not about to expire ──────────────────────────────
#
# -checkend does the arithmetic inside openssl. The obvious alternative -- parsing
# `x509 -enddate` with date(1) -- needs `date -d` on Linux and `date -j -f` on macOS,
# so it breaks on whichever machine you did not write it on. This runs on both.
cert="$(echo | openssl s_client -connect "${HOST}:443" -servername "$HOST" 2>/dev/null)" \
  || fail "could not complete a TLS handshake with ${HOST}:443"

echo "$cert" | openssl x509 -noout -checkend "$(( CERT_MIN_DAYS * 86400 ))" >/dev/null \
  || fail "certificate for ${HOST} expires within ${CERT_MIN_DAYS} days -- check cert-manager:
  kubectl get certificate,order,challenge -A"

enddate="$(echo "$cert" | openssl x509 -noout -enddate | cut -d= -f2)"
issuer="$(echo "$cert" | openssl x509 -noout -issuer | sed 's/.*CN *= *//')"
pass "cert valid > ${CERT_MIN_DAYS}d (expires ${enddate}, issuer ${issuer})"

# A staging-issuer certificate is untrusted by browsers, so curl above would already
# have failed -- but say it out loud, because "it works with -k" is how people ship it.
case "$issuer" in
  *STAGING*|*staging*) warn "issued by a Let's Encrypt STAGING issuer -- browsers will reject it" ;;
esac

# ── 4. Deep health, reported but NOT fatal ─────────────────────────────────────
#
# /api/health queries Supabase and checks cron liveness, so it returns 503 for reasons
# that have nothing to do with whether the site serves traffic -- the same argument that
# keeps it out of the k8s probes (see charts/revealroll/values.yaml). Failing a deploy
# gate on it would mean a Supabase blip blocks a rollback. Reported, never fatal.
health="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "${URL%/}/api/health" || echo 000)"
case "$health" in
  200) pass "/api/health 200" ;;
  000) warn "/api/health unreachable — informational only" ;;
  *)   warn "/api/health ${health} — app is serving, but a dependency is unhappy. Check Supabase and cron freshness." ;;
esac

printf '\n✓ smoke passed: %s\n\n' "$URL"
