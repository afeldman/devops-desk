#!/usr/bin/env bash
set -euo pipefail
# devops-desk — bundled single-file distribution

# --- lib/core.sh ---
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

# --- lib/state.sh ---
# Persists session state (current environment, namespace) to ~/.devops-desk/state

DEVOPS_DESK_STATE_DIR="${HOME}/.devops-desk"
DEVOPS_DESK_STATE_FILE="${DEVOPS_DESK_STATE_DIR}/state"

state_init() {
  mkdir -p "$DEVOPS_DESK_STATE_DIR"
  touch "$DEVOPS_DESK_STATE_FILE"
}

state_set() {
  local key="$1" value="$2"
  state_init
  local tmp
  tmp=$(mktemp)
  grep -v "^${key}=" "$DEVOPS_DESK_STATE_FILE" > "$tmp" 2>/dev/null || true
  echo "${key}=${value}" >> "$tmp"
  mv "$tmp" "$DEVOPS_DESK_STATE_FILE"
}

state_get() {
  local key="$1"
  grep "^${key}=" "$DEVOPS_DESK_STATE_FILE" 2>/dev/null | cut -d'=' -f2- || echo ""
}

state_set_env()       { state_set "ENVIRONMENT" "$1"; }
state_get_env()       { state_get "ENVIRONMENT"; }
state_set_namespace() { state_set "NAMESPACE" "$1"; }
state_get_namespace() { state_get "NAMESPACE"; }

# --- lib/checks.sh ---
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

# --- config.sh ---

# installation root
PREFIX="${PREFIX:-/opt/devops-desk}"

# binary directory
BIN_DIR="${BIN_DIR:-/usr/local/bin}"

# config directory
CONFIG_DIR="${HOME}/.devops-desk"

# k9s config
K9S_CONFIG_DIR="${K9S_CONFIG_DIR:-$HOME/.config/k9s}"

# --- Environment config loader ---
load_env_config() {
  local env="$1"
  case "$env" in
    dev)
      # Embedded config for dev
# Development environment configuration
# Copy and adapt for each environment.

export DD_AWS_PROFILE="dev"
export DD_AWS_REGION="eu-west-1"
export DD_EKS_CLUSTER="dev-eks-cluster"
export DD_EKS_CLUSTER_ALIAS="dev"

# Optional: pin to a default namespace
# export DD_NAMESPACE="default"

# Optional: extra OCI registries for `devops-desk nav oci` (comma-separated)
# Registries from Flux OCI sources are picked up automatically.
# export DD_OCI_REGISTRIES="ghcr.io/myorg,123456789.dkr.ecr.eu-west-1.amazonaws.com"
      ;;
    prod)
      # Embedded config for prod
# Production environment configuration
# All destructive operations prompt for confirmation when this env is active.

export DD_AWS_PROFILE="prod"
export DD_AWS_REGION="eu-west-1"
export DD_EKS_CLUSTER="prod-eks-cluster"
export DD_EKS_CLUSTER_ALIAS="prod"
      ;;
    stage)
      # Embedded config for stage
# Staging environment configuration

export DD_AWS_PROFILE="stage"
export DD_AWS_REGION="eu-west-1"
export DD_EKS_CLUSTER="stage-eks-cluster"
export DD_EKS_CLUSTER_ALIAS="stage"
      ;;
    *)
      error "Unknown environment: $env"
      echo "  Available: $(ls config/envs/ 2>/dev/null | sed \"s/\.sh$//\" | tr \"\\n\" \" \" 2>/dev/null || echo \"dev stage prod\")"
      exit 1
      ;;
  esac
}

# --- Override require_env for bundled version ---
require_env() {
  local env
  env=$(state_get_env)
  if [[ -z "$env" ]]; then
    error "No environment selected. Run: devops-desk env"
    exit 1
  fi
  load_env_config "$env"
  echo "$env"
}

# --- commands/auth.sh ---

cmd_auth() {
  local subcommand="${1:-login}"
  shift || true

  case "$subcommand" in
    login)  auth_login "$@" ;;
    status) auth_status ;;
    logout) auth_logout ;;
    *)      error "auth: unknown subcommand: $subcommand"
            echo "  Usage: devops-desk auth [login|status|logout]"
            exit 1 ;;
  esac
}

auth_login() {
  local env
  env=$(require_env)

  step "Authenticating to AWS SSO ($env)"
  info "Profile: ${DD_AWS_PROFILE}"

  aws sso login --profile "$DD_AWS_PROFILE"

  if aws sts get-caller-identity --profile "$DD_AWS_PROFILE" &>/dev/null 2>&1; then
    local account arn
    account=$(aws sts get-caller-identity --profile "$DD_AWS_PROFILE" --query Account --output text)
    arn=$(aws sts get-caller-identity --profile "$DD_AWS_PROFILE" --query Arn --output text)
    success "Authenticated"
    echo "  Account: $account"
    echo "  ARN:     $arn"
  else
    error "Authentication failed"
    exit 1
  fi
}

