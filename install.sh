#!/usr/bin/env bash
set -euo pipefail

DEVOPS_DESK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${DEVOPS_DESK_INSTALL_DIR:-/usr/local/bin}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "  ${BOLD}→${RESET} $*"; }
success() { echo -e "  ${GREEN}✓${RESET} $*"; }
warning() { echo -e "  ${YELLOW}⚠${RESET} $*"; }
fail()    { echo -e "  ${RED}✗${RESET} $*" >&2; exit 1; }

echo ""
echo -e "${BOLD}Installing devops-desk${RESET}"
echo "══════════════════════"
echo ""

# ── Bash version check ────────────────────────────────────────────────────────
bash_major="${BASH_VERSINFO[0]}"
if [[ "$bash_major" -lt 4 ]]; then
  echo -e "  ${RED}✗${RESET}  bash 4+ required — you are running bash ${BASH_VERSION}" >&2
  echo ""
  echo "  macOS ships with bash 3.2 (GPL). Install a modern version via Homebrew:"
  echo "    brew install bash"
  echo ""
  echo "  Then add it to your shell config so \`/usr/bin/env bash\` resolves to it:"
  echo "    echo \"\$(brew --prefix)/bin/bash\" | sudo tee -a /etc/shells"
  echo "    chsh -s \"\$(brew --prefix)/bin/bash\"   # optional: set as login shell"
  echo ""
  exit 1
fi
success "bash ${BASH_VERSION} OK"

# ── Dependency check ──────────────────────────────────────────────────────────
REQUIRED=(aws kubectl fzf)
OPTIONAL=(k9s flux helm gh bat stern oras)

info "Checking required dependencies…"
missing_required=()
for dep in "${REQUIRED[@]}"; do
  command -v "$dep" &>/dev/null || missing_required+=("$dep")
done

if [[ ${#missing_required[@]} -gt 0 ]]; then
  fail "Missing required tools: ${missing_required[*]}\n  Install: brew install ${missing_required[*]}"
fi
success "Required dependencies OK"

missing_optional=()
for dep in "${OPTIONAL[@]}"; do
  command -v "$dep" &>/dev/null || missing_optional+=("$dep")
done
if [[ ${#missing_optional[@]} -gt 0 ]]; then
  warning "Optional tools not installed: ${missing_optional[*]}"
  echo "    brew install ${missing_optional[*]}"
fi

# ── Permissions ───────────────────────────────────────────────────────────────
info "Setting script permissions…"
chmod +x "$DEVOPS_DESK_ROOT/bin/devops-desk"
chmod +x "$DEVOPS_DESK_ROOT/commands/"*.sh
chmod +x "$DEVOPS_DESK_ROOT/lib/"*.sh
success "Permissions set"

# ── Symlink ───────────────────────────────────────────────────────────────────
info "Creating symlink in $INSTALL_DIR…"
if [[ -w "$INSTALL_DIR" ]]; then
  ln -sf "$DEVOPS_DESK_ROOT/bin/devops-desk" "$INSTALL_DIR/devops-desk"
else
  sudo ln -sf "$DEVOPS_DESK_ROOT/bin/devops-desk" "$INSTALL_DIR/devops-desk"
fi
success "Symlink created: $INSTALL_DIR/devops-desk"

# ── State directory ───────────────────────────────────────────────────────────
mkdir -p "$HOME/.devops-desk"
success "State directory ready: ~/.devops-desk"

# ── k9s plugins ───────────────────────────────────────────────────────────────
if command -v k9s &>/dev/null; then
  K9S_CONFIG_DIR="${K9S_CONFIG_DIR:-$HOME/.config/k9s}"
  mkdir -p "$K9S_CONFIG_DIR/skins"

  if [[ -f "$K9S_CONFIG_DIR/plugins.yaml" ]]; then
    warning "k9s plugins.yaml already exists — backing up to plugins.yaml.bak"
    cp "$K9S_CONFIG_DIR/plugins.yaml" "$K9S_CONFIG_DIR/plugins.yaml.bak"
  fi
  cp "$DEVOPS_DESK_ROOT/k9s/plugins.yaml" "$K9S_CONFIG_DIR/plugins.yaml"
  cp "$DEVOPS_DESK_ROOT/k9s/skin.yaml"    "$K9S_CONFIG_DIR/skins/devops-desk.yaml"
  success "k9s plugins + skin installed"
fi

# ── Configure environments ────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Next step:${RESET} configure your environments"
echo -e "  Edit the following files with your AWS profiles + EKS cluster names:"
echo ""
for f in "$DEVOPS_DESK_ROOT/config/envs/"*.sh; do
  echo "    $f"
done
echo ""

echo -e "${GREEN}${BOLD}Installation complete!${RESET}"
echo ""
echo "  Quick start:"
echo -e "    ${BOLD}devops-desk env${RESET}        Select environment (dev / stage / prod)"
echo -e "    ${BOLD}devops-desk auth${RESET}       Authenticate via AWS SSO"
echo -e "    ${BOLD}devops-desk connect${RESET}    Configure kubeconfig for EKS"
echo -e "    ${BOLD}devops-desk dashboard${RESET}  Open DevOps dashboard"
echo -e "    ${BOLD}devops-desk nav${RESET}        FZF Kubernetes navigator"
echo ""
