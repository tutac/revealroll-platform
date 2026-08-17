#!/usr/bin/env bash
#
# Seal the ntfy topic Alertmanager pushes alerts to.
#
#   ./scripts/seal-ntfy.sh                    # generate a random topic
#   NTFY_TOPIC=my-topic ./scripts/seal-ntfy.sh
#
# The topic name IS the credential: ntfy.sh has no accounts, so anyone who knows the topic
# can read every alert this cluster sends -- hostnames, namespaces, what is broken and
# when. That is why it is generated long and random, sealed, and never committed in clear.
#
# Alertmanager reads it from a FILE (webhook_configs.url_file) rather than having it
# inlined in the config. That keeps the routing tree readable in Git while the destination
# stays secret -- the alternative, sealing the whole Alertmanager config, would make every
# routing change an opaque blob nobody can review.
set -euo pipefail

NAMESPACE="${NAMESPACE:-monitoring}"
SECRET_NAME="${SECRET_NAME:-alertmanager-ntfy}"
OUT="secrets/monitoring/ntfy-sealed.yaml"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

die() { printf '\nERROR: %s\n\n' "$*" >&2; exit 1; }

command -v kubeseal >/dev/null || die "kubeseal not installed.  brew install kubeseal"

TOPIC="${NTFY_TOPIC:-}"
GENERATED=0
if [[ -z "$TOPIC" ]]; then
  # Same SIGPIPE-safe construction as seal-grafana-admin.sh: every command terminates.
  SUFFIX="$(openssl rand -base64 24 | tr -dc 'a-z0-9' | cut -c1-20)"
  TOPIC="revealroll-staging-${SUFFIX}"
  GENERATED=1
fi

(( ${#TOPIC} >= 16 )) \
  || die "topic '${TOPIC}' is too short to be unguessable. ntfy has no auth; length is the only protection."

URL="https://ntfy.sh/${TOPIC}"

echo "→ sealing ${NAMESPACE}/${SECRET_NAME}"

mkdir -p "$(dirname "$OUT")"

kubectl create secret generic "$SECRET_NAME" \
    --namespace "$NAMESPACE" \
    --from-literal=url="$URL" \
    --dry-run=client -o yaml \
  | kubeseal --format yaml \
      --controller-name sealed-secrets-controller \
      --controller-namespace kube-system \
  > "${OUT}.tmp"

grep -q 'encryptedData' "${OUT}.tmp" \
  || { rm -f "${OUT}.tmp"; die "kubeseal produced no encryptedData. Is the tunnel up and the controller running?"; }

if grep -qF "$TOPIC" "${OUT}.tmp"; then
  rm -f "${OUT}.tmp"
  die "the topic appears in plaintext in the sealed output — NOT writing it."
fi

mv "${OUT}.tmp" "$OUT"

cat <<EOF

✓ wrote $OUT

  Subscribe BEFORE the first alert fires:

    phone   — install the ntfy app, "+", subscribe to:  ${TOPIC}
    desktop — open ${URL}
    test it — curl -d "hello from $(hostname -s)" ${URL}

EOF

if (( GENERATED )); then
  cat <<EOF
  ^ shown once, and not recoverable from the sealed file. Save the topic in your password
    manager alongside the Grafana password.

EOF
fi
