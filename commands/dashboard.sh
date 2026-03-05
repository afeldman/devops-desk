#!/usr/bin/env bash
# DevOps Dashboard — high-level operational overview rendered in the terminal

cmd_dashboard() {
  local env
  env=$(require_env)

  clear
  _dashboard_render "$env"

  echo ""
  echo -e "  ${DIM}Press 'r' to refresh · 'q' to quit · auto-refreshes every 30s${RESET}"

  while true; do
    local key=""
    read -r -n1 -t 30 key 2>/dev/null || key="r"
    case "$key" in
      q|Q) echo ""; break ;;
      *)   clear; _dashboard_render "$env" ;;
    esac
  done
}

_dashboard_render() {
  local env="${1:-unknown}"

  local ctx ns
  ctx=$(kubectl config current-context 2>/dev/null || echo "none")
  ns=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || echo "default")
  [[ -z "$ns" ]] && ns="default"

  # ── Header ──────────────────────────────────────────────────────────────────
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════╗${RESET}"
  printf "${BOLD}${CYAN}║${RESET}  ${BOLD}%-63s${BOLD}${CYAN}║${RESET}\n" "devops-desk  $(date '+%Y-%m-%d %H:%M:%S')"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""

  # ── Environment info ────────────────────────────────────────────────────────
  local env_color=""
  case "$env" in
    prod*) env_color="${RED}${BOLD}" ;;
    stage*) env_color="${YELLOW}" ;;
    *) env_color="${GREEN}" ;;
  esac

  printf "  %-16s ${env_color}%s${RESET}\n" "Environment:" "$env"
  printf "  %-16s %s\n" "Context:"     "$ctx"
  printf "  %-16s %s\n" "Namespace:"   "$ns"
  echo ""
  echo -e "  ${DIM}──────────────────────────────────────────────────────────────────${RESET}"

  # ── Pods ────────────────────────────────────────────────────────────────────
  echo ""
  echo -e "  ${BOLD}Pods${RESET}"
  _dash_pods

  # ── Deployments ─────────────────────────────────────────────────────────────
  echo ""
  echo -e "  ${BOLD}Deployments${RESET}"
  _dash_deployments

  # ── Flux ────────────────────────────────────────────────────────────────────
  if kubectl get crd kustomizations.kustomize.toolkit.fluxcd.io &>/dev/null 2>&1; then
    echo ""
    echo -e "  ${BOLD}Flux${RESET}"
    _dash_flux
  fi

  # ── Flux Image Updates ──────────────────────────────────────────────────────
  if kubectl get crd imagepolicies.image.toolkit.fluxcd.io &>/dev/null 2>&1; then
    echo ""
    echo -e "  ${BOLD}Flux Image Updates${RESET}"
    _dash_flux_images
  fi

  # ── Helm ────────────────────────────────────────────────────────────────────
  if command -v helm &>/dev/null; then
    echo ""
    echo -e "  ${BOLD}Helm Releases${RESET}"
    _dash_helm
  fi

  echo ""
}

_dash_pods() {
  local total running pending failed restarts
  total=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
  running=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep -c "Running" 2>/dev/null || echo 0)
  pending=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep -c "Pending" 2>/dev/null || echo 0)
  failed=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep -cE "Error|CrashLoopBackOff|OOMKilled|Failed|ImagePullBackOff|ErrImagePull" 2>/dev/null || echo 0)

  printf "  ${GREEN}✓ Running:${RESET} %-5s  ${YELLOW}⏳ Pending:${RESET} %-5s  ${RED}✗ Failing:${RESET} %-5s  Total: %s\n" \
    "$running" "$pending" "$failed" "$total"

  if [[ "$failed" -gt 0 ]]; then
    echo ""
    kubectl get pods --all-namespaces --no-headers 2>/dev/null \
      | grep -E "Error|CrashLoopBackOff|OOMKilled|Failed|ImagePullBackOff|ErrImagePull" \
      | awk '{printf "    \033[31m✗\033[0m %-35s %-20s %s\n", $2, $1, $4}' \
      | head -8
  fi
}

