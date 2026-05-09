#!/bin/bash
set -eo pipefail

# Run from the repo root regardless of where this script is invoked from.
cd "$(dirname "$0")/.."

echo "🚀 Starting zero to hero deployment..."

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
SKIP_SMOKE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap-state-key)
      BOOTSTRAP_STATE_KEY="$2"; shift 2 ;;
    --skip-helm)
      SKIP_HELM=1; shift ;;
    --skip-smoke)
      SKIP_SMOKE=1; shift ;;
    -h|--help)
      echo "Usage: $0 [-- <interview-name>]";
      echo "       [--bootstrap-state-key <s3/key/path.tfstate>]";
      echo "       [--skip-helm] [--skip-smoke]";
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

TFVARS=""
if [ ! -z "$SSH_CIDR_BLOCK" ]; then
    # Create a temporary file for the list
    TEMP_FILE=$(mktemp)
    echo "ssh_cidr_blocks = [\"$SSH_CIDR_BLOCK\"]" > "$TEMP_FILE"
    TFVARS="$TFVARS -var-file=$TEMP_FILE"
    # Clean up temp file after terraform runs
    trap 'rm -f "$TEMP_FILE"' EXIT
fi

set -u

# Initialize and apply Terraform
echo "📦 Creating infrastructure with Terraform..."
cd terraform/bootstrap
# Allow overriding only the bootstrap backend key via CLI
BOOTSTRAP_INIT_ARGS="$TERRAFORM_INIT_ARGS"
if [ -n "$BOOTSTRAP_STATE_KEY" ]; then
  BOOTSTRAP_INIT_ARGS="$BOOTSTRAP_INIT_ARGS --backend-config=key=$BOOTSTRAP_STATE_KEY"
fi
# -reconfigure: each interview name uses a different state key, so the cached
# backend config from a previous run will mismatch. Reset it.
terraform init -reconfigure $BOOTSTRAP_INIT_ARGS
terraform apply -auto-approve -var "interview_name=${INTERVIEW_NAME}"

# Surface which ECR repository is being used
ECR_REPO_URL=$(terraform output -raw ecr_repository_url)
echo "📦 Using ECR repository: ${ECR_REPO_URL} (name: ${INTERVIEW_NAME})"

echo "✨ Bootstrap Infrastructure created successfully!"

# Initialize the EKS cluster
echo "📦 Initializing EKS cluster..."
cd ../aws
# Init with the bucket we just created, but the standard key from that module
terraform init $TERRAFORM_INIT_ARGS
terraform apply -var "interviewee_name=${INTERVIEW_NAME}" -auto-approve

echo "✨ EKS cluster initialized successfully!"

# Install in-cluster addons via Helm (LBC, autoscaler, external-dns, metrics-server)
if [ $SKIP_HELM -eq 0 ]; then
  echo "📦 Installing Helm addons..."
  cd ../aws-helm
  terraform init
  terraform apply -auto-approve
  echo "✨ Helm addons installed!"
else
  echo "ℹ️  --skip-helm set; not applying terraform/aws-helm."
fi

# Verify the cluster is healthy end-to-end. smoke-test.sh re-anchors to the
# repo root itself, so it doesn't matter what cwd we hand it.
if [ $SKIP_SMOKE -eq 0 ]; then
  echo "🔬 Running smoke tests..."
  SMOKE_ARGS=()
  if [ $SKIP_HELM -eq 1 ]; then SMOKE_ARGS+=(--no-helm); fi
  # Bash 3.2 (macOS default) treats `${arr[@]}` on an empty array as unbound
  # under `set -u`. The `+"${arr[@]}"` idiom expands to the array if set,
  # else to nothing.
  if "$(dirname "$0")/smoke-test.sh" ${SMOKE_ARGS[@]+"${SMOKE_ARGS[@]}"}; then
    echo "✨ Smoke tests passed!"
  else
    echo "❌ Smoke tests failed - the cluster came up but is not fully healthy. See output above." >&2
    exit 1
  fi
else
  echo "ℹ️  --skip-smoke set; not running scripts/smoke-test.sh."
fi

# The app-deploy branch below expects cwd to be terraform/aws, where the
# previous `terraform output -raw ecr_repository_url` etc. live.
cd "$(dirname "$0")/.."/terraform/aws

# Build/push app image and deploy (only if ./app exists two levels up)
if [ -d "../../app" ]; then
  echo "🐳 Building and pushing Docker image..."
  cd ../../app
  make build push
  IMAGE_ID=$(make output-image-id)

  echo "🔍 Image ID: $IMAGE_ID"

  cd ../terraform
  terraform init $TERRAFORM_INIT_ARGS
  terraform apply -var "docker_image=$IMAGE_ID" -var "ecr_repository_url=$ECR_REPO_URL" $TFVARS -auto-approve

  timeout=300  # 5 minutes in seconds
  start_time=$(date +%s)
  end_time=$((start_time + timeout))

  current_time=$(date +%s)
  while ! curl -s $(terraform output -raw instance_ip) > /dev/null; do
      current_time=$(date +%s)
      if [ $current_time -ge $end_time ]; then
          echo "Timeout reached after 5 minutes. Application may not be ready."
          break
      fi
      echo "Waiting for application to start... $(date)"
      sleep 10
  done

  EXIT_CODE=0
  if [ $current_time -ge $end_time ]; then
      echo "Timeout reached after 5 minutes. Application may not be ready."
      EXIT_CODE=1
  else
      echo "🎉 Deployment complete!"
  fi

  echo "🔑 To SSH into the instance, run:"
  echo "    $(terraform output -raw ssh_key_commands)"

  echo
  echo "🔍 You can access the application at: http://$(terraform output -raw instance_ip)"

  exit $EXIT_CODE
else
  echo "ℹ️ No ./app found. Skipping image build and app deployment."
  echo "   ECR repository is ready: ${ECR_REPO_URL}"
  exit 0
fi