auth_status() {
  local env
  env=$(require_env)

  step "AWS Auth Status ($env)"

  if aws sts get-caller-identity --profile "$DD_AWS_PROFILE" &>/dev/null 2>&1; then
    local account arn
    account=$(aws sts get-caller-identity --profile "$DD_AWS_PROFILE" --query Account --output text)
    arn=$(aws sts get-caller-identity --profile "$DD_AWS_PROFILE" --query Arn --output text)
    success "Authenticated"
    echo "  Account: $account"
    echo "  ARN:     $arn"
  else
    warning "Not authenticated"
    echo "  Run: devops-desk auth login"
  fi
}

auth_logout() {
  local env
  env=$(require_env)

  step "Logging out of AWS SSO ($env)"
  aws sso logout --profile "$DD_AWS_PROFILE"
  success "Logged out"
}

# --- commands/batch.sh ---

cmd_batch() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    status)   batch_status "$@" ;;
    logs)     batch_logs "$@" ;;
    submit)   batch_submit "$@" ;;
    list)     batch_list "$@" ;;
    "")       batch_menu ;;
    *)
      error "batch: unknown subcommand: $subcommand"
      echo "  Usage: devops-desk batch [status|logs|submit|list]"
      exit 1 ;;
  esac
}

batch_menu() {
  local choice
  choice=$(printf '%s\n' \
    "list      List AWS Batch jobs in current environment" \
    "status    Check job status by Job ID" \
    "logs      Tail CloudWatch logs for a job" \
    "submit    Submit a new AWS Batch job" \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="AWS Batch > " \
      --header="AWS Batch Operations" \
      --height=12) || return 0

  [[ -z "$choice" ]] && return
  cmd_batch "$(echo "$choice" | awk '{print $1}')"
}

# ─── List Jobs ────────────────────────────────────────────────────────────────
batch_list() {
  require_env > /dev/null
  local job_queue="${1:-}"

  if [[ -z "$job_queue" ]]; then
    job_queue=$(aws batch describe-job-queues \
      --region "$DD_AWS_REGION" \
      --query 'jobQueues[*].jobQueueName' \
      --output text 2>/dev/null | tr ' ' '\n' \
      | fzf "${DD_FZF_OPTS[@]}" \
        --prompt="Job Queue > " \
        --header="Select Job Queue" \
        --height=10) || return 0
  fi

  [[ -z "$job_queue" ]] && return

  step "Listing AWS Batch jobs from queue: $job_queue"
  aws batch list_jobs \
    --job-queue "$job_queue" \
    --region "$DD_AWS_REGION" \
    --query 'jobSummaryList[*].[jobId,jobName,status,createdAt]' \
    --output table
}

# ─── Job Status ───────────────────────────────────────────────────────────────
batch_status() {
  require_env > /dev/null
  local job_id="${1:-}"

  if [[ -z "$job_id" ]]; then
    info "Enter Job ID (or paste from Batch console):"
    read -r job_id
  fi

  [[ -z "$job_id" ]] && { error "Job ID required"; return 1; }

  step "Fetching status for job: $job_id"
  aws batch describe_jobs \
    --jobs "$job_id" \
    --region "$DD_AWS_REGION" \
    --query 'jobs[0]' \
    --output json | jq '{
      jobId: .jobId,
      jobName: .jobName,
      status: .status,
      statusReason: .statusReason,
      createdAt: .createdAt,
      startedAt: .startedAt,
      stoppedAt: .stoppedAt,
      exitCode: .container.exitCode,
      reason: .container.reason
    }' 2>/dev/null || error "Job not found"
}

# ─── Tail CloudWatch Logs ─────────────────────────────────────────────────────
batch_logs() {
  require_env > /dev/null
  local job_id="${1:-}"

  if [[ -z "$job_id" ]]; then
    info "Enter Job ID:"
    read -r job_id
  fi

  [[ -z "$job_id" ]] && { error "Job ID required"; return 1; }

  # Get log group from job description
  local log_group log_stream
  log_group=$(aws batch describe_jobs \
    --jobs "$job_id" \
    --region "$DD_AWS_REGION" \
    --query 'jobs[0].container.logStreamName' \
    --output text 2>/dev/null)

  if [[ -z "$log_group" || "$log_group" == "None" ]]; then
    error "No log stream found for job $job_id"
    return 1
  fi

  # Extract log stream
  log_stream=$(basename "$log_group")
  log_group=$(dirname "$log_group" | sed 's|/aws/batch|/aws/batch|')

  step "Tailing logs: $log_stream"
  aws logs tail "$log_group" \
    --log-stream-name-prefix "$log_stream" \
    --region "$DD_AWS_REGION" \
    --follow 2>/dev/null || warning "CloudWatch logs: $log_group/$log_stream"
}

