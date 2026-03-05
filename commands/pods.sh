#!/usr/bin/env bash

cmd_pods() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    logs)    pods_logs "$@" ;;
    restart) pods_restart "$@" ;;
    exec)    pods_exec "$@" ;;
    forward) pods_forward "$@" ;;
    debug)   pods_debug "$@" ;;
    "")      pods_menu ;;
    *)
      error "pods: unknown subcommand: $subcommand"
      echo "  Usage: devops-desk pods [logs|restart|exec|forward|debug]"
      exit 1 ;;
  esac
}

pods_menu() {
  local choice
  choice=$(printf '%s\n' \
    "logs     Stream pod logs (supports multi-container selection)" \
    "restart  Restart a deployment" \
    "exec     Shell into a pod" \
    "forward  Port-forward to a pod or service" \
    "debug    Diagnose a failing pod (events, describe, logs)" \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Pods > " \
      --header="Pod Operations" \
      --height=12) || return 0

  [[ -z "$choice" ]] && return
  cmd_pods "$(echo "$choice" | awk '{print $1}')"
}

# ─── Helpers ──────────────────────────────────────────────────────────────────
_select_pod() {
  local prompt="${1:-Pod}"
  kubectl get pods --all-namespaces --no-headers \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,NODE:.spec.nodeName' \
    2>/dev/null \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="${prompt} > " \
    --preview='kubectl describe pod {2} -n {1} 2>/dev/null | head -50' \
    --preview-window='right:50%:wrap'
}

_select_deployment() {
  kubectl get deployments --all-namespaces --no-headers \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas' \
    2>/dev/null \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Deployment > " \
    --preview='kubectl describe deployment {2} -n {1} 2>/dev/null | head -40' \
    --preview-window='right:50%:wrap'
}

# ─── Logs ─────────────────────────────────────────────────────────────────────
pods_logs() {
  local selected
  selected=$(_select_pod "Logs") || return 0
  [[ -z "$selected" ]] && return

  local ns pod
  ns=$(echo "$selected" | awk '{print $1}')
  pod=$(echo "$selected" | awk '{print $2}')

  # Pick container if multiple
  local containers
  containers=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null)
  local container_flag=""

  if [[ $(echo "$containers" | wc -w) -gt 1 ]]; then
    local container
    container=$(echo "$containers" | tr ' ' '\n' \
      | fzf --prompt="Container > " --height=10 --border=rounded) || return 0
    [[ -n "$container" ]] && container_flag="-c $container"
  fi

  step "Logs: $pod (namespace: $ns)"
  # shellcheck disable=SC2086
  kubectl logs -f --tail=200 "$pod" -n "$ns" $container_flag
}

# ─── Restart ──────────────────────────────────────────────────────────────────
pods_restart() {
  local selected
  selected=$(_select_deployment) || return 0
  [[ -z "$selected" ]] && return

  local ns deploy
  ns=$(echo "$selected" | awk '{print $1}')
  deploy=$(echo "$selected" | awk '{print $2}')

  if confirm "Restart deployment/$deploy in namespace $ns?"; then
    kubectl rollout restart deployment/"$deploy" -n "$ns"
    info "Waiting for rollout…"
    kubectl rollout status deployment/"$deploy" -n "$ns"
    success "Rollout complete"
  fi
}

# ─── Exec ─────────────────────────────────────────────────────────────────────
pods_exec() {
  local selected
  selected=$(_select_pod "Exec into") || return 0
  [[ -z "$selected" ]] && return

  local ns pod
  ns=$(echo "$selected" | awk '{print $1}')
  pod=$(echo "$selected" | awk '{print $2}')

  # Try preferred shells in order
  local shell="sh"
  for sh in bash sh; do
    if kubectl exec "$pod" -n "$ns" -- which "$sh" &>/dev/null 2>&1; then
      shell="$sh"
      break
    fi
  done

  step "Exec: $pod (namespace: $ns)  [shell: $shell]"
  kubectl exec -it "$pod" -n "$ns" -- "$shell"
}

# ─── Port Forward ─────────────────────────────────────────────────────────────
pods_forward() {
  local resource_type
  resource_type=$(printf 'pod\nservice\n' \
    | fzf --prompt="Resource type > " --height=8 --border=rounded) || return 0
  [[ -z "$resource_type" ]] && return

  local ns name remote_port

  if [[ "$resource_type" == "pod" ]]; then
    local selected
    selected=$(_select_pod "Port forward") || return 0
    [[ -z "$selected" ]] && return
    ns=$(echo "$selected" | awk '{print $1}')
    name=$(echo "$selected" | awk '{print $2}')
  else
    local selected
    selected=$(kubectl get services --all-namespaces --no-headers \
      -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,PORT:.spec.ports[0].port' 2>/dev/null \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Service > " \
      --preview='kubectl describe svc {2} -n {1} 2>/dev/null | head -30') || return 0
    [[ -z "$selected" ]] && return
    ns=$(echo "$selected" | awk '{print $1}')
    name="svc/$(echo "$selected" | awk '{print $2}')"
    remote_port=$(echo "$selected" | awk '{print $3}')
  fi

  [[ -z "${remote_port:-}" ]] && { echo -en "\n  Remote port: "; read -r remote_port; }
  echo -en "  Local port (default: $remote_port): "
  read -r local_port
  [[ -z "$local_port" ]] && local_port="$remote_port"

  step "Port forwarding: localhost:$local_port → $name:$remote_port (namespace: $ns)"
  info "Press Ctrl+C to stop"
  kubectl port-forward "$name" -n "$ns" "${local_port}:${remote_port}"
}

# ─── Debug ────────────────────────────────────────────────────────────────────
pods_debug() {
  local selected
  selected=$(_select_pod "Debug") || return 0
  [[ -z "$selected" ]] && return

  local ns pod
  ns=$(echo "$selected" | awk '{print $1}')
  pod=$(echo "$selected" | awk '{print $2}')

  step "Debug: $pod (namespace: $ns)"

  echo -e "\n${BOLD}Pod Status${RESET}"
  kubectl get pod "$pod" -n "$ns" -o wide

  echo -e "\n${BOLD}Recent Events${RESET}"
  kubectl get events -n "$ns" \
    --field-selector "involvedObject.name=$pod" \
    --sort-by='.lastTimestamp' 2>/dev/null | tail -15

  echo -e "\n${BOLD}Conditions & Container Status${RESET}"
  kubectl describe pod "$pod" -n "$ns" \
    | grep -A5 -E "^Conditions:|^Containers:|^Events:" | head -50

  echo -e "\n${BOLD}Recent Logs (last 30 lines)${RESET}"
  kubectl logs "$pod" -n "$ns" --tail=30 --all-containers=true 2>/dev/null \
    || kubectl logs "$pod" -n "$ns" --tail=30 --previous 2>/dev/null \
    || echo "  (no logs available)"
}
