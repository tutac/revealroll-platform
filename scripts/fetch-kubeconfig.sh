#!/usr/bin/env bash
#
# Fetch the k3s kubeconfig from the staging node and make it usable from a laptop.
#
#   ./scripts/fetch-kubeconfig.sh          # write ~/.kube/revealroll-staging.yaml
#   ./scripts/fetch-kubeconfig.sh --print-host   # just resolve and print the VPS IPv4
#
# The API server is NOT reachable from the internet -- roles/firewall leaves 6443 closed
# and playbooks/99-verify.yml asserts that it stays closed. So the kubeconfig this writes
# points at 127.0.0.1:6443 and expects an SSH tunnel (`make tunnel`) to be up. That is the
# trade recorded in .claude/memory/decisions.md: a little friction, versus an internet
# facing Kubernetes API guarded only by a certificate.
#
# Set K3S_DIRECT=1 if you ever open 6443 to your own IP -- the kubeconfig is then written
# against the public address and no tunnel is needed. The SANs for that already exist
# (see k3s_tls_sans), so it is a firewall change, not a cluster change.
#
# This never touches ~/.kube/config. A separate file you opt into with KUBECONFIG cannot
# become the accidental current-context of an unrelated kubectl.
set -euo pipefail

SSH_PORT="${SSH_PORT:-22}"
SSH_USER="${SSH_USER:-deploy}"
OUT="${KUBECONFIG_PATH:-${HOME}/.kube/revealroll-staging.yaml}"
CONTEXT="revealroll-staging"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { printf '\nERROR: %s\n\n' "$*" >&2; exit 1; }

# Host resolution, in order of authority. Terraform owns the VPS, so its output is the
# real answer -- but it needs the R2 backend credentials, and the moment you actually want
# a kubeconfig is often the moment something is on fire. The inventory fallback means a
# missing CNTB_/AWS_ env var does not stand between you and `kubectl get pods`.
resolve_host() {
  if [[ -n "${K3S_HOST:-}" ]]; then
    printf '%s' "$K3S_HOST"
    return
  fi

  local ip
  if ip="$(terraform -chdir="${REPO_ROOT}/terraform/stacks/01-infra" output -raw ipv4 2>/dev/null)" \
     && [[ -n "$ip" ]]; then
    printf '%s' "$ip"
    return
  fi

  if ip="$(awk '/ansible_host:/ {print $2; exit}' \
             "${REPO_ROOT}/ansible/inventory/staging.yml" 2>/dev/null)" \
     && [[ -n "$ip" ]]; then
    printf '%s' "$ip"
    return
  fi

  die "could not determine the VPS address.
  Tried: \$K3S_HOST, 'terraform output -raw ipv4' in 01-infra, and ansible_host in
  ansible/inventory/staging.yml. Set K3S_HOST=<ip> and re-run."
}

HOST="$(resolve_host)"

if [[ "${1:-}" == "--print-host" ]]; then
  printf '%s\n' "$HOST"
  exit 0
fi

# Fail here, with a sentence, rather than 30 seconds later with a half-written file.
echo "→ checking ${SSH_USER}@${HOST}:${SSH_PORT}"
ssh -p "$SSH_PORT" -o ConnectTimeout=5 -o BatchMode=yes \
    "${SSH_USER}@${HOST}" true 2>/dev/null \
  || die "cannot SSH to ${SSH_USER}@${HOST}:${SSH_PORT}.
  Check the host is up, that your key is in the agent, and that ansible_port in
  ansible/inventory/staging.yml still matches SSH_PORT (currently ${SSH_PORT})."

TMP="$(mktemp)"
trap 'rm -f "$TMP" "$TMP.raw"' EXIT

# `sudo -n`: never prompt. Without it a sudo password prompt is silently captured INTO the
# kubeconfig and you spend ten minutes debugging a YAML parse error.
echo "→ reading /etc/rancher/k3s/k3s.yaml"
ssh -p "$SSH_PORT" "${SSH_USER}@${HOST}" 'sudo -n cat /etc/rancher/k3s/k3s.yaml' > "$TMP.raw" \
  || die "could not read the kubeconfig from the node.
  If k3s is not installed yet, run: make ansible-site
  If sudo asked for a password, the deploy user's NOPASSWD sudoers rule is missing."

grep -q '^clusters:' "$TMP.raw" \
  || die "what came back from the node is not a kubeconfig. First line was:
  $(head -1 "$TMP.raw")"

if [[ "${K3S_DIRECT:-0}" == "1" ]]; then
  SERVER="https://${HOST}:6443"
  ACCESS="direct (6443 must be open to your IP in roles/firewall)"
else
  SERVER="https://127.0.0.1:6443"
  ACCESS="SSH tunnel — run 'make tunnel' in another terminal"
fi

# No `sed -i`: BSD sed wants an argument to it and GNU sed refuses one, so the in-place
# form is the single least portable thing you can put in a shell script. Reading one file
# and writing another sidesteps the whole argument.
#
# ': default' covers every occurrence at once -- 'name: default', 'cluster: default',
# 'user: default', 'current-context: default'. Renaming matters: the day there are two
# clusters, 'default' is how you kubectl delete in the wrong one.
sed -e "s#server: https://127.0.0.1:6443#server: ${SERVER}#" \
    -e "s#server: https://\[::1\]:6443#server: ${SERVER}#" \
    -e "s/: default/: ${CONTEXT}/g" \
    "$TMP.raw" > "$TMP"

grep -q "server: ${SERVER}" "$TMP" \
  || die "the server address rewrite did not match anything.
  k3s wrote something unexpected into k3s.yaml -- inspect it on the node before trusting
  this file."

mkdir -p "$(dirname "$OUT")"
install -m 600 "$TMP" "$OUT"

cat <<EOF

✓ wrote $OUT
  context : ${CONTEXT}
  server  : ${SERVER}
  access  : ${ACCESS}

  export KUBECONFIG=${OUT}
  kubectl get nodes -o wide

EOF