_dash_deployments() {
  local total degraded ready
  total=$(kubectl get deployments --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
  degraded=$(kubectl get deployments --all-namespaces --no-headers 2>/dev/null \
    | awk '$3 != $4 {count++} END {print count+0}')
  ready=$((total - degraded))

  printf "  ${GREEN}✓ Ready:${RESET} %-5s  ${RED}✗ Degraded:${RESET} %-5s  Total: %s\n" "$ready" "$degraded" "$total"

  if [[ "$degraded" -gt 0 ]]; then
    echo ""
    kubectl get deployments --all-namespaces --no-headers 2>/dev/null \
      | awk '$3 != $4 {printf "    \033[31m✗\033[0m %-35s %-20s %s/%s\n", $2, $1, $3, $4}' \
      | head -6
  fi
}

_dash_flux() {
  local ks_total ks_ready ks_failing hr_total hr_ready hr_failing

  ks_total=$(kubectl get kustomizations.kustomize.toolkit.fluxcd.io --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
  ks_ready=$(kubectl get kustomizations.kustomize.toolkit.fluxcd.io --all-namespaces 2>/dev/null | grep -c "True" 2>/dev/null || echo 0)
  ks_failing=$((ks_total - ks_ready))

  hr_total=$(kubectl get helmreleases.helm.toolkit.fluxcd.io --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
  hr_ready=$(kubectl get helmreleases.helm.toolkit.fluxcd.io --all-namespaces 2>/dev/null | grep -c "True" 2>/dev/null || echo 0)
  hr_failing=$((hr_total - hr_ready))

  printf "  Kustomizations: ${GREEN}✓ %s synced${RESET}" "$ks_ready"
  [[ "$ks_failing" -gt 0 ]] && printf "   ${RED}✗ %s failing${RESET}" "$ks_failing"
  echo ""

  printf "  HelmReleases:   ${GREEN}✓ %s ready${RESET}" "$hr_ready"
  [[ "$hr_failing" -gt 0 ]] && printf "   ${RED}✗ %s failing${RESET}" "$hr_failing"
  echo ""

  if [[ "$ks_failing" -gt 0 ]]; then
    kubectl get kustomizations.kustomize.toolkit.fluxcd.io --all-namespaces 2>/dev/null \
      | grep -v "True\|^NAMESPACE" \
      | awk '{printf "    \033[31m✗\033[0m %-30s %s\n", $2, $4}' | head -5
  fi
  if [[ "$hr_failing" -gt 0 ]]; then
    kubectl get helmreleases.helm.toolkit.fluxcd.io --all-namespaces 2>/dev/null \
      | grep -v "True\|^NAMESPACE" \
      | awk '{printf "    \033[31m✗\033[0m %-30s %s\n", $2, $4}' | head -5
  fi
}

_dash_flux_images() {
  local count
  count=$(kubectl get imagepolicies.image.toolkit.fluxcd.io --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$count" -eq 0 ]]; then
    echo "    (no image policies configured)"
    return
  fi

  kubectl get imagepolicies.image.toolkit.fluxcd.io --all-namespaces --no-headers \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,LATEST:.status.latestImage' \
    2>/dev/null \
  | awk 'NR>0 {printf "    %-28s  %s\n", $2, $3}' | head -10
}

_dash_helm() {
  local total failed deployed
  total=$(helm list --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
  failed=$(helm list --all-namespaces --no-headers 2>/dev/null | grep -c "failed" 2>/dev/null || echo 0)
  deployed=$((total - failed))

  printf "  ${GREEN}✓ Deployed:${RESET} %-5s  ${RED}✗ Failed:${RESET} %-5s  Total: %s\n" "$deployed" "$failed" "$total"

  if [[ "$failed" -gt 0 ]]; then
    helm list --all-namespaces --no-headers 2>/dev/null \
      | grep "failed" \
      | awk '{printf "    \033[31m✗\033[0m %-30s %s\n", $1, $2}' | head -5
  fi
}