# ─── Submit Job ───────────────────────────────────────────────────────────────
batch_submit() {
  require_env > /dev/null
  
  local job_def job_queue job_count

  # Select job definition
  job_def=$(aws batch describe_job_definitions \
    --region "$DD_AWS_REGION" \
    --status ACTIVE \
    --query 'jobDefinitions[*].jobDefinitionArn' \
    --output text 2>/dev/null | tr ' ' '\n' | xargs -I {} basename {} \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Job Definition > " \
      --header="Select Job Definition") || return 0

  [[ -z "$job_def" ]] && { error "Job definition required"; return 1; }

  # Select job queue
  job_queue=$(aws batch describe_job_queues \
    --region "$DD_AWS_REGION" \
    --query 'jobQueues[*].jobQueueName' \
    --output text 2>/dev/null | tr ' ' '\n' \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Job Queue > " \
      --height=10) || return 0

  [[ -z "$job_queue" ]] && { error "Job queue required"; return 1; }

  # Optional: job count
  info "Number of jobs to submit (default: 1):"
  read -r job_count
  job_count="${job_count:-1}"

  if confirm "Submit $job_count job(s) with definition $job_def to queue $job_queue?"; then
    step "Submitting jobs…"
    for ((i=1; i<=job_count; i++)); do
      local resp
      resp=$(aws batch submit_job \
        --job-name "$(basename "$job_def")-$(date +%s)" \
        --job-queue "$job_queue" \
        --job-definition "$job_def" \
        --region "$DD_AWS_REGION" \
        --output json)
      
      local job_id
      job_id=$(echo "$resp" | jq -r '.jobId')
      success "Submitted job: $job_id"
    done
  fi
}

# --- commands/connect.sh ---

cmd_connect() {
  local env
  env=$(require_env)

  step "Configuring kubeconfig ($env)"
  info "Cluster: ${DD_EKS_CLUSTER}"
  info "Region:  ${DD_AWS_REGION}"
  info "Profile: ${DD_AWS_PROFILE}"

  if ! aws sts get-caller-identity --profile "$DD_AWS_PROFILE" &>/dev/null 2>&1; then
    error "Not authenticated to AWS. Run: devops-desk auth"
    exit 1
  fi

  local alias="${DD_EKS_CLUSTER_ALIAS:-$env}"

  aws eks update-kubeconfig \
    --profile  "$DD_AWS_PROFILE" \
    --region   "$DD_AWS_REGION" \
    --name     "$DD_EKS_CLUSTER" \
    --alias    "$alias"

  success "kubeconfig updated (context: $alias)"

  if kubectl cluster-info &>/dev/null 2>&1; then
    success "Cluster connection verified"
    kubectl cluster-info | head -2
  else
    warning "Could not verify cluster connection"
  fi
}

# --- commands/dashboard.sh ---
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

# --- commands/flux.sh ---

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

# --- commands/git.sh ---

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

# --- commands/github.sh ---

cmd_github() {
  check_dependency gh

  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    prs)    github_prs "$@" ;;
    runs)   github_runs "$@" ;;
    issues) github_issues "$@" ;;
    "")     github_menu ;;
    *)
      error "github: unknown subcommand: $subcommand"
      echo "  Usage: devops-desk github [prs|runs|issues]"
      exit 1 ;;
  esac
}

github_menu() {
  local choice
  choice=$(printf '%s\n' \
    "prs      Browse open pull requests" \
    "runs     Browse workflow runs" \
    "issues   Browse open issues" \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="GitHub > " \
      --header="GitHub Operations" \
      --height=10) || return 0

  [[ -z "$choice" ]] && return
  cmd_github "$(echo "$choice" | awk '{print $1}')"
}

github_prs() {
  gh pr list --json number,title,author,headRefName,updatedAt \
    --template '{{range .}}#{{.number}} {{.title}} [{{.author.login}}] {{.headRefName}}{{"\n"}}{{end}}' \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="PR > " \
    --header="CTRL-O: open browser  CTRL-C: checkout  CTRL-M: merge  CTRL-R: request review" \
    --preview='echo {1} | tr -d "#" | xargs gh pr view 2>/dev/null' \
    --preview-window='right:60%:wrap' \
    --bind='ctrl-o:execute(echo {1} | tr -d "#" | xargs gh pr view --web)' \
    --bind='ctrl-c:execute(echo {1} | tr -d "#" | xargs gh pr checkout)' \
    --bind='ctrl-m:execute(echo {1} | tr -d "#" | xargs gh pr merge --squash)'
}

github_runs() {
  gh run list --json databaseId,name,status,conclusion,createdAt \
    --template '{{range .}}{{.databaseId}} {{.name}} [{{.status}}] {{.conclusion}}{{"\n"}}{{end}}' \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Run > " \
    --header="CTRL-O: open browser  CTRL-L: view logs  CTRL-R: rerun" \
    --preview='gh run view {1} 2>/dev/null' \
    --preview-window='right:60%:wrap' \
    --bind='ctrl-o:execute(gh run view --web {1})' \
    --bind='ctrl-l:execute(gh run view --log {1} | less)' \
    --bind='ctrl-r:execute(gh run rerun {1})'
}

github_issues() {
  gh issue list --json number,title,author,state,labels \
    --template '{{range .}}#{{.number}} {{.title}} [{{.author.login}}]{{"\n"}}{{end}}' \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Issue > " \
    --header="CTRL-O: open browser  CTRL-A: assign to me  CTRL-C: create branch" \
    --preview='echo {1} | tr -d "#" | xargs gh issue view 2>/dev/null' \
    --preview-window='right:60%:wrap' \
    --bind='ctrl-o:execute(echo {1} | tr -d "#" | xargs gh issue view --web)'
}

