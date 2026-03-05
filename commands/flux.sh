#!/usr/bin/env bash

cmd_flux() {
  check_dependency flux

  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    reconcile) flux_reconcile "$@" ;;
    status)    flux_status ;;
    images)    flux_images ;;
    suspend)   _flux_toggle_resource "suspend" ;;
    resume)    _flux_toggle_resource "resume" ;;
    "")        flux_menu ;;
    *)
      error "flux: unknown subcommand: $subcommand"
      echo "  Usage: devops-desk flux [reconcile|status|images|suspend|resume]"
      exit 1 ;;
  esac
}

flux_menu() {
  local choice
  choice=$(printf '%s\n' \
    "reconcile   Trigger Flux reconciliation" \
    "status      Show Flux kustomizations + HelmRelease status" \
    "images      Show Flux image automation updates" \
    "suspend     Suspend a Flux resource" \
    "resume      Resume a suspended Flux resource" \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Flux > " \
      --header="Flux Operations" \
      --height=12) || return 0

  [[ -z "$choice" ]] && return
  cmd_flux "$(echo "$choice" | awk '{print $1}')"
}

flux_reconcile() {
  # If args are passed directly (e.g. "flux reconcile kustomization foo -n bar"), use them
  if [[ $# -gt 0 ]]; then
    flux reconcile "$@"
    return
  fi

  step "Flux Reconcile"

  # Interactive: pick resource type
  local resource_type
  resource_type=$(printf '%s\n' \
    "kustomization" "helmrelease" "source git" "source helm" "source oci" \
    | fzf --prompt="Resource type > " --height=10 --border=rounded) || return 0
  [[ -z "$resource_type" ]] && return

  # Pick resource by name
  local crd_kind
  case "$resource_type" in
    kustomization) crd_kind="kustomizations.kustomize.toolkit.fluxcd.io" ;;
    helmrelease)   crd_kind="helmreleases.helm.toolkit.fluxcd.io" ;;
    source*)       crd_kind="gitrepositories.source.toolkit.fluxcd.io helmrepositories.source.toolkit.fluxcd.io ocirepositories.source.toolkit.fluxcd.io" ;;
  esac

  local selected
  # shellcheck disable=SC2086
  selected=$(kubectl get $crd_kind --all-namespaces --no-headers 2>/dev/null \
    | fzf --prompt="Select resource > " --height=20 --border=rounded) || return 0
  [[ -z "$selected" ]] && return

  local ns name
  ns=$(echo "$selected" | awk '{print $1}')
  name=$(echo "$selected" | awk '{print $2}')

  info "Reconciling: $resource_type/$name (namespace: $ns)"
  flux reconcile $resource_type "$name" -n "$ns" --with-source
  success "Reconciliation complete"
}

flux_status() {
  step "Flux Status"
  echo ""

  echo -e "${BOLD}Kustomizations${RESET}"
  kubectl get kustomizations.kustomize.toolkit.fluxcd.io --all-namespaces \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status,MSG:.status.conditions[0].message' \
    2>/dev/null \
  | awk 'NR==1{print; next}
         /True/  {print "\033[32m" $0 "\033[0m"; next}
         /False/ {print "\033[31m" $0 "\033[0m"; next}
                 {print}'

  echo ""
  echo -e "${BOLD}HelmReleases${RESET}"
  kubectl get helmreleases.helm.toolkit.fluxcd.io --all-namespaces \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status,MSG:.status.conditions[0].message' \
    2>/dev/null \
  | awk 'NR==1{print; next}
         /True/  {print "\033[32m" $0 "\033[0m"; next}
         /False/ {print "\033[31m" $0 "\033[0m"; next}
                 {print}'

  echo ""
  echo -e "${BOLD}Sources${RESET}"
  {
    kubectl get gitrepositories.source.toolkit.fluxcd.io  --all-namespaces --no-headers 2>/dev/null | awk '{print $1, $2, "(git)",  $3}'
    kubectl get helmrepositories.source.toolkit.fluxcd.io --all-namespaces --no-headers 2>/dev/null | awk '{print $1, $2, "(helm)", $3}'
    kubectl get ocirepositories.source.toolkit.fluxcd.io  --all-namespaces --no-headers 2>/dev/null | awk '{print $1, $2, "(oci)",  $3}'
  } | awk '/True/  {print "\033[32m✓\033[0m", $0; next}
           /False/ {print "\033[31m✗\033[0m", $0; next}
                   {print "  ", $0}'
}

flux_images() {
  step "Flux Image Automation"
  echo ""

  echo -e "${BOLD}Image Update Automations${RESET}"
  kubectl get imageupdateautomations.image.toolkit.fluxcd.io --all-namespaces \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status,LAST-PUSH:.status.lastPushTime' \
    2>/dev/null

  echo ""
  echo -e "${BOLD}Image Policies${RESET}"
  kubectl get imagepolicies.image.toolkit.fluxcd.io --all-namespaces \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,LATEST:.status.latestImage' \
    2>/dev/null

  echo ""
  echo -e "${BOLD}Image Repositories${RESET}"
  kubectl get imagerepositories.image.toolkit.fluxcd.io --all-namespaces \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,IMAGE:.spec.image,READY:.status.conditions[0].status,LAST-SCAN:.status.lastScanTime' \
    2>/dev/null
}

_flux_toggle_resource() {
  local action="$1"

  local selected
  selected=$(kubectl get \
    kustomizations.kustomize.toolkit.fluxcd.io,helmreleases.helm.toolkit.fluxcd.io \
    --all-namespaces --no-headers 2>/dev/null \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="${action^} resource > " \
    --header="Select Flux resource to ${action} (TAB for multi-select)" \
    --multi) || return 0

  [[ -z "$selected" ]] && return

  while IFS= read -r line; do
    local ns name kind
    ns=$(echo "$line" | awk '{print $1}')
    name=$(echo "$line" | awk '{print $2}')
    # Infer type from the "kind" column k8s shows for mixed queries
    if echo "$line" | grep -qi "kustomization"; then
      kind="kustomization"
    else
      kind="helmrelease"
    fi
    flux "$action" "$kind" "$name" -n "$ns"
    success "${action^}d: $kind/$name (namespace: $ns)"
  done <<< "$selected"
}
