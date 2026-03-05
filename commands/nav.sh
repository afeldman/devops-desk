#!/usr/bin/env bash
# FZF Kubernetes Navigator — the core interactive exploration layer

cmd_nav() {
  check_all_deps

  local resource="${1:-}"
  shift || true

  case "$resource" in
    pods|pod|po)          nav_pods "$@" ;;
    deployments|deploy)   nav_deployments "$@" ;;
    services|svc)         nav_services "$@" ;;
    namespaces|ns)        nav_namespaces "$@" ;;
    helm)                 nav_helm "$@" ;;
    flux)                 nav_flux "$@" ;;
    nodes|node)           nav_nodes "$@" ;;
    oci|oras)             nav_oci "$@" ;;
    "")                   nav_main_menu ;;
    *)
      error "nav: unknown resource: $resource"
      echo "  Available: pods, deployments, services, namespaces, helm, flux, nodes, oci"
      exit 1 ;;
  esac
}

nav_main_menu() {
  local choice
  choice=$(printf '%s\n' \
    "pods           Search pods (logs / exec / restart / port-forward)" \
    "deployments    Search deployments (restart / scale / history)" \
    "services       Search services (describe / port-forward)" \
    "namespaces     Switch current namespace" \
    "helm           Browse Helm releases (upgrade / rollback / values)" \
    "flux           Browse Flux resources (reconcile / suspend / resume)" \
    "oci            Browse OCI registries via oras (repos / tags / manifests)" \
    "nodes          View cluster nodes" \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Navigate > " \
      --header="devops-desk navigator — select resource type" \
      --height=14) || return 0

  [[ -z "$choice" ]] && return
  cmd_nav "$(echo "$choice" | awk '{print $1}')"
}

# ─── Helpers ──────────────────────────────────────────────────────────────────
_ns_flag() {
  local ns
  ns=$(state_get_namespace 2>/dev/null || echo "")
  if [[ -n "$ns" ]]; then
    echo "-n $ns"
  else
    echo "--all-namespaces"
  fi
}

# ─── Pods ─────────────────────────────────────────────────────────────────────
nav_pods() {
  # shellcheck disable=SC2046
  kubectl get pods $(_ns_flag) --no-headers \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,NODE:.spec.nodeName' \
    2>/dev/null \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Pod > " \
    --header="CTRL-L: logs  CTRL-E: exec  CTRL-D: describe  CTRL-R: restart deploy  CTRL-F: port-forward  CTRL-X: delete" \
    --preview='kubectl describe pod {2} -n {1} 2>/dev/null | head -60' \
    --preview-window='right:60%:wrap' \
    --bind='ctrl-l:execute(kubectl logs -f --tail=200 {2} -n {1} 2>&1 | less +F)' \
    --bind='ctrl-e:execute(kubectl exec -it {2} -n {1} -- sh 2>/dev/null || kubectl exec -it {2} -n {1} -- bash)' \
    --bind='ctrl-d:execute(kubectl describe pod {2} -n {1} | less)' \
    --bind='ctrl-r:execute(kubectl rollout restart deployment -n {1} --selector=$(kubectl get pod {2} -n {1} -o jsonpath="{.metadata.labels}" 2>/dev/null | tr -d "{}" | sed "s/: /=/g;s/,/ /g" | awk "{print $1}") 2>/dev/null || echo "Could not determine owner deployment")' \
    --bind='ctrl-f:execute(read -p "Local port: " lp && read -p "Remote port: " rp && kubectl port-forward {2} -n {1} "$lp:$rp")' \
    --bind='ctrl-x:execute(kubectl delete pod {2} -n {1})'
}

# ─── Deployments ──────────────────────────────────────────────────────────────
nav_deployments() {
  # shellcheck disable=SC2046
  kubectl get deployments $(_ns_flag) --no-headers \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas,UP-TO-DATE:.status.updatedReplicas,AGE:.metadata.creationTimestamp' \
    2>/dev/null \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Deployment > " \
    --header="CTRL-R: restart  CTRL-S: scale  CTRL-H: history  CTRL-D: describe  CTRL-I: images" \
    --preview='kubectl describe deployment {2} -n {1} 2>/dev/null | head -60' \
    --preview-window='right:60%:wrap' \
    --bind='ctrl-r:execute(kubectl rollout restart deployment/{2} -n {1} && kubectl rollout status deployment/{2} -n {1})' \
    --bind='ctrl-s:execute(read -p "Scale {2} to replicas: " r && kubectl scale deployment/{2} -n {1} --replicas="$r")' \
    --bind='ctrl-h:execute(kubectl rollout history deployment/{2} -n {1} | less)' \
    --bind='ctrl-d:execute(kubectl describe deployment {2} -n {1} | less)' \
    --bind='ctrl-i:execute(kubectl get deployment {2} -n {1} -o jsonpath="{.spec.template.spec.containers[*].image}" | tr " " "\n")'
}

# ─── Services ─────────────────────────────────────────────────────────────────
nav_services() {
  # shellcheck disable=SC2046
  kubectl get services $(_ns_flag) --no-headers \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,PORT:.spec.ports[0].port' \
    2>/dev/null \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Service > " \
    --header="CTRL-D: describe  CTRL-F: port-forward  CTRL-E: endpoints" \
    --preview='kubectl describe svc {2} -n {1} 2>/dev/null | head -40' \
    --preview-window='right:50%:wrap' \
    --bind='ctrl-d:execute(kubectl describe svc {2} -n {1} | less)' \
    --bind='ctrl-f:execute(read -p "Local port (default {5}): " lp; lp=${lp:-{5}}; kubectl port-forward svc/{2} -n {1} "$lp:{5}")' \
    --bind='ctrl-e:execute(kubectl get endpoints {2} -n {1} -o yaml | less)'
}

# ─── Namespaces ───────────────────────────────────────────────────────────────
nav_namespaces() {
  local selected
  selected=$(kubectl get namespaces --no-headers \
    -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,AGE:.metadata.creationTimestamp' \
    2>/dev/null \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Namespace > " \
    --header="Select namespace  (CTRL-D: describe  CTRL-P: list pods)" \
    --preview='kubectl get all -n {1} --no-headers 2>/dev/null | head -30' \
    --preview-window='right:50%:wrap' \
    --bind='ctrl-d:execute(kubectl describe namespace {1} | less)' \
    --bind='ctrl-p:execute(kubectl get pods -n {1} | less)') || return 0

  [[ -z "$selected" ]] && return
  local ns
  ns=$(echo "$selected" | awk '{print $1}')
  kubectl config set-context --current --namespace="$ns"
  state_set_namespace "$ns"
  success "Switched to namespace: $ns"
}

# ─── Helm ─────────────────────────────────────────────────────────────────────
nav_helm() {
  check_dependency helm

  helm list --all-namespaces --no-headers 2>/dev/null \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Helm Release > " \
    --header="CTRL-U: upgrade  CTRL-H: history  CTRL-V: values  CTRL-R: rollback  CTRL-D: diff" \
    --preview='helm status {1} -n {2} 2>/dev/null | head -40' \
    --preview-window='right:50%:wrap' \
    --bind='ctrl-h:execute(helm history {1} -n {2} | less)' \
    --bind='ctrl-v:execute(helm get values {1} -n {2} | less)' \
    --bind='ctrl-r:execute(helm rollback {1} -n {2})'
}

# ─── Flux ─────────────────────────────────────────────────────────────────────
nav_flux() {
  check_dependency flux

  local choice
  choice=$(printf '%s\n' \
    "kustomizations    GitOps kustomization deployments" \
    "helmreleases      Helm releases managed by Flux" \
    "sources           Git/Helm/OCI source repositories" \
    "imageautomations  Flux image update automations" \
    "imagepolicies     Image update policies" \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Flux resource type > " \
      --header="Select Flux resource type to browse" \
      --height=12) || return 0

  [[ -z "$choice" ]] && return
  local resource
  resource=$(echo "$choice" | awk '{print $1}')

  case "$resource" in
    kustomizations)   _nav_flux_ks ;;
    helmreleases)     _nav_flux_hr ;;
    sources)          _nav_flux_sources ;;
    imageautomations) _nav_flux_image_automations ;;
    imagepolicies)    _nav_flux_image_policies ;;
  esac
}