# --- commands/helm.sh ---

cmd_helm() {
  check_dependency helm

  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    upgrade)  helm_upgrade "$@" ;;
    rollback) helm_rollback "$@" ;;
    "")       helm_menu ;;
    *)
      error "helm: unknown subcommand: $subcommand"
      echo "  Usage: devops-desk helm [upgrade|rollback]"
      exit 1 ;;
  esac
}

helm_menu() {
  local choice
  choice=$(printf '%s\n' \
    "upgrade    Interactive Helm upgrade" \
    "rollback   Rollback a Helm release to a previous revision" \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Helm > " \
      --header="Helm Operations" \
      --height=8) || return 0

  [[ -z "$choice" ]] && return
  cmd_helm "$(echo "$choice" | awk '{print $1}')"
}

helm_upgrade() {
  step "Helm Upgrade"

  local selected
  selected=$(helm list --all-namespaces --no-headers 2>/dev/null \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Release > " \
      --header="Select Helm release to upgrade" \
      --preview='helm get values {1} -n {2} 2>/dev/null') || return 0

  [[ -z "$selected" ]] && return

  local release ns chart
  release=$(echo "$selected" | awk '{print $1}')
  ns=$(echo "$selected" | awk '{print $2}')
  chart=$(echo "$selected" | awk '{print $9}')

  info "Release: $release  (namespace: $ns)"
  info "Chart:   $chart"

  echo -en "\n  Chart version (leave empty for latest): "
  read -r version

  local version_flag=""
  [[ -n "$version" ]] && version_flag="--version $version"

  if confirm "Upgrade $release → $chart $version?"; then
    # shellcheck disable=SC2086
    helm upgrade "$release" "$chart" -n "$ns" $version_flag --reuse-values
    success "Upgrade complete"
  fi
}

helm_rollback() {
  step "Helm Rollback"

  local selected
  selected=$(helm list --all-namespaces --no-headers 2>/dev/null \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Release > " \
      --header="Select release to rollback" \
      --preview='helm history {1} -n {2} 2>/dev/null') || return 0

  [[ -z "$selected" ]] && return

  local release ns
  release=$(echo "$selected" | awk '{print $1}')
  ns=$(echo "$selected" | awk '{print $2}')

  echo ""
  helm history "$release" -n "$ns"
  echo ""

  echo -en "  Rollback to revision (leave empty for previous): "
  read -r revision

  if confirm "Rollback $release?"; then
    if [[ -n "$revision" ]]; then
      helm rollback "$release" "$revision" -n "$ns"
    else
      helm rollback "$release" -n "$ns"
    fi
    success "Rollback complete"
  fi
}

# --- commands/nav.sh ---
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

# --- commands/oras.sh ---

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

# --- commands/pods.sh ---

cmd_pods() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    logs)    pods_logs "$@" ;;
    restart) pods_restart "$@" ;;
    exec)    pods_exec "$@" ;;
    forward) pods_forward "$@" ;;
    debug)   pods_debug "$@" ;;
    "")      pods_menu ;;
    *)
      error "pods: unknown subcommand: $subcommand"
      echo "  Usage: devops-desk pods [logs|restart|exec|forward|debug]"
      exit 1 ;;
  esac
}

pods_menu() {
  local choice
  choice=$(printf '%s\n' \
    "logs     Stream pod logs (supports multi-container selection)" \
    "restart  Restart a deployment" \
    "exec     Shell into a pod" \
    "forward  Port-forward to a pod or service" \
    "debug    Diagnose a failing pod (events, describe, logs)" \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Pods > " \
      --header="Pod Operations" \
      --height=12) || return 0

  [[ -z "$choice" ]] && return
  cmd_pods "$(echo "$choice" | awk '{print $1}')"
}

# ─── Helpers ──────────────────────────────────────────────────────────────────
_select_pod() {
  local prompt="${1:-Pod}"
  kubectl get pods --all-namespaces --no-headers \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,NODE:.spec.nodeName' \
    2>/dev/null \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="${prompt} > " \
    --preview='kubectl describe pod {2} -n {1} 2>/dev/null | head -50' \
    --preview-window='right:50%:wrap'
}

_select_deployment() {
  kubectl get deployments --all-namespaces --no-headers \
    -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas' \
    2>/dev/null \
  | fzf "${DD_FZF_OPTS[@]}" \
    --prompt="Deployment > " \
    --preview='kubectl describe deployment {2} -n {1} 2>/dev/null | head -40' \
    --preview-window='right:50%:wrap'
}

# ─── Logs ─────────────────────────────────────────────────────────────────────
pods_logs() {
  local selected
  selected=$(_select_pod "Logs") || return 0
  [[ -z "$selected" ]] && return

  local ns pod
  ns=$(echo "$selected" | awk '{print $1}')
  pod=$(echo "$selected" | awk '{print $2}')

  # Pick container if multiple
  local containers
  containers=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null)
  local container_flag=""

  if [[ $(echo "$containers" | wc -w) -gt 1 ]]; then
    local container
    container=$(echo "$containers" | tr ' ' '\n' \
      | fzf --prompt="Container > " --height=10 --border=rounded) || return 0
    [[ -n "$container" ]] && container_flag="-c $container"
  fi

  step "Logs: $pod (namespace: $ns)"
  # shellcheck disable=SC2086
  kubectl logs -f --tail=200 "$pod" -n "$ns" $container_flag
}

