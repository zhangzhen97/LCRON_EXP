#!/usr/bin/env bash

# LCRON_EXP KML development machine connector.
# Flow: local tmux -> SSH Relay -> KIM approval -> kml_login -> worker container.

set -euo pipefail

SESSION="${LCRON_EXP_SESSION:-lcron-exp-kml}"
SSH_USER="${LCRON_EXP_SSH_USER:-zhangzhen24}"
RELAY_HOST="${LCRON_EXP_RELAY_HOST:-relay.corp.kuaishou.com}"
SSH_KEY="${MAC_OS_SSH_KEY:-/Users/zz/.ssh/id_rsa}"
TOKEN_FILE="${LCRON_EXP_TOKEN_FILE:-$HOME/.config/lcron-exp/kml.env}"
WAIT_TIMEOUT="${LCRON_EXP_WAIT_TIMEOUT:-180}"

POD="kml-dtmachine-100000920-prod-worker-0"
CONTAINER="worker"
NAMESPACE="kubekml"
CLUSTER="kce-aip-wlf1-hb2az1"
SERVER="kml.corp.kuaishou.com"

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./connect.sh [attach|stop]

  (default)  Create/reuse the persistent SSH + KML session and attach to it.
  attach     Attach to the existing tmux session.
  stop       Stop the tmux session.

Environment overrides:
  LCRON_EXP_SESSION       tmux session name (default: lcron-exp-kml)
  MAC_OS_SSH_KEY          SSH private key (default: /Users/zz/.ssh/id_rsa)
  LCRON_EXP_TOKEN_FILE    local token env file
EOF
}

tmux_has_session() {
  tmux has-session -t "$SESSION" 2>/dev/null
}

capture_pane() {
  tmux capture-pane -t "$SESSION":0 -p 2>/dev/null || true
}

wait_for_relay_and_login() {
  local deadline=$((SECONDS + WAIT_TIMEOUT))
  local pane
  local login_cmd

  printf -v login_cmd \
    'kml_login --pod=%q --container=%q --namespace=%q --cluster=%q --token=%q --server=%q' \
    "$POD" "$CONTAINER" "$NAMESPACE" "$CLUSTER" "$KML_TOKEN" "$SERVER"

  while (( SECONDS < deadline )); do
    pane="$(capture_pane)"

    if grep -Fq "[$SSH_USER@relay]" <<<"$pane"; then
      # The Relay prompt is ready after KIM approval. Enter is sent as CR by tmux.
      tmux send-keys -t "$SESSION":0 "$login_cmd" C-m
      return 0
    fi

    if grep -Eiq 'Permission denied|Could not resolve|Connection refused|No route to host|timed out' <<<"$pane"; then
      echo "[ERROR] SSH to Relay failed. Check the tmux pane: tmux attach -t $SESSION" >&2
      return 1
    fi

    sleep 2
  done

  echo "[ERROR] Timed out waiting for Relay/KIM approval (${WAIT_TIMEOUT}s)." >&2
  echo "[INFO] Attach manually with: tmux attach -t $SESSION" >&2
  return 1
}

load_token() {
  if [[ -z "${KML_TOKEN:-}" && -f "$TOKEN_FILE" ]]; then
    # The file is user-managed and should contain only shell variable exports.
    # shellcheck disable=SC1090
    source "$TOKEN_FILE"
  fi

  if [[ -z "${KML_TOKEN:-}" ]]; then
    read -r -s -p 'KML token: ' KML_TOKEN
    printf '\n'
  fi

  [[ -n "${KML_TOKEN:-}" ]] || die 'KML_TOKEN is empty'
}

start_session() {
  command -v tmux >/dev/null 2>&1 || die 'tmux is not installed'
  [[ -r "$SSH_KEY" ]] || die "SSH key is not readable: $SSH_KEY"

  load_token

  tmux new-session -d -s "$SESSION"
  tmux send-keys -t "$SESSION":0 \
    "ssh -tt -i $(printf '%q' "$SSH_KEY") ${SSH_USER}@${RELAY_HOST}" C-m

  echo "[INFO] SSH session started: $SESSION"
  echo "[INFO] Approve the KIM request when prompted. The script will then run kml_login automatically."

  # Keep the pane visible so the user can see the KIM prompt and the target shell.
  wait_for_relay_and_login &
  local helper_pid=$!
  tmux attach -t "$SESSION" || true
  wait "$helper_pid" || true
}

case "${1:-connect}" in
  connect)
    if tmux_has_session; then
      tmux attach -t "$SESSION"
    else
      start_session
    fi
    ;;
  attach)
    tmux_has_session || die "tmux session does not exist: $SESSION"
    tmux attach -t "$SESSION"
    ;;
  stop)
    tmux_has_session && tmux kill-session -t "$SESSION" || true
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
