#!/usr/bin/env bash
#
# Turn a local plaintext .env into a committable SealedSecret.
#
#   ./scripts/seal-env.sh [env-file] [namespace]
#   ./scripts/seal-env.sh .env.staging revealroll        # the defaults
#
# The plaintext Secret is never written to disk: kubectl renders it to stdout and it goes
# straight into kubeseal. A temp file here would be a temp file containing every credential
# the application has, and you would forget to delete it exactly once.
#
# Requires: kubeseal (brew install kubeseal), a reachable cluster (`make tunnel`).
set -euo pipefail

ENV_FILE="${1:-.env.staging}"
NAMESPACE="${2:-revealroll}"
SECRET_NAME="${SECRET_NAME:-revealroll-env}"
P8_FILE="${P8_FILE:-secrets/apns.p8}"
OUT="secrets/staging/revealroll-sealed.yaml"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

die() { printf '\nERROR: %s\n\n' "$*" >&2; exit 1; }

command -v kubeseal >/dev/null || die "kubeseal not installed.  brew install kubeseal"
[[ -f "$ENV_FILE" ]] || die "no such env file: $ENV_FILE
  It is gitignored on purpose; assemble it locally from your staging credentials."

# The file must be gitignored. Checking is cheap; discovering otherwise in a commit is not.
git check-ignore -q "$ENV_FILE" \
  || die "$ENV_FILE is NOT gitignored. Add it before putting real credentials in it."

# ── the guardrail ────────────────────────────────────────────────────────────────
# Staging holding production credentials is not a staging environment; it is a production
# incident with a misleading name. These are hard failures, not warnings: a warning in a
# pipeline you run twice a month is a line of output nobody reads. Override with FORCE=1
# only if you can say out loud why.
violations=()

grep -qE '^[A-Z0-9_]+=(sk|rk)_live_' "$ENV_FILE" && violations+=("a LIVE Stripe secret key (sk_live_/rk_live_)")
grep -qE '^[A-Z0-9_]+=pk_live_'      "$ENV_FILE" && violations+=("a LIVE Stripe publishable key (pk_live_)")
grep -qE '^APNS_ENV=production'      "$ENV_FILE" && violations+=("APNS_ENV=production — this sends real pushes to real devices")
grep -qE '^PROD_DATABASE_URL='       "$ENV_FILE" && violations+=("PROD_DATABASE_URL — must never exist in staging")

# NEXT_PUBLIC_APP_URL pointing anywhere but staging silently breaks QR codes and share links.
if grep -qE '^NEXT_PUBLIC_APP_URL=' "$ENV_FILE" \
   && ! grep -qE '^NEXT_PUBLIC_APP_URL=https://stg\.' "$ENV_FILE"; then
  violations+=("NEXT_PUBLIC_APP_URL is not https://stg.* — QR codes and share links will point elsewhere")
fi

if (( ${#violations[@]} > 0 )) && [[ "${FORCE:-0}" != "1" ]]; then
  printf '\nREFUSING TO SEAL — %s looks like production:\n\n' "$ENV_FILE" >&2
  printf '  • %s\n' "${violations[@]}" >&2
  printf '\nFix the file. If you are certain, re-run with FORCE=1.\n\n' >&2
  exit 1
fi

# ── build and seal ───────────────────────────────────────────────────────────────
# APNS_KEY_P8 is a multi-line PEM and --from-env-file cannot parse it, so it arrives as a
# separate --from-file into the same Secret. This is the detail that turns a 20-minute task
# into a 2-hour one when you meet it at the end instead of the start.
from_file_args=()
if [[ -f "$P8_FILE" ]]; then
  from_file_args+=(--from-file="APNS_KEY_P8=${P8_FILE}")
  echo "→ including multi-line APNS_KEY_P8 from ${P8_FILE}"
else
  echo "→ ${P8_FILE} not found; sealing without APNS_KEY_P8 (iOS push will not work)"
fi

key_count=$(grep -cE '^[A-Z0-9_]+=' "$ENV_FILE")
echo "→ sealing ${key_count} keys from ${ENV_FILE} into ${NAMESPACE}/${SECRET_NAME}"

mkdir -p "$(dirname "$OUT")"

kubectl create secret generic "$SECRET_NAME" \
    --namespace "$NAMESPACE" \
    --from-env-file="$ENV_FILE" \
    "${from_file_args[@]}" \
    --dry-run=client -o yaml \
  | kubeseal --format yaml \
      --controller-name sealed-secrets-controller \
      --controller-namespace kube-system \
  > "${OUT}.tmp"

# Never replace a good sealed file with a broken one. If encryptedData is missing, kubeseal
# emitted something that is not a SealedSecret -- most often an error from a cluster it
# could not reach, which would otherwise land here as a committable file full of nothing.
grep -q 'encryptedData' "${OUT}.tmp" \
  || { rm -f "${OUT}.tmp"; die "kubeseal produced no encryptedData. Is the tunnel up and the controller running?"; }

# Belt and braces: if any plaintext value survived into the output, stop.
if grep -qE '(sk_test_|sk_live_|eyJ[A-Za-z0-9_-]{20,})' "${OUT}.tmp"; then
  rm -f "${OUT}.tmp"
  die "plaintext-looking values found in the sealed output — NOT writing it. Inspect manually."
fi

mv "${OUT}.tmp" "$OUT"

cat <<EOF

✓ wrote $OUT  ($(grep -cE '^\s{4}[A-Z0-9_]+:' "$OUT") encrypted keys)

  Read it before committing — spec.encryptedData must be ciphertext, not your keys:
    less $OUT

  Then:
    kubectl apply -f $OUT
    kubectl get secret ${SECRET_NAME} -n ${NAMESPACE}

EOF
