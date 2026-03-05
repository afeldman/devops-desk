#!/usr/bin/env bash
# Persists session state (current environment, namespace) to ~/.devops-desk/state

DEVOPS_DESK_STATE_DIR="${HOME}/.devops-desk"
DEVOPS_DESK_STATE_FILE="${DEVOPS_DESK_STATE_DIR}/state"

state_init() {
  mkdir -p "$DEVOPS_DESK_STATE_DIR"
  touch "$DEVOPS_DESK_STATE_FILE"
}

state_set() {
  local key="$1" value="$2"
  state_init
  local tmp
  tmp=$(mktemp)
  grep -v "^${key}=" "$DEVOPS_DESK_STATE_FILE" > "$tmp" 2>/dev/null || true
  echo "${key}=${value}" >> "$tmp"
  mv "$tmp" "$DEVOPS_DESK_STATE_FILE"
}

state_get() {
  local key="$1"
  grep "^${key}=" "$DEVOPS_DESK_STATE_FILE" 2>/dev/null | cut -d'=' -f2- || echo ""
}

state_set_env()       { state_set "ENVIRONMENT" "$1"; }
state_get_env()       { state_get "ENVIRONMENT"; }
state_set_namespace() { state_set "NAMESPACE" "$1"; }
state_get_namespace() { state_get "NAMESPACE"; }