# ─── Restart ──────────────────────────────────────────────────────────────────
pods_restart() {
  local selected
  selected=$(_select_deployment) || return 0
  [[ -z "$selected" ]] && return

  local ns deploy
  ns=$(echo "$selected" | awk '{print $1}')
  deploy=$(echo "$selected" | awk '{print $2}')

  if confirm "Restart deployment/$deploy in namespace $ns?"; then
    kubectl rollout restart deployment/"$deploy" -n "$ns"
    info "Waiting for rollout…"
    kubectl rollout status deployment/"$deploy" -n "$ns"
    success "Rollout complete"
  fi
}

# ─── Exec ─────────────────────────────────────────────────────────────────────
pods_exec() {
  local selected
  selected=$(_select_pod "Exec into") || return 0
  [[ -z "$selected" ]] && return

  local ns pod
  ns=$(echo "$selected" | awk '{print $1}')
  pod=$(echo "$selected" | awk '{print $2}')

  # Try preferred shells in order
  local shell="sh"
  for sh in bash sh; do
    if kubectl exec "$pod" -n "$ns" -- which "$sh" &>/dev/null 2>&1; then
      shell="$sh"
      break
    fi
  done

  step "Exec: $pod (namespace: $ns)  [shell: $shell]"
  kubectl exec -it "$pod" -n "$ns" -- "$shell"
}

# ─── Port Forward ─────────────────────────────────────────────────────────────
pods_forward() {
  local resource_type
  resource_type=$(printf 'pod\nservice\n' \
    | fzf --prompt="Resource type > " --height=8 --border=rounded) || return 0
  [[ -z "$resource_type" ]] && return

  local ns name remote_port

  if [[ "$resource_type" == "pod" ]]; then
    local selected
    selected=$(_select_pod "Port forward") || return 0
    [[ -z "$selected" ]] && return
    ns=$(echo "$selected" | awk '{print $1}')
    name=$(echo "$selected" | awk '{print $2}')
  else
    local selected
    selected=$(kubectl get services --all-namespaces --no-headers \
      -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,PORT:.spec.ports[0].port' 2>/dev/null \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Service > " \
      --preview='kubectl describe svc {2} -n {1} 2>/dev/null | head -30') || return 0
    [[ -z "$selected" ]] && return
    ns=$(echo "$selected" | awk '{print $1}')
    name="svc/$(echo "$selected" | awk '{print $2}')"
    remote_port=$(echo "$selected" | awk '{print $3}')
  fi

  [[ -z "${remote_port:-}" ]] && { echo -en "\n  Remote port: "; read -r remote_port; }
  echo -en "  Local port (default: $remote_port): "
  read -r local_port
  [[ -z "$local_port" ]] && local_port="$remote_port"

  step "Port forwarding: localhost:$local_port → $name:$remote_port (namespace: $ns)"
  info "Press Ctrl+C to stop"
  kubectl port-forward "$name" -n "$ns" "${local_port}:${remote_port}"
}

# ─── Debug ────────────────────────────────────────────────────────────────────
pods_debug() {
  local selected
  selected=$(_select_pod "Debug") || return 0
  [[ -z "$selected" ]] && return

  local ns pod
  ns=$(echo "$selected" | awk '{print $1}')
  pod=$(echo "$selected" | awk '{print $2}')

  step "Debug: $pod (namespace: $ns)"

  echo -e "\n${BOLD}Pod Status${RESET}"
  kubectl get pod "$pod" -n "$ns" -o wide

  echo -e "\n${BOLD}Recent Events${RESET}"
  kubectl get events -n "$ns" \
    --field-selector "involvedObject.name=$pod" \
    --sort-by='.lastTimestamp' 2>/dev/null | tail -15

  echo -e "\n${BOLD}Conditions & Container Status${RESET}"
  kubectl describe pod "$pod" -n "$ns" \
    | grep -A5 -E "^Conditions:|^Containers:|^Events:" | head -50

  echo -e "\n${BOLD}Recent Logs (last 30 lines)${RESET}"
  kubectl logs "$pod" -n "$ns" --tail=30 --all-containers=true 2>/dev/null \
    || kubectl logs "$pod" -n "$ns" --tail=30 --previous 2>/dev/null \
    || echo "  (no logs available)"
}

# --- commands/release.sh ---

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

# --- commands/tfctl.sh ---

cmd_tfctl() {
  check_dependency tfctl

  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    reconcile) tfctl_reconcile "$@" ;;
    replan)    tfctl_replan "$@" ;;
    suspend)   tfctl_suspend "$@" ;;
    resume)    tfctl_resume "$@" ;;
    status)    tfctl_status ;;
    "")        tfctl_menu ;;
    *)
      error "tfctl: unknown subcommand: $subcommand"
      echo "  Usage: devops-desk tfctl [reconcile|replan|suspend|resume|status]"
      exit 1 ;;
  esac
}

