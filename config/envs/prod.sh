#!/usr/bin/env bash
# Production environment configuration
# All destructive operations prompt for confirmation when this env is active.

export DD_AWS_PROFILE="prod"
export DD_AWS_REGION="eu-west-1"
export DD_EKS_CLUSTER="prod-eks-cluster"
export DD_EKS_CLUSTER_ALIAS="prod"
