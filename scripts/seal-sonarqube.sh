#!/usr/bin/env bash
#
# Seal SonarQube's two startup credentials so they live in Git encrypted, like everything else.
#
#   ./scripts/seal-sonarqube.sh
#
# Two keys, one Secret:
#   postgres-password    -- read by platform/sonarqube-db/postgres.yaml AND by the
#                           SonarQube chart's jdbcOverwrite. They must agree, which is why
#                           they come from the same key rather than two.
#   monitoring-passcode  -- SONAR_WEB_SYSTEMPASSCODE. The readiness probe and the
#                           PodMonitor both authenticate with it. Without it the pod is
#                           never Ready and the chart refuses to template.
#
# The ADMIN password is deliberately NOT here: SonarQube forces a password change at first
# login, and the chart's password-changing Job re-runs on every sync and then fails 401
# forever. Set it in the UI, store it in the password manager.
#
# ⚠ Rotating postgres-password after first install does NOT change the password inside an
# existing database. Change it with ALTER ROLE first, or delete the PVC and start over.
#
# Sibling of seal-env.sh, seal-registry.sh and seal-grafana-admin.sh.
set -euo pipefail

NAMESPACE="${NAMESPACE:-sonarqube}"
SECRET_NAME="${SECRET_NAME:-sonarqube}"
OUT="secrets/sonarqube/sonarqube-sealed.yaml"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

die() { printf '\nERROR: %s\n\n' "$*" >&2; exit 1; }

command -v kubeseal >/dev/null || die "kubeseal not installed.  brew install kubeseal"

# Same generator as seal-grafana-admin.sh: every command terminates on its own, so
# pipefail cannot kill the script at exit 141.
gen() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-32; }

PG_PASSWORD="${SONARQUBE_DB_PASSWORD:-$(gen)}"
PASSCODE="${SONARQUBE_MONITORING_PASSCODE:-$(gen)}"

for name in PG_PASSWORD PASSCODE; do
  value="${!name}"
  (( ${#value} >= 16 )) || die "${name} is only ${#value} characters. Refusing to seal a weak credential."
done

echo "→ sealing ${NAMESPACE}/${SECRET_NAME}"

mkdir -p "$(dirname "$OUT")"

# Plaintext goes stdout-to-stdin only; it never touches the filesystem.
kubectl create secret generic "$SECRET_NAME" \
    --namespace "$NAMESPACE" \
    --from-literal=postgres-password="$PG_PASSWORD" \
    --from-literal=monitoring-passcode="$PASSCODE" \
    --dry-run=client -o yaml \
  | kubeseal --format yaml \
      --controller-name sealed-secrets-controller \
      --controller-namespace kube-system \
  > "${OUT}.tmp"

grep -q 'encryptedData' "${OUT}.tmp" \
  || { rm -f "${OUT}.tmp"; die "kubeseal produced no encryptedData. Is the tunnel up and the controller running?"; }

# The one check that matters before a file goes to a PUBLIC repository.
for secret in "$PG_PASSWORD" "$PASSCODE"; do
  if grep -qF "$secret" "${OUT}.tmp"; then
    rm -f "${OUT}.tmp"
    die "a credential appears in plaintext in the sealed output — NOT writing it."
  fi
done

mv "${OUT}.tmp" "$OUT"

cat <<MSG

✓ wrote $OUT

  SonarQube:  https://sonarqube.stg.revealroll.com
  first login: admin / admin — it will force a change. Put the new one in your
  password manager; nothing in this repo can recover it.

  DB password and monitoring passcode are sealed and need not be remembered, but save
  the DB password anyway: you need it to psql into the StatefulSet during an incident.

  postgres-password:   ${PG_PASSWORD}
  monitoring-passcode: ${PASSCODE}

  ^ shown once.

  Argo CD deploys this via gitops/apps/sonarqube-secrets.yaml — commit and push, do not
  kubectl apply.

MSG