_nav_flux_ks() {
  kubectl get kustomizations.kustomize.toolkit.fluxcd.io \
    --all-namespaces --no-headers 2>/dev/null \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Flux Kustomization > " \
    --header="CTRL-R: reconcile  CTRL-S: suspend  CTRL-U: resume  CTRL-D: describe" \
    --preview='kubectl describe kustomization.kustomize.toolkit.fluxcd.io {2} -n {1} 2>/dev/null | head -50' \
    --preview-window='right:60%:wrap' \
    --bind='ctrl-r:execute(flux reconcile kustomization {2} -n {1} --with-source)' \
    --bind='ctrl-s:execute(flux suspend kustomization {2} -n {1})' \
    --bind='ctrl-u:execute(flux resume kustomization {2} -n {1})' \
    --bind='ctrl-d:execute(kubectl describe kustomization.kustomize.toolkit.fluxcd.io {2} -n {1} | less)'
}

_nav_flux_hr() {
  kubectl get helmreleases.helm.toolkit.fluxcd.io \
    --all-namespaces --no-headers 2>/dev/null \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Flux HelmRelease > " \
    --header="CTRL-R: reconcile  CTRL-S: suspend  CTRL-U: resume  CTRL-D: describe" \
    --preview='kubectl describe helmrelease.helm.toolkit.fluxcd.io {2} -n {1} 2>/dev/null | head -50' \
    --preview-window='right:60%:wrap' \
    --bind='ctrl-r:execute(flux reconcile helmrelease {2} -n {1})' \
    --bind='ctrl-s:execute(flux suspend helmrelease {2} -n {1})' \
    --bind='ctrl-u:execute(flux resume helmrelease {2} -n {1})' \
    --bind='ctrl-d:execute(kubectl describe helmrelease.helm.toolkit.fluxcd.io {2} -n {1} | less)'
}

