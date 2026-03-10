#!/usr/bin/env bash

cmd_git() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    tag)      git_tag "$@" ;;
    tags)     git_tags "$@" ;;
    status)   git_status "$@" ;;
    log)      git_log "$@" ;;
    push)     git_push "$@" ;;
    "")       git_menu ;;
    *)
      error "git: unknown subcommand: $subcommand"
      echo "  Usage: devops-desk git [tag|tags|status|log|push]"
      exit 1 ;;
  esac
}

git_menu() {
  local choice
  choice=$(printf '%s\n' \
    "status    Show git status" \
    "log       Show commit history with fzf" \
    "tag       Create new annotated tag" \
    "tags      List all tags (filter by pattern)" \
    "push      Push tags to origin" \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Git > " \
      --header="Git Operations" \
      --height=12) || return 0

  [[ -z "$choice" ]] && return
  cmd_git "$(echo "$choice" | awk '{print $1}')"
}

# ─── Git Status ───────────────────────────────────────────────────────────────
git_status() {
  step "Git Status in $(pwd)"
  git status
}

# ─── Commit Log ───────────────────────────────────────────────────────────────
git_log() {
  local pattern="${1:-}"
  local commits

  step "Browsing commit history"
  commits=$(git log --oneline --all 2>/dev/null | fzf "${DD_FZF_OPTS[@]}" \
    --multi \
    --prompt="Commits > " \
    --header="Select commits (Ctrl+A to select all)" \
    --preview='git show --stat {1} 2>/dev/null | head -40' \
    --preview-window='right:50%:wrap') || return 0

  echo "$commits"
}

# ─── List Tags ────────────────────────────────────────────────────────────────
git_tags() {
  local pattern="${1:-}"
  local filter_cmd="cat"

  if [[ -n "$pattern" ]]; then
    filter_cmd="grep $pattern"
  fi

  step "Listing tags"
  if [[ -n "$pattern" ]]; then
    info "Filtering by: $pattern"
  fi

  git tag -l --sort=-version:refname 2>/dev/null \
    | $filter_cmd \
    | fzf "${DD_FZF_OPTS[@]}" \
      --multi \
      --prompt="Tags > " \
      --header="Select tags (ESC to return)" \
      --preview='git log {1} --oneline -n 10 2>/dev/null' \
      --preview-window='right:50%:wrap'
}

# ─── Create Tag ───────────────────────────────────────────────────────────────
git_tag() {
  local tag_name="${1:-}"
  local tag_message="${2:-}"
  local tag_type="${3:-annotated}"  # annotated or lightweight

  if [[ -z "$tag_name" ]]; then
    info "Suggested tag patterns:"
    echo "  v2.2.0-dev.N        (development)"
    echo "  v2.2.0-rc.N         (release candidate)"
    echo "  v2.2.0-final        (production)"
    echo "  iac/v2.2.0-dev.N    (infrastructure)"
    echo ""
    info "Enter tag name:"
    read -r tag_name
  fi

  [[ -z "$tag_name" ]] && { error "Tag name required"; return 1; }

  # Validate tag doesn't exist
  if git rev-parse "$tag_name" &>/dev/null; then
    error "Tag already exists: $tag_name"
    return 1
  fi

  # Get message if needed
  if [[ "$tag_type" == "annotated" && -z "$tag_message" ]]; then
    info "Enter tag message (or press Enter to skip):"
    read -r tag_message
  fi

  # Create tag
  step "Creating tag: $tag_name"
  if [[ "$tag_type" == "annotated" && -n "$tag_message" ]]; then
    git tag -a "$tag_name" -m "$tag_message"
  elif [[ "$tag_type" == "annotated" ]]; then
    git tag -a "$tag_name"
  else
    git tag "$tag_name"
  fi

  success "Tag created: $tag_name"
  info "Current commit: $(git rev-list -n 1 "$tag_name")"
}

# ─── Push Tags ────────────────────────────────────────────────────────────────
git_push() {
  local target="${1:-origin}"
  local tags

  step "Select tags to push"
  tags=$(git_tags) || return 0

  if [[ -z "$tags" ]]; then
    warning "No tags selected"
    return 0
  fi

  if confirm "Push tags to $target?\n\n$(echo "$tags" | sed 's/^/  /')\n"; then
    step "Pushing tags to $target"
    while IFS= read -r tag; do
      [[ -z "$tag" ]] && continue
      git push "$target" "$tag" && success "Pushed: $tag" || error "Failed to push: $tag"
    done <<< "$tags"
  fi
}
