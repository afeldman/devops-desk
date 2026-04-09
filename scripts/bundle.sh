#!/usr/bin/env bash
# bundle.sh — creates a single-file devops-desk for distribution
set -euo pipefail

OUT="${1:-dist/devops-desk}"
mkdir -p "$(dirname "$OUT")"

{
  # Shebang + header
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  echo '# devops-desk — bundled single-file distribution'
  echo ''

  # Inline all lib files (strip shebang + set -euo lines)
  for f in lib/core.sh lib/state.sh lib/checks.sh; do
    echo "# --- ${f} ---"
    grep -v '^#!/' "$f" | grep -v '^set -euo' || true
    echo ''
  done

  # Inline config.sh from root
  echo "# --- config.sh ---"
  grep -v '^#!/' config.sh | grep -v '^set -euo' || true
  echo ''

  # Create a function to load environment configs
  echo '# --- Environment config loader ---'
  echo 'load_env_config() {'
  echo '  local env="$1"'
  echo '  case "$env" in'
  
  # Embed all environment configs
  for env_file in config/envs/*.sh; do
    env_name=$(basename "$env_file" .sh)
    echo "    $env_name)"
    echo '      # Embedded config for '"$env_name"
    grep -v '^#!/' "$env_file" | grep -v '^set -euo' || true
    echo '      ;;'
  done
  
  echo '    *)'
  echo '      error "Unknown environment: $env"'
  echo '      echo "  Available: $(ls config/envs/ 2>/dev/null | sed \"s/\.sh$//\" | tr \"\\n\" \" \" 2>/dev/null || echo \"dev stage prod\")"'
  echo '      exit 1'
  echo '      ;;'
  echo '  esac'
  echo '}'
  echo ''

  # Override require_env to use load_env_config
  echo '# --- Override require_env for bundled version ---'
  echo 'require_env() {'
  echo '  local env'
  echo '  env=$(state_get_env)'
  echo '  if [[ -z "$env" ]]; then'
  echo '    error "No environment selected. Run: devops-desk env"'
  echo '    exit 1'
  echo '  fi'
  echo '  load_env_config "$env"'
  echo '  echo "$env"'
  echo '}'
  echo ''

  # Inline all commands (strip shebang + set -euo)
  for f in commands/*.sh; do
    echo "# --- ${f} ---"
    grep -v '^#!/' "$f" | grep -v '^set -euo' || true
    echo ''
  done

  # Process the main script
  echo "# --- Main script ---"
  
  # Read bin/devops-desk and transform it
  while IFS= read -r line; do
    # Skip shebang and set -euo
    [[ "$line" =~ ^#!/ ]] && continue
    [[ "$line" == "set -euo pipefail" ]] && continue
    
    # Skip SCRIPT_DIR and DEVOPS_DESK_ROOT setup
    [[ "$line" =~ ^SCRIPT_DIR= ]] && continue
    [[ "$line" =~ ^DEVOPS_DESK_ROOT= ]] && continue
    
    # Skip source lines (everything is inlined)
    [[ "$line" =~ ^source\  ]] && continue
    
    # Replace source "$DEVOPS_DESK_ROOT/config/envs/${env}.sh" with load_env_config
    if [[ "$line" == *'source "$DEVOPS_DESK_ROOT/config/envs/${env}.sh"'* ]]; then
      echo '  load_env_config "$env"'
      continue
    fi
    
    # Fix cmd_env to work without DEVOPS_DESK_ROOT
    if [[ "$line" == *'envs=$(ls "$DEVOPS_DESK_ROOT/config/envs/"'* ]]; then
      echo '      local envs'
      echo '      envs="dev stage prod"  # Hardcoded for bundled version'
      continue
    fi
    
    if [[ "$line" == *'if [[ ! -f "$DEVOPS_DESK_ROOT/config/envs/${env}.sh" ]]; then'* ]]; then
      echo '    if [[ ! "$env" =~ ^(dev|stage|prod)$ ]]; then'
      continue
    fi
    
    # Output the line
    echo "$line"
  done < bin/devops-desk

} > "$OUT"

chmod +x "$OUT"
echo "Bundled: $OUT"
