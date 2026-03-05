#!/usr/bin/env bash
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
