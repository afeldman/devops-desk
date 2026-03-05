#!/usr/bin/env bash

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
