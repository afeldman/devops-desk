#!/usr/bin/env bash

cmd_release() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    create)   release_create "$@" ;;
    status)   release_status "$@" ;;
    workflows) release_workflows "$@" ;;
    promote)  release_promote "$@" ;;
    "")       release_menu ;;
    *)
      error "release: unknown subcommand: $subcommand"
      echo "  Usage: devops-desk release [create|status|promote|workflows]"
      exit 1 ;;
  esac
}

release_menu() {
  local choice
  choice=$(printf '%s\n' \
    "create     Create new release tag (dev/rc/final)" \
    "status     Check GitHub Actions release workflow" \
    "workflows  List recent release workflows" \
    "promote    Promote from dev → rc → final" \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Release > " \
      --header="Release Management" \
      --height=12) || return 0

  [[ -z "$choice" ]] && return
  cmd_release "$(echo "$choice" | awk '{print $1}')"
}

# ─── Create Release Tag ───────────────────────────────────────────────────────
release_create() {
  local release_type="${1:-}"  # dev, rc, or final
  local version_base="${2:-}"  # e.g., v2.2.0
  local iac_match="${3:-true}" # whether to create matching iac tag

  # Prompt for type if not provided
  if [[ -z "$release_type" ]]; then
    release_type=$(printf '%s\n' "dev" "rc" "final" | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Release Type > " \
      --header="dev (development) | rc (release candidate) | final (production)") || return 0
  fi

  # Get current highest tag for version bumping
  local last_tag last_num
  case "$release_type" in
    dev)
      last_tag=$(git tag -l "v*-dev.*" --sort=-version:refname 2>/dev/null | head -1)
      last_num=$(echo "$last_tag" | sed 's/.*-dev\.\([0-9]*\)$/\1/' || echo "0")
      local next_num=$((last_num + 1))
      local tag_name="v2.2.0-dev.$next_num"
      local tag_msg="Development release v2.2.0-dev.$next_num"
      ;;
    rc)
      last_tag=$(git tag -l "v*-rc.*" --sort=-version:refname 2>/dev/null | head -1)
      last_num=$(echo "$last_tag" | sed 's/.*-rc\.\([0-9]*\)$/\1/' || echo "0")
      local next_num=$((last_num + 1))
      local tag_name="v2.2.0-rc.$next_num"
      local tag_msg="Release Candidate v2.2.0-rc.$next_num"
      ;;
    final)
      local tag_name="v2.2.0-final"
      local tag_msg="Production Release v2.2.0-final"
      ;;
  esac

  info "Last $release_type tag: ${last_tag:-none}"
  info "New tag would be: $tag_name"
  
  # Allow customization
  echo "  Override tag (leave blank to use suggested):"
  read -r custom_tag
  [[ -n "$custom_tag" ]] && tag_name="$custom_tag"

  if confirm "Create tag $tag_name?"; then
    step "Creating release tag: $tag_name"
    git tag -a "$tag_name" -m "$tag_msg"
    success "Tag created: $tag_name"

    # Optionally create matching iac tag
    if [[ "$iac_match" == "true" ]]; then
      local iac_tag="iac/$tag_name"
      if ! git rev-parse "$iac_tag" &>/dev/null; then
        if confirm "Also create matching IaC tag: $iac_tag?"; then
          git tag -a "$iac_tag" -m "IaC release synchronized with $tag_name"
          success "IaC tag created: $iac_tag"
        fi
      fi
    fi

    # Offer to push immediately
    if confirm "Push tags to origin?"; then
      git push origin "$tag_name"
      [[ -n "$iac_tag" ]] && git push origin "$iac_tag"
      success "Tags pushed!"
    fi
  fi
}

# ─── Check Release Workflow Status ────────────────────────────────────────────
release_status() {
  require_env > /dev/null
  
  if ! command -v gh &>/dev/null; then
    error "GitHub CLI (gh) required. Install with: brew install gh"
    return 1
  fi

  step "Fetching latest release workflow"
  
  gh run list --workflow "release.yml" --limit 1 --json status,conclusion,displayTitle,url,createdAt \
    --template '
{{range .}}
Status:      {{.status}}
Conclusion:  {{.conclusion}}
Title:       {{.displayTitle}}
Created:     {{.createdAt}}
URL:         {{.url}}
{{end}}'
}

# ─── List Recent Workflows ───────────────────────────────────────────────────
release_workflows() {
  if ! command -v gh &>/dev/null; then
    error "GitHub CLI (gh) required"
    return 1
  fi

  step "Recent release workflows"
  gh run list --workflow "release.yml" --limit 10 \
    --json status,conclusion,displayTitle,createdAt \
    --template '{{range .}}{{.status|padRight 10}}{{.conclusion|padRight 12}}{{.displayTitle|padRight 40}}{{.createdAt|padRight 25}}{{"\n"}}{{end}}'
}

# ─── Promote Release ───────────────────────────────────────────────────────────
release_promote() {
  step "Release Promotion Pipeline"
  
  local current_type="${1:-}"
  if [[ -z "$current_type" ]]; then
    current_type=$(printf '%s\n' "dev" "rc" | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Promote from > " \
      --header="Source release type") || return 0
  fi

  local target_type
  case "$current_type" in
    dev) target_type="rc" ;;
    rc)  target_type="final" ;;
    *)   error "Can only promote from dev or rc"; return 1 ;;
  esac

  info "Promotion: $current_type → $target_type"
  
  # Get latest tag of current type
  local latest_tag
  latest_tag=$(git tag -l "v*-${current_type}.*" --sort=-version:refname 2>/dev/null | head -1)
  
  if [[ -z "$latest_tag" ]]; then
    error "No ${current_type} releases found"
    return 1
  fi

  info "Latest $current_type tag: $latest_tag"
  
  # Create corresponding target tag
  local new_tag
  if [[ "$target_type" == "final" ]]; then
    new_tag="v2.2.0-final"
  else
    local next_num=$(git tag -l "v*-${target_type}.*" --sort=-version:refname 2>/dev/null | head -1 | sed "s/.*-${target_type}\.\([0-9]*\)$/\1/" || echo "0")
    new_tag="v2.2.0-${target_type}.$((next_num + 1))"
  fi

  if confirm "Create promotion tag: $new_tag (from $latest_tag)?"; then
    git tag -a "$new_tag" -m "Promoted from $latest_tag to $target_type"
    success "Promotion tag created: $new_tag"
    
    if confirm "Push to origin?"; then
      git push origin "$new_tag"
    fi
  fi
}
