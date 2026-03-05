#!/usr/bin/env bash
# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

color_red()    { printf "${RED}%s${RESET}" "$*"; }
color_green()  { printf "${GREEN}%s${RESET}" "$*"; }
color_yellow() { printf "${YELLOW}%s${RESET}" "$*"; }
color_blue()   { printf "${BLUE}%s${RESET}" "$*"; }
color_cyan()   { printf "${CYAN}%s${RESET}" "$*"; }
color_bold()   { printf "${BOLD}%s${RESET}" "$*"; }
color_dim()    { printf "${DIM}%s${RESET}" "$*"; }

info()    { echo -e "  ${BLUE}ℹ${RESET}  $*"; }
success() { echo -e "  ${GREEN}✓${RESET}  $*"; }
warning() { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
error()   { echo -e "  ${RED}✗${RESET}  $*" >&2; }
step()    { echo -e "\n${BOLD}${CYAN}▶${RESET} ${BOLD}$*${RESET}"; }

# ─── Environment helpers ──────────────────────────────────────────────────────
# Sources the current environment config and exports its variables.
# Exits with an error if no environment is selected.
require_env() {
  local env
  env=$(state_get_env)
  if [[ -z "$env" ]]; then
    error "No environment selected. Run: devops-desk env"
    exit 1
  fi
  source "$DEVOPS_DESK_ROOT/config/envs/${env}.sh"
  echo "$env"
}

# ─── Confirmation prompt ──────────────────────────────────────────────────────
confirm() {
  local msg="${1:-Are you sure?}"
  local env
  env=$(state_get_env 2>/dev/null || echo "")

  if [[ "$env" == "prod" ]]; then
    echo -e "  ${RED}${BOLD}⚠  PRODUCTION ENVIRONMENT${RESET}"
  fi

  echo -en "  ${YELLOW}?${RESET}  ${msg} [y/N] "
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}
