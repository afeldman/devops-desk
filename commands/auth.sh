#!/usr/bin/env bash

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
