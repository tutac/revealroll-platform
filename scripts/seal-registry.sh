#!/usr/bin/env bash
#
# Seal a GHCR pull credential so the cluster can pull private images from Git.
#
#   GHCR_TOKEN=ghp_xxx ./scripts/seal-registry.sh [namespace]
#   ./scripts/seal-registry.sh                      # falls back to `gh auth token`
#
# WHY this exists rather than `kubectl create secret docker-registry` by hand:
# a hand-created Secret lives only in the cluster. It is absent from Git, so Argo CD does
# not know about it, and it does not come back when the cluster is rebuilt -- which means
# the Stage 10 restore drill ends in ImagePullBackOff and a confused half hour. Sealing it
# makes the credential part of the desired state like everything else.
#
# Sibling of seal-env.sh: same crypto, different Secret TYPE. A dockerconfigjson Secret
# has a fixed key (.dockerconfigjson) that kubelet looks for by name, so it cannot simply
# be another entry in revealroll-env.
set -euo pipefail

NAMESPACE="${1:-revealroll}"
SECRET_NAME="${SECRET_NAME:-ghcr}"
REGISTRY="${REGISTRY:-ghcr.io}"
USERNAME="${GHCR_USER:-tutac}"
OUT="secrets/staging/ghcr-sealed.yaml"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

die() { printf '\nERROR: %s\n\n' "$*" >&2; exit 1; }

command -v kubeseal >/dev/null || die "kubeseal not installed.  brew install kubeseal"

TOKEN="${GHCR_TOKEN:-}"
if [[ -z "$TOKEN" ]] && command -v gh >/dev/null; then
  echo "→ GHCR_TOKEN unset; falling back to \`gh auth token\`"
  TOKEN="$(gh auth token 2>/dev/null || true)"
fi
[[ -n "$TOKEN" ]] || die "no token. Set GHCR_TOKEN to a PAT with read:packages, or run gh auth login."

# Least privilege matters more than usual here: this credential sits in a cluster, decrypted,
# for as long as the deployment exists. A token that can WRITE packages lets anyone who can
# read Secrets in this namespace publish images under your name. Pulling needs read:packages
# and nothing else.
if command -v gh >/dev/null && [[ "$TOKEN" == "$(gh auth token 2>/dev/null || echo -)" ]]; then
  scopes="$(gh auth status 2>&1 | sed -n 's/.*Token scopes: //p')"
  case "$scopes" in
    *write:packages*)
      printf '\n⚠  This is your gh CLI token and it carries write:packages.\n' >&2
      printf '   It will work, but the cluster only needs read:packages. Consider a\n' >&2
      printf '   dedicated classic PAT scoped to read:packages instead.\n\n' >&2
      ;;
  esac
fi

echo "→ sealing ${REGISTRY} credential for ${USERNAME} into ${NAMESPACE}/${SECRET_NAME}"

mkdir -p "$(dirname "$OUT")"

# --docker-email is required by older kubectl and harmless now; the value is never used.
# Plaintext never touches disk: stdout straight into kubeseal, same as seal-env.sh.
kubectl create secret docker-registry "$SECRET_NAME" \
    --namespace "$NAMESPACE" \
    --docker-server="$REGISTRY" \
    --docker-username="$USERNAME" \
    --docker-password="$TOKEN" \
    --dry-run=client -o yaml \
  | kubeseal --format yaml \
      --controller-name sealed-secrets-controller \
      --controller-namespace kube-system \
  > "${OUT}.tmp"

grep -q 'encryptedData' "${OUT}.tmp" \
  || { rm -f "${OUT}.tmp"; die "kubeseal produced no encryptedData. Is the tunnel up and the controller running?"; }

# The token must not appear in the output. If it does, kubeseal did not encrypt and this
# file would publish a credential to a public repository.
if grep -qF "$TOKEN" "${OUT}.tmp"; then
  rm -f "${OUT}.tmp"
  die "the token appears in plaintext in the sealed output — NOT writing it."
fi

mv "${OUT}.tmp" "$OUT"

cat <<EOF

✓ wrote $OUT

  Apply it, then reference it from the chart:

    kubectl apply -f $OUT
    kubectl get secret ${SECRET_NAME} -n ${NAMESPACE}

  charts/revealroll/values-staging.yaml:
    imagePullSecrets:
      - name: ${SECRET_NAME}

  NOTE: a SealedSecret is bound to its exact namespace AND name. Deploying this app to a
  different namespace means re-running this script, not copying the file.

EOF