_nav_flux_sources() {
  {
    kubectl get gitrepositories.source.toolkit.fluxcd.io  --all-namespaces --no-headers 2>/dev/null | awk '{print $1, $2, "GitRepository",  $3, $4}'
    kubectl get helmrepositories.source.toolkit.fluxcd.io --all-namespaces --no-headers 2>/dev/null | awk '{print $1, $2, "HelmRepository", $3, $4}'
    kubectl get ocirepositories.source.toolkit.fluxcd.io  --all-namespaces --no-headers 2>/dev/null | awk '{print $1, $2, "OCIRepository",  $3, $4}'
  } | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Flux Source > " \
    --header="CTRL-R: reconcile  CTRL-D: describe" \
    --preview-window='right:50%:wrap' \
    --bind='ctrl-r:execute(flux reconcile source git {2} -n {1} 2>/dev/null || flux reconcile source helm {2} -n {1} 2>/dev/null)'
}

_nav_flux_image_automations() {
  kubectl get imageupdateautomations.image.toolkit.fluxcd.io \
    --all-namespaces --no-headers 2>/dev/null \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Flux Image Automation > " \
    --header="CTRL-R: reconcile  CTRL-D: describe" \
    --preview='kubectl describe imageupdateautomation.image.toolkit.fluxcd.io {2} -n {1} 2>/dev/null | head -50' \
    --preview-window='right:60%:wrap' \
    --bind='ctrl-r:execute(flux reconcile image update {2} -n {1})' \
    --bind='ctrl-d:execute(kubectl describe imageupdateautomation.image.toolkit.fluxcd.io {2} -n {1} | less)'
}

_nav_flux_image_policies() {
  kubectl get imagepolicies.image.toolkit.fluxcd.io \
    --all-namespaces --no-headers 2>/dev/null \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Flux Image Policy > " \
    --header="CTRL-D: describe" \
    --preview='kubectl describe imagepolicy.image.toolkit.fluxcd.io {2} -n {1} 2>/dev/null' \
    --preview-window='right:60%:wrap' \
    --bind='ctrl-d:execute(kubectl describe imagepolicy.image.toolkit.fluxcd.io {2} -n {1} | less)'
}

# ─── Nodes ────────────────────────────────────────────────────────────────────
nav_nodes() {
  kubectl get nodes --no-headers \
    -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[-1].type,VERSION:.status.nodeInfo.kubeletVersion,INSTANCE:.metadata.labels.node\.kubernetes\.io/instance-type,AGE:.metadata.creationTimestamp' \
    2>/dev/null \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Node > " \
    --header="CTRL-D: describe  CTRL-P: pods on node  CTRL-T: top" \
    --preview='kubectl describe node {1} 2>/dev/null | head -50' \
    --preview-window='right:60%:wrap' \
    --bind='ctrl-d:execute(kubectl describe node {1} | less)' \
    --bind='ctrl-p:execute(kubectl get pods --all-namespaces --field-selector spec.nodeName={1} | less)' \
    --bind='ctrl-t:execute(kubectl top node {1})'
}

