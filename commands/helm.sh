#!/usr/bin/env bash

cmd_helm() {
  check_dependency helm

  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    upgrade)  helm_upgrade "$@" ;;
    rollback) helm_rollback "$@" ;;
    "")       helm_menu ;;
    *)
      error "helm: unknown subcommand: $subcommand"
      echo "  Usage: devops-desk helm [upgrade|rollback]"
      exit 1 ;;
  esac
}

helm_menu() {
  local choice
  choice=$(printf '%s\n' \
    "upgrade    Interactive Helm upgrade" \
    "rollback   Rollback a Helm release to a previous revision" \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Helm > " \
      --header="Helm Operations" \
      --height=8) || return 0

  [[ -z "$choice" ]] && return
  cmd_helm "$(echo "$choice" | awk '{print $1}')"
}

helm_upgrade() {
  step "Helm Upgrade"

  local selected
  selected=$(helm list --all-namespaces --no-headers 2>/dev/null \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Release > " \
      --header="Select Helm release to upgrade" \
      --preview='helm get values {1} -n {2} 2>/dev/null') || return 0

  [[ -z "$selected" ]] && return

  local release ns chart
  release=$(echo "$selected" | awk '{print $1}')
  ns=$(echo "$selected" | awk '{print $2}')
  chart=$(echo "$selected" | awk '{print $9}')

  info "Release: $release  (namespace: $ns)"
  info "Chart:   $chart"

  echo -en "\n  Chart version (leave empty for latest): "
  read -r version

  local version_flag=""
  [[ -n "$version" ]] && version_flag="--version $version"

  if confirm "Upgrade $release → $chart $version?"; then
    # shellcheck disable=SC2086
    helm upgrade "$release" "$chart" -n "$ns" $version_flag --reuse-values
    success "Upgrade complete"
  fi
}

helm_rollback() {
  step "Helm Rollback"

  local selected
  selected=$(helm list --all-namespaces --no-headers 2>/dev/null \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Release > " \
      --header="Select release to rollback" \
      --preview='helm history {1} -n {2} 2>/dev/null') || return 0

  [[ -z "$selected" ]] && return

  local release ns
  release=$(echo "$selected" | awk '{print $1}')
  ns=$(echo "$selected" | awk '{print $2}')

  echo ""
  helm history "$release" -n "$ns"
  echo ""

  echo -en "  Rollback to revision (leave empty for previous): "
  read -r revision

  if confirm "Rollback $release?"; then
    if [[ -n "$revision" ]]; then
      helm rollback "$release" "$revision" -n "$ns"
    else
      helm rollback "$release" -n "$ns"
    fi
    success "Rollback complete"
  fi
}
