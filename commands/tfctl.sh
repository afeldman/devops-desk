#!/usr/bin/env bash

cmd_tfctl() {
  check_dependency tfctl

  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    reconcile) tfctl_reconcile "$@" ;;
    replan)    tfctl_replan "$@" ;;
    suspend)   tfctl_suspend "$@" ;;
    resume)    tfctl_resume "$@" ;;
    status)    tfctl_status ;;
    "")        tfctl_menu ;;
    *)
      error "tfctl: unknown subcommand: $subcommand"
      echo "  Usage: devops-desk tfctl [reconcile|replan|suspend|resume|status]"
      exit 1 ;;
  esac
}

tfctl_menu() {
  local choice
  choice=$(printf '%s\n' \
    "reconcile   Reconcile a terraform service-stack" \
    "replan      Replan a terraform service-stack" \
    "suspend     Suspend a terraform service-stack" \
    "resume      Resume a terraform service-stack" \
    "status      Show all terraform resources status" | \
    fzf --header="tfctl operations" --preview-window=hidden)

  # Extract subcommand
  subcommand="$(echo "$choice" | awk '{print $1}')"
  [[ -z "$subcommand" ]] && return 0
  
  cmd_tfctl "$subcommand"
}

tfctl_reconcile() {
  local stack="${1:-}"
  
  if [[ -z "$stack" ]]; then
    echo "Available terraform stacks:"
    tfctl list --output names 2>/dev/null || echo "  (run: tfctl list)"
    echo ""
    read -p "Enter stack name: " stack
  fi
  
  if [[ -z "$stack" ]]; then
    error "No stack specified"
    exit 1
  fi
  
  info "Reconciling terraform stack: $stack"
  tfctl reconcile "$stack"
  success "Reconciliation triggered"
}

tfctl_replan() {
  local stack="${1:-}"
  
  if [[ -z "$stack" ]]; then
    echo "Available terraform stacks:"
    tfctl list --output names 2>/dev/null || echo "  (run: tfctl list)"
    echo ""
    read -p "Enter stack name: " stack
  fi
  
  if [[ -z "$stack" ]]; then
    error "No stack specified"
    exit 1
  fi
  
  info "Replanning terraform stack: $stack"
  tfctl replan "$stack"
  success "Replan triggered"
}

tfctl_suspend() {
  local stack="${1:-}"
  
  if [[ -z "$stack" ]]; then
    echo "Available terraform stacks:"
    tfctl list --output names 2>/dev/null || echo "  (run: tfctl list)"
    echo ""
    read -p "Enter stack name: " stack
  fi
  
  if [[ -z "$stack" ]]; then
    error "No stack specified"
    exit 1
  fi
  
  info "Suspending terraform stack: $stack"
  tfctl suspend "$stack"
  success "Stack suspended"
}

tfctl_resume() {
  local stack="${1:-}"
  
  if [[ -z "$stack" ]]; then
    echo "Available terraform stacks:"
    tfctl list --output names 2>/dev/null || echo "  (run: tfctl list)"
    echo ""
    read -p "Enter stack name: " stack
  fi
  
  if [[ -z "$stack" ]]; then
    error "No stack specified"
    exit 1
  fi
  
  info "Resuming terraform stack: $stack"
  tfctl resume "$stack"
  success "Stack resumed"
}

tfctl_status() {
  info "Terraform service-stacks status"
  kubectl --context="${KUBE_CONTEXT}" get terraform -n flux-system \
    -o wide \
    --no-headers=false 2>/dev/null || {
    error "Failed to fetch terraform resources. Make sure you're connected to the cluster."
    exit 1
  }
}

check_dependency() {
  if ! command -v "$1" &>/dev/null; then
    error "$1 not installed"
    echo "  Install via: brew install $1"
    echo "  Or see: https://docs.opentofu.org/docs/intro/install/"
    exit 1
  fi
}