# ─── OCI / oras ───────────────────────────────────────────────────────────────
# Entry point: collects registries from Flux OCI sources + manual input,
# then drills down repo → tags → manifest inspect.
nav_oci() {
  check_dependency oras

  # Build registry list from Flux OCI sources (if CRD exists)
  local flux_registries=()
  if kubectl get crd ocirepositories.source.toolkit.fluxcd.io &>/dev/null 2>&1; then
    while IFS= read -r url; do
      [[ -n "$url" ]] && flux_registries+=("$url")
    done < <(kubectl get ocirepositories.source.toolkit.fluxcd.io \
      --all-namespaces -o jsonpath='{.items[*].spec.url}' 2>/dev/null \
      | tr ' ' '\n' \
      | sed 's|^oci://||')
  fi

  # Combine with any extra registries defined in env config
  local extra_registries=()
  if [[ -n "${DD_OCI_REGISTRIES:-}" ]]; then
    IFS=',' read -ra extra_registries <<< "$DD_OCI_REGISTRIES"
  fi

  local all_registries=("${flux_registries[@]}" "${extra_registries[@]}")

  local registry
  if [[ ${#all_registries[@]} -eq 0 ]]; then
    # No sources found — ask for manual input
    echo -en "\n  OCI registry (e.g. ghcr.io/myorg): "
    read -r registry
    [[ -z "$registry" ]] && return
  else
    # Deduplicate and let user pick (or type a custom one)
    registry=$(printf '%s\n' "${all_registries[@]}" | sort -u \
      | fzf "${DD_FZF_OPTS[@]}" \
        --prompt="OCI Registry > " \
        --header="Registries from Flux OCI sources  (type to filter or enter a custom one)" \
        --print-query \
        --height=14 \
      | tail -1) || return 0
    [[ -z "$registry" ]] && return
    # Strip oci:// prefix if pasted with it
    registry="${registry#oci://}"
  fi

  _nav_oci_repos "$registry"
}

# List repositories inside a registry and drill into tags
_nav_oci_repos() {
  local registry="$1"

  local selected
  selected=$(oras repo ls "$registry" 2>/dev/null \
    | awk -v r="$registry" '{print r "/" $0}' \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Repo > " \
      --header="$registry  —  ENTER: browse tags  CTRL-D: discover (oras repo ls)" \
      --preview='oras repo tags {1} 2>/dev/null | head -40' \
      --preview-window='right:40%:wrap' \
      --bind="ctrl-d:execute(oras repo ls $registry 2>/dev/null | less)") || return 0

  [[ -z "$selected" ]] && return
  _nav_oci_tags "$selected"
}

# List tags for a repository and drill into manifest inspect
_nav_oci_tags() {
  local repo="$1"

  local selected
  selected=$(oras repo tags "$repo" 2>/dev/null \
    | sort -rV \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Tag > " \
      --header="$repo  —  ENTER: inspect manifest  CTRL-P: pull  CTRL-C: copy ref" \
      --preview="oras manifest fetch ${repo}:{} 2>/dev/null | ${_JSON_PRETTY:-cat}" \
      --preview-window='right:60%:wrap' \
      --bind="ctrl-p:execute(oras pull ${repo}:{1})" \
      --bind="ctrl-c:execute(echo -n '${repo}:{1}' | pbcopy && echo 'Copied: ${repo}:{1}')") || return 0

  [[ -z "$selected" ]] && return
  _nav_oci_manifest "$repo" "$selected"
}

# Show full manifest + config for a specific tag
_nav_oci_manifest() {
  local repo="$1" tag="$2"
  local ref="${repo}:${tag}"

  # Pretty-print JSON if possible
  local pretty_cmd="cat"
  command -v jq &>/dev/null && pretty_cmd="jq ."

  step "OCI Manifest: $ref"
  echo ""
  echo -e "${BOLD}Manifest${RESET}"
  oras manifest fetch "$ref" 2>/dev/null | $pretty_cmd

  echo ""
  echo -e "${BOLD}Layers / Config${RESET}"
  oras manifest fetch --descriptor "$ref" 2>/dev/null | $pretty_cmd

  echo ""
  echo -e "${DIM}  press q to close${RESET}"
  read -r -n1 -s
}
