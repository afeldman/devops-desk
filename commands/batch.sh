#!/usr/bin/env bash

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
