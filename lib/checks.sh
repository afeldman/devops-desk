#!/usr/bin/env bash
REQUIRED_DEPS=(aws kubectl fzf)
OPTIONAL_DEPS=(k9s flux helm gh bat stern git oras uv)

check_dependency() {
  local dep="$1"
  if ! command -v "$dep" &>/dev/null; then
    error "Required tool not found: $dep"
    echo "  Install with: brew install $dep"
    exit 1
  fi
}

check_all_deps() {
  local missing=()
  for dep in "${REQUIRED_DEPS[@]}"; do
    command -v "$dep" &>/dev/null || missing+=("$dep")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing required tools: ${missing[*]}"
    echo "  Install: brew install ${missing[*]}"
    exit 1
  fi
}

check_optional_deps() {
  local missing=()
  for dep in "${OPTIONAL_DEPS[@]}"; do
    command -v "$dep" &>/dev/null || missing+=("$dep")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    warning "Optional tools not installed: ${missing[*]}"
    echo "  Install: brew install ${missing[*]}"
  fi
}
