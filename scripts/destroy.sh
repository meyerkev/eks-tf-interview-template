#!/bin/bash
set -eo pipefail

# Run from the repo root regardless of where this script is invoked from.
cd "$(dirname "$0")/.."

echo "🚀 Starting infrastructure destruction..."

# Optional: choose interview/ECR repo name and bootstrap backend key
INTERVIEW_NAME="interview-repo"

# Get the first argument after -- if it exists. macOS ships bash 3.2 which
# doesn't accept `${!((expr))}` indirect expansion, so use a named temp var.
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "--" ]] && [[ $((i+1)) -le $# ]]; then
    next_idx=$((i+1))
    INTERVIEW_NAME="${!next_idx}"
    break
  fi
done

BOOTSTRAP_STATE_KEY="${INTERVIEW_NAME}-bootstrap-ecr.tfstate"
SKIP_HELM=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap-state-key)
      BOOTSTRAP_STATE_KEY="$2"; shift 2 ;;
    --skip-helm)
      SKIP_HELM=1; shift ;;
    -h|--help)
      echo "Usage: $0 [-- <interview-name>]";
      echo "       [--bootstrap-state-key <s3/key/path.tfstate>]";
      echo "       [--skip-helm]";
      echo "Example: $0 -- acme-takehome --bootstrap-state-key interviews/acme/bootstrap-ecr.tfstate"; exit 0 ;;
    --) shift; shift; continue ;;  # Skip the -- and the interview name; `continue` avoids the trailing `shift` blowing up under `set -e` when no args remain
    *)
      if [[ "$1" != "--bootstrap-state-key" ]]; then
        echo "Unknown argument: $1" >&2; exit 1
      fi ;;
  esac
  shift
done

TERRAFORM_INIT_ARGS=''
if [ ! -z "$TF_STATE_BUCKET" ]; then
    TERRAFORM_INIT_ARGS="--backend-config=bucket=$TF_STATE_BUCKET"
fi
if [ ! -z "$TF_STATE_KEY" ]; then
    TERRAFORM_INIT_ARGS="$TERRAFORM_INIT_ARGS --backend-config=key=$TF_STATE_KEY"
fi
if [ ! -z "$TF_STATE_REGION" ]; then
    TERRAFORM_INIT_ARGS="$TERRAFORM_INIT_ARGS --backend-config=region=$TF_STATE_REGION"
fi

set -u

# First, destroy aws-helm (Helm releases + IRSA roles). Doing this before
# terraform/aws ensures the IAM roles aren't left orphaned and that the
# helm uninstall hooks have a working cluster + API server to talk to.
if [ $SKIP_HELM -eq 0 ] && [ -d terraform/aws-helm ]; then
  if [ -f terraform/aws-helm/test-interview-helm.tfstate ] || [ -d terraform/aws-helm/.terraform ]; then
    echo "🗑️ Destroying Helm addons..."
    cd terraform/aws-helm
    terraform init
    terraform destroy -auto-approve
    cd ../..
    echo "✨ Helm addons destroyed!"
  else
    echo "ℹ️  No terraform/aws-helm state found; skipping helm destroy."
  fi
fi

# Then destroy the EKS cluster
echo "🗑️ Destroying EKS cluster..."
cd terraform/aws
terraform init $TERRAFORM_INIT_ARGS
terraform destroy -var "interviewee_name=${INTERVIEW_NAME}" -auto-approve

echo "✨ EKS cluster destroyed successfully!"

# Finally, destroy the bootstrap infrastructure
echo "🗑️ Destroying bootstrap infrastructure..."
cd ../bootstrap
# Allow overriding only the bootstrap backend key via CLI
BOOTSTRAP_INIT_ARGS="$TERRAFORM_INIT_ARGS"
if [ -n "$BOOTSTRAP_STATE_KEY" ]; then
  BOOTSTRAP_INIT_ARGS="$BOOTSTRAP_INIT_ARGS --backend-config=key=$BOOTSTRAP_STATE_KEY"
fi
# -reconfigure: each interview name uses a different state key, so the cached
# backend config from a previous run will mismatch. Reset it.
terraform init -reconfigure $BOOTSTRAP_INIT_ARGS
terraform destroy -auto-approve -var "interview_name=${INTERVIEW_NAME}"

echo "✨ Bootstrap infrastructure destroyed successfully!"
echo "🎉 All infrastructure has been cleaned up!"