tfctl_menu() {
  local choice
  choice=$(printf '%s\n' \
    "reconcile   Reconcile a terraform service-stack" \
    "replan      Replan a terraform service-stack" \
    "suspend     Suspend a terraform service-stack" \
    "resume      Resume a terraform service-stack" \
    "status      Show all terraform resources status" | \
    fzf --header="tfctl operations" --preview-window=hidden)

  # Extract subcommand
  subcommand="$(echo "$choice" | awk '{print $1}')"
  [[ -z "$subcommand" ]] && return 0
  
  cmd_tfctl "$subcommand"
}

tfctl_reconcile() {
  local stack="${1:-}"
  
  if [[ -z "$stack" ]]; then
    echo "Available terraform stacks:"
    tfctl list --output names 2>/dev/null || echo "  (run: tfctl list)"
    echo ""
    read -p "Enter stack name: " stack
  fi
  
  if [[ -z "$stack" ]]; then
    error "No stack specified"
    exit 1
  fi
  
  info "Reconciling terraform stack: $stack"
  tfctl reconcile "$stack"
  success "Reconciliation triggered"
}

tfctl_replan() {
  local stack="${1:-}"
  
  if [[ -z "$stack" ]]; then
    echo "Available terraform stacks:"
    tfctl list --output names 2>/dev/null || echo "  (run: tfctl list)"
    echo ""
    read -p "Enter stack name: " stack
  fi
  
  if [[ -z "$stack" ]]; then
    error "No stack specified"
    exit 1
  fi
  
  info "Replanning terraform stack: $stack"
  tfctl replan "$stack"
  success "Replan triggered"
}

tfctl_suspend() {
  local stack="${1:-}"
  
  if [[ -z "$stack" ]]; then
    echo "Available terraform stacks:"
    tfctl list --output names 2>/dev/null || echo "  (run: tfctl list)"
    echo ""
    read -p "Enter stack name: " stack
  fi
  
  if [[ -z "$stack" ]]; then
    error "No stack specified"
    exit 1
  fi
  
  info "Suspending terraform stack: $stack"
  tfctl suspend "$stack"
  success "Stack suspended"
}

tfctl_resume() {
  local stack="${1:-}"
  
  if [[ -z "$stack" ]]; then
    echo "Available terraform stacks:"
    tfctl list --output names 2>/dev/null || echo "  (run: tfctl list)"
    echo ""
    read -p "Enter stack name: " stack
  fi
  
  if [[ -z "$stack" ]]; then
    error "No stack specified"
    exit 1
  fi
  
  info "Resuming terraform stack: $stack"
  tfctl resume "$stack"
  success "Stack resumed"
}

tfctl_status() {
  info "Terraform service-stacks status"
  kubectl --context="${KUBE_CONTEXT}" get terraform -n flux-system \
    -o wide \
    --no-headers=false 2>/dev/null || {
    error "Failed to fetch terraform resources. Make sure you're connected to the cluster."
    exit 1
  }
}

check_dependency() {
  if ! command -v "$1" &>/dev/null; then
    error "$1 not installed"
    echo "  Install via: brew install $1"
    echo "  Or see: https://docs.opentofu.org/docs/intro/install/"
    exit 1
  fi
}

# --- commands/trace.sh ---

cmd_trace() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    test)     trace_test "$@" ;;
    status)   trace_status "$@" ;;
    export)   trace_export "$@" ;;
    config)   trace_config "$@" ;;
    "")       trace_menu ;;
    *)
      error "trace: unknown subcommand: $subcommand"
      echo "  Usage: devops-desk trace [test|status|export|config]"
      exit 1 ;;
  esac
}

