#!/usr/bin/env bash

cmd_oras() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    pull)      oras_pull "$@" ;;
    push)      oras_push "$@" ;;
    login)     oras_login "$@" ;;
    list)      oras_list "$@" ;;
    sign)      oras_sign "$@" ;;
    verify)    oras_verify "$@" ;;
    "")        oras_menu ;;
    *)
      error "oras: unknown subcommand: $subcommand"
      echo "  Usage: devops-desk oras [login|list|pull|push|sign|verify]"
      exit 1 ;;
  esac
}

oras_menu() {
  local choice
  choice=$(printf '%s\n' \
    "login     Authenticate with OCI registry" \
    "list      List artifacts in registry" \
    "pull      Pull artifact from registry" \
    "push      Push artifact to registry" \
    "sign      Sign container image (Cosign)" \
    "verify    Verify signed image" \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="ORAS > " \
      --header="OCI Registry & Artifact Management" \
      --height=14) || return 0

  [[ -z "$choice" ]] && return
  cmd_oras "$(echo "$choice" | awk '{print $1}')"
}

# ─── Registry Login ───────────────────────────────────────────────────────────
oras_login() {
  local registry="${1:-}"
  local username="${2:-}"
  local password="${3:-}"

  if [[ -z "$registry" ]]; then
    info "Enter registry URL (e.g., docker.io, ghcr.io, ecr):"
    read -r registry
  fi

  [[ -z "$registry" ]] && { error "Registry URL required"; return 1; }

  if [[ -z "$username" ]]; then
    info "Enter username:"
    read -r username
  fi

  if [[ -z "$password" ]]; then
    info "Enter password (will not be echoed):"
    read -rs password
    echo ""
  fi

  step "Logging in to $registry"
  echo "$password" | oras login "$registry" -u "$username" --password-stdin && \
    success "Logged in to $registry" || \
    error "Login failed"
}

# ─── List Artifacts ───────────────────────────────────────────────────────────
oras_list() {
  local ref="${1:-}"

  if [[ -z "$ref" ]]; then
    info "Enter OCI reference (e.g., ghcr.io/owner/repo:tag):"
    read -r ref
  fi

  [[ -z "$ref" ]] && { error "OCI reference required"; return 1; }

  step "Listing artifacts: $ref"
  oras discover "$ref" --output table 2>/dev/null || \
    error "Failed to list artifacts for: $ref"
}

# ─── Pull Artifact ────────────────────────────────────────────────────────────
oras_pull() {
  local source_ref="${1:-}"
  local output_dir="${2:-.}"

  if [[ -z "$source_ref" ]]; then
    info "Enter source OCI reference:"
    read -r source_ref
  fi

  [[ -z "$source_ref" ]] && { error "Source reference required"; return 1; }

  if [[ -z "$output_dir" ]]; then
    info "Enter output directory (default: current):"
    read -r output_dir
    output_dir="${output_dir:-.}"
  fi

  step "Pulling artifact: $source_ref → $output_dir"
  mkdir -p "$output_dir"
  oras pull "$source_ref" -o "$output_dir" && \
    success "Artifact pulled to $output_dir" || \
    error "Pull failed"
}

# ─── Push Artifact ────────────────────────────────────────────────────────────
oras_push() {
  local target_ref="${1:-}"
  local artifact_path="${2:-}"

  if [[ -z "$target_ref" ]]; then
    info "Enter target OCI reference (e.g., ghcr.io/owner/repo:v1.0.0):"
    read -r target_ref
  fi

  [[ -z "$target_ref" ]] && { error "Target reference required"; return 1; }

  if [[ -z "$artifact_path" ]]; then
    info "Enter artifact file path(s) (space-separated):"
    read -r artifact_path
  fi

  [[ -z "$artifact_path" ]] && { error "Artifact path required"; return 1; }

  step "Pushing artifact: $target_ref"
  # shellcheck disable=SC2086
  oras push "$target_ref" $artifact_path && \
    success "Artifact pushed: $target_ref" || \
    error "Push failed"
}

# ─── Sign Image (Cosign) ──────────────────────────────────────────────────────
oras_sign() {
  local image_ref="${1:-}"
  local key="${2:-}"

  # Check for cosign
  if ! command -v cosign &>/dev/null; then
    error "cosign not found. Install with: brew install cosign"
    return 1
  fi

  if [[ -z "$image_ref" ]]; then
    info "Enter image reference to sign (e.g., ghcr.io/owner/repo:v1.0.0):"
    read -r image_ref
  fi

  [[ -z "$image_ref" ]] && { error "Image reference required"; return 1; }

  if [[ -z "$key" ]]; then
    info "Use existing cosign key? [y/n] (default: generate new)"
    read -r use_existing
    if [[ "$use_existing" =~ ^[Yy]$ ]]; then
      info "Enter path to private key:"
      read -r key
    fi
  fi

  step "Signing image: $image_ref"
  
  if [[ -n "$key" ]]; then
    cosign sign --key "$key" "$image_ref" && \
      success "Image signed: $image_ref" || \
      error "Signing failed"
  else
    cosign sign "$image_ref" && \
      success "Image signed: $image_ref" || \
      error "Signing failed"
  fi
}

# ─── Verify Signed Image ──────────────────────────────────────────────────────
oras_verify() {
  local image_ref="${1:-}"
  local key="${2:-}"

  # Check for cosign
  if ! command -v cosign &>/dev/null; then
    error "cosign not found. Install with: brew install cosign"
    return 1
  fi

  if [[ -z "$image_ref" ]]; then
    info "Enter image reference to verify:"
    read -r image_ref
  fi

  [[ -z "$image_ref" ]] && { error "Image reference required"; return 1; }

  if [[ -z "$key" ]]; then
    info "Enter path to public key (optional, or CTRL+C to skip):"
    read -r key
  fi

  step "Verifying signature: $image_ref"
  
  if [[ -n "$key" ]]; then
    cosign verify --key "$key" "$image_ref" && \
      success "Signature valid: $image_ref" || \
      error "Verification failed"
  else
    cosign verify "$image_ref" && \
      success "Signature valid: $image_ref" || \
      error "Verification failed"
  fi
}
