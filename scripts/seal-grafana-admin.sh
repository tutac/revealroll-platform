#!/usr/bin/env bash
#
# Seal Grafana's admin credentials so they live in Git encrypted, like everything else.
#
#   ./scripts/seal-grafana-admin.sh                 # generate a strong password
#   GRAFANA_PASSWORD='…' ./scripts/seal-grafana-admin.sh
#
# The generated password is printed ONCE, here, and never written to disk in plaintext.
# Put it in your password manager before closing the terminal -- the sealed file cannot be
# decrypted by you, only by the controller in the cluster.
#
# Sibling of seal-env.sh and seal-registry.sh. Separate file because a SealedSecret is
# bound to one namespace and one name: this one is monitoring/grafana-admin, and copying
# it anywhere else simply will not decrypt.
set -euo pipefail

NAMESPACE="${NAMESPACE:-monitoring}"
SECRET_NAME="${SECRET_NAME:-grafana-admin}"
ADMIN_USER="${GRAFANA_USER:-admin}"
OUT="secrets/monitoring/grafana-admin-sealed.yaml"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

die() { printf '\nERROR: %s\n\n' "$*" >&2; exit 1; }

command -v kubeseal >/dev/null || die "kubeseal not installed.  brew install kubeseal"

PASSWORD="${GRAFANA_PASSWORD:-}"
GENERATED=0
if [[ -z "$PASSWORD" ]]; then
  # Grafana's admin account is not behind SSO here, so it is only as good as this string
  # -- do not hand-type a memorable one.
  #
  # NOT `tr -dc … </dev/urandom | head -c 32`: head exits at 32 bytes, /dev/urandom never
  # ends, so tr dies of SIGPIPE and `set -o pipefail` kills the script at exit 141 before
  # anything is written. Every command here terminates on its own.
  PASSWORD="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-32)"
  GENERATED=1
fi

(( ${#PASSWORD} >= 16 )) \
  || die "password is only ${#PASSWORD} characters. Refusing to seal a weak Grafana admin credential."

echo "→ sealing ${NAMESPACE}/${SECRET_NAME} for user '${ADMIN_USER}'"

mkdir -p "$(dirname "$OUT")"

# Plaintext goes stdout-to-stdin only; it never touches the filesystem.
kubectl create secret generic "$SECRET_NAME" \
    --namespace "$NAMESPACE" \
    --from-literal=admin-user="$ADMIN_USER" \
    --from-literal=admin-password="$PASSWORD" \
    --dry-run=client -o yaml \
  | kubeseal --format yaml \
      --controller-name sealed-secrets-controller \
      --controller-namespace kube-system \
  > "${OUT}.tmp"

grep -q 'encryptedData' "${OUT}.tmp" \
  || { rm -f "${OUT}.tmp"; die "kubeseal produced no encryptedData. Is the tunnel up and the controller running?"; }

# The one check that matters before a file goes to a PUBLIC repository.
if grep -qF "$PASSWORD" "${OUT}.tmp"; then
  rm -f "${OUT}.tmp"
  die "the password appears in plaintext in the sealed output — NOT writing it."
fi

mv "${OUT}.tmp" "$OUT"

cat <<EOF

✓ wrote $OUT

  Grafana:  https://grafana.stg.revealroll.com
  user:     ${ADMIN_USER}
EOF

if (( GENERATED )); then
  cat <<EOF
  password: ${PASSWORD}

  ^ shown once. Save it in your password manager NOW.
EOF
fi

cat <<EOF

  Argo CD deploys it via gitops/apps/monitoring-secrets.yaml — commit and push, do not
  kubectl apply. Changing the password later is: re-run this script, commit, push.

EOF