trace_menu() {
  local choice
  choice=$(printf '%s\n' \
    "config    Show current OTEL/Dash0 configuration" \
    "test      Send test spans to Dash0" \
    "status    Check Dash0 connectivity" \
    "export    Generate OTEL env var exports" \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Tracing > " \
      --header="OpenTelemetry / Dash0 Operations" \
      --height=12) || return 0

  [[ -z "$choice" ]] && return
  cmd_trace "$(echo "$choice" | awk '{print $1}')"
}

# ─── OTEL Configuration ───────────────────────────────────────────────────────
trace_config() {
  local service="${1:-bi-advanced-analytics}"

  step "OTEL Configuration for service: $service"
  
  [[ -z "$OTEL_EXPORTER_OTLP_ENDPOINT" ]] && warning "OTEL_EXPORTER_OTLP_ENDPOINT not set"
  [[ -z "$OTEL_EXPORTER_OTLP_HEADERS" ]] && warning "OTEL_EXPORTER_OTLP_HEADERS not set"
  [[ -z "$OTEL_SERVICE_NAME" ]] && warning "OTEL_SERVICE_NAME not set"

  cat <<EOF

$(color_bold "Environment Variables:")
  OTEL_EXPORTER_OTLP_ENDPOINT:     ${OTEL_EXPORTER_OTLP_ENDPOINT:-not set}
  OTEL_EXPORTER_OTLP_HEADERS:      ${OTEL_EXPORTER_OTLP_HEADERS:+SET}
  OTEL_EXPORTER_OTLP_PROTOCOL:     ${OTEL_EXPORTER_OTLP_PROTOCOL:-grpc}
  OTEL_TRACES_EXPORTER:            ${OTEL_TRACES_EXPORTER:-otlp}
  OTEL_SERVICE_NAME:               ${OTEL_SERVICE_NAME:-not set}

$(color_bold "Dash0 Integration:")
  Endpoint: ingress.eu-west-1.aws.dash0.com:4317
  Protocol: gRPC (OTLP)
  Dataset:  dev (from headers)

EOF
}

# ─── Test Span Submission ─────────────────────────────────────────────────────
trace_test() {
  require_env > /dev/null
  local service="${1:-bi-advanced-analytics}"

  step "Sending test spans to Dash0 for service: $service"

  # Create inline test script
  local test_script
  test_script=$(cat <<'SCRIPT'
import sys
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
import os
import time

try:
    endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "")
    headers = os.environ.get("OTEL_EXPORTER_OTLP_HEADERS", "")
    service_name = os.environ.get("OTEL_SERVICE_NAME", "test-service")
    
    if not endpoint or not headers:
        print("❌ OTEL_EXPORTER_OTLP_ENDPOINT or OTEL_EXPORTER_OTLP_HEADERS not set")
        sys.exit(1)
    
    # Create exporter
    exporter = OTLPSpanExporter(
        endpoint=endpoint,
        headers=dict(pair.split("=") for pair in headers.split(","))
    )
    
    # Create provider
    provider = TracerProvider()
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)
    
    # Create tracer and test span
    tracer = trace.get_tracer(__name__)
    with tracer.start_as_current_span("devops_desk_test_span") as span:
        span.set_attribute("test.timestamp", str(time.time()))
        span.set_attribute("service.name", service_name)
    
    # Flush
    provider.force_flush()
    print("✅ Test span sent successfully!")
    print(f"   Service: {service_name}")
    print(f"   Endpoint: {endpoint}")
    
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
SCRIPT
)

  echo "$test_script" | python3 - || error "Failed to send test span"
}

# ─── Dash0 Connectivity Status ────────────────────────────────────────────────
trace_status() {
  step "Checking Dash0 connectivity"

  # Simple connectivity test via curl
  local endpoint="ingress.eu-west-1.aws.dash0.com:4317"
  
  if nc -z "${endpoint%:*}" "${endpoint##*:}" 2>/dev/null; then
    success "Dash0 endpoint reachable: $endpoint"
  else
    warning "Dash0 endpoint check inconclusive (gRPC ports may not respond to TCP checks)"
  fi

  info "Full connectivity test requires actual span submission (use 'devops-desk trace test')"
}

# ─── Export OTEL Variables ────────────────────────────────────────────────────
trace_export() {
  local auth_token="${1:-}"
  local dataset="${2:-dev}"
  local service="${3:-bi-advanced-analytics}"

  if [[ -z "$auth_token" ]]; then
    info "Enter Dash0 Bearer token:"
    read -rs auth_token
    echo ""
  fi

  [[ -z "$auth_token" ]] && { error "Auth token required"; return 1; }

  step "Generating OTEL environment variables"

  cat <<EOF

# ─── OTEL Environment Variables for Dash0 ─────────────────────────────────

export OTEL_EXPORTER_OTLP_ENDPOINT="ingress.eu-west-1.aws.dash0.com:4317"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer ${auth_token},Dash0-Dataset=${dataset}"
export OTEL_SERVICE_NAME="${service}"
export OTEL_TRACES_EXPORTER="otlp"
export OTEL_EXPORTER_OTLP_PROTOCOL="grpc"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=$(state_get_env),host.name=\$(hostname)"

# ─── Load with:
# source <(devops-desk trace export)

EOF
}

# --- Main script ---

# Resolve symlink so installation via /usr/local/bin works
SOURCE="${BASH_SOURCE[0]}"

while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done


# devops-desk root
export DEVOPS_DESK_ROOT


# ─── FZF defaults (available to all subcommands) ──────────────────────────────
export FZF_DEFAULT_OPTS=""
DD_FZF_OPTS=(
  --height=80%
  --layout=reverse
  --border=rounded
  --info=inline
  --color="header:bold,prompt:cyan,pointer:green,hl:yellow,hl+:yellow"
  --bind="ctrl-/:toggle-preview"
  --bind="ctrl-f:preview-page-down"
  --bind="ctrl-b:preview-page-up"
)
export DD_FZF_OPTS

usage() {
  local env
  env=$(state_get_env)
  [[ -z "$env" ]] && env="$(color_yellow "not set")"

  cat <<EOF

$(color_bold "devops-desk") — Terminal DevOps Control Center

$(color_bold "ENVIRONMENT")
  env                    Select or show current environment
  auth [login|status]    AWS SSO authentication
  connect                Configure kubeconfig for EKS
  status                 Show current env + cluster info

$(color_bold "NAVIGATION")
  nav                    Interactive FZF resource navigator
  nav pods               Navigate pods (logs/exec/restart/forward)
  nav deployments        Navigate deployments
  nav services           Navigate services + port-forward
  nav namespaces         Switch namespace
  nav helm               Browse Helm releases
  nav flux               Browse Flux resources
  nav nodes              View cluster nodes

$(color_bold "OPERATIONS")
  dashboard              DevOps dashboard (pods/flux/helm overview)
  flux [reconcile|status|images|suspend|resume]
  helm [upgrade|rollback]
  pods [logs|restart|exec|forward|debug]
  tfctl [reconcile|replan|suspend|resume|status]

$(color_bold "INTEGRATIONS")
  k9s                    Launch k9s with devops-desk plugins
  github [prs|runs|issues]

$(color_dim "Current environment:") $env

EOF
}

cmd_env() {
  if [[ $# -eq 0 ]]; then
    local envs
      local envs
      envs="dev stage prod"  # Hardcoded for bundled version
    local selected
    selected=$(echo "$envs" | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Select environment > " \
      --header="devops-desk — choose environment" \
      --height=12) || return 0

    [[ -z "$selected" ]] && return
    state_set_env "$selected"
    success "Environment set to: $selected"
  else
    local env="$1"
    if [[ ! "$env" =~ ^(dev|stage|prod)$ ]]; then
      error "Unknown environment: $env"
      echo "  Available: $(ls "$DEVOPS_DESK_ROOT/config/envs/" | sed 's/\.sh$//' | tr '\n' ' ')"
      exit 1
    fi
    state_set_env "$env"
    success "Environment set to: $env"
  fi
}

cmd_status() {
  local env
  env=$(state_get_env)

  echo ""
  echo -e "$(color_bold "devops-desk status")"
  echo -e "$(color_dim "  ──────────────────────────────────────────")"

  if [[ -z "$env" ]]; then
    echo -e "  $(color_bold "Environment:") $(color_yellow "not set")  — run: devops-desk env"
    echo ""
    return
  fi

  load_env_config "$env"

  printf "  %-15s %s\n" "$(color_bold "Environment:")" "$env"
  printf "  %-15s %s\n" "$(color_bold "AWS Profile:")" "${DD_AWS_PROFILE:-not set}"
  printf "  %-15s %s\n" "$(color_bold "AWS Region:")"  "${DD_AWS_REGION:-not set}"
  printf "  %-15s %s\n" "$(color_bold "EKS Cluster:")" "${DD_EKS_CLUSTER:-not set}"

  if aws sts get-caller-identity --profile "${DD_AWS_PROFILE:-}" &>/dev/null 2>&1; then
    printf "  %-15s %s\n" "$(color_bold "AWS Auth:")" "$(color_green "authenticated")"
  else
    printf "  %-15s %s\n" "$(color_bold "AWS Auth:")" "$(color_yellow "not authenticated")  — run: devops-desk auth"
  fi

  local ctx
  ctx=$(kubectl config current-context 2>/dev/null || echo "none")
  printf "  %-15s %s\n" "$(color_bold "k8s Context:")" "$ctx"

  echo ""
}

launch_k9s() {
  check_dependency k9s
  local k9s_config_dir="${K9S_CONFIG_DIR:-$HOME/.config/k9s}"
  mkdir -p "$k9s_config_dir"

  if [[ -f "$DEVOPS_DESK_ROOT/k9s/plugins.yaml" ]]; then
    cp "$DEVOPS_DESK_ROOT/k9s/plugins.yaml" "$k9s_config_dir/plugins.yaml"
  fi
  if [[ -f "$DEVOPS_DESK_ROOT/k9s/skin.yaml" ]]; then
    mkdir -p "$k9s_config_dir/skins"
    cp "$DEVOPS_DESK_ROOT/k9s/skin.yaml" "$k9s_config_dir/skins/devops-desk.yaml"
  fi

  k9s "$@"
}

main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    env)       cmd_env "$@" ;;
    auth)      source "$DEVOPS_DESK_ROOT/commands/auth.sh";      cmd_auth "$@" ;;
    connect)   source "$DEVOPS_DESK_ROOT/commands/connect.sh";   cmd_connect "$@" ;;
    nav)       source "$DEVOPS_DESK_ROOT/commands/nav.sh";       cmd_nav "$@" ;;
    dashboard) source "$DEVOPS_DESK_ROOT/commands/dashboard.sh"; cmd_dashboard "$@" ;;
    flux)      source "$DEVOPS_DESK_ROOT/commands/flux.sh";      cmd_flux "$@" ;;
    helm)      source "$DEVOPS_DESK_ROOT/commands/helm.sh";      cmd_helm "$@" ;;
    pods)      source "$DEVOPS_DESK_ROOT/commands/pods.sh";      cmd_pods "$@" ;;
    tfctl)     source "$DEVOPS_DESK_ROOT/commands/tfctl.sh";     cmd_tfctl "$@" ;;
    k9s)       launch_k9s "$@" ;;
    github)    source "$DEVOPS_DESK_ROOT/commands/github.sh";    cmd_github "$@" ;;
    status)    cmd_status ;;
    help|--help|-h) usage ;;
    *)
      error "Unknown command: $cmd"
      echo "  Run 'devops-desk help' for usage."
      exit 1
      ;;
  esac
}

main "$@"
