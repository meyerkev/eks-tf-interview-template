#!/usr/bin/env bash
# Smoke-test the EKS cluster + addon stack produced by:
#
#   terraform/aws       -- control plane, nodes, access entries, interviewee IAM
#   terraform/aws-helm  -- aws-load-balancer-controller, cluster-autoscaler,
#                          external-dns, metrics-server
#
# Re-runnable. Reads the interviewee IAM keypair from `terraform output` so
# the operator (whoever has access to the tfstate) must run it. Verifies both
# the cluster-admin path AND the interviewee path so you know access entries
# actually wired the interviewee user up to AmazonEKSClusterAdminPolicy.
#
# Usage (from repo root):
#   ./scripts/smoke-test.sh
#   AWS_REGION=us-east-1 CLUSTER_NAME=my-cluster ./scripts/smoke-test.sh
#   ./scripts/smoke-test.sh --no-helm     # skip the aws-helm tier
#
# Exit code = number of failed checks (0 if all pass).

set -uo pipefail

# Run from the repo root regardless of where this script is invoked from.
cd "$(dirname "$0")/.."
REPO_ROOT=$PWD

REGION=${AWS_REGION:-us-east-2}
CLUSTER_NAME=${CLUSTER_NAME:-eks-cluster}
ADMIN_CTX=${ADMIN_KUBE_CONTEXT:-smoke-admin}
INTV_CTX=${INTERVIEWEE_KUBE_CONTEXT:-smoke-interviewee}
SKIP_HELM=0

for arg in "$@"; do
  case "$arg" in
    --no-helm) SKIP_HELM=1 ;;
    -h|--help)
      sed -n '/^# Usage/,/^# Exit/p' "$0" | sed 's/^# //;s/^#//'
      exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# ---- result tracking ------------------------------------------------------

PASS=0
FAIL=0
FAILED=()

ok()      { PASS=$((PASS+1)); printf "  \033[32m✓\033[0m %s\n" "$1"; }
fail()    { FAIL=$((FAIL+1)); FAILED+=("$1"); printf "  \033[31m✗\033[0m %s\n" "$1"; [ -n "${2:-}" ] && printf "      %s\n" "$2"; }
section() { printf "\n\033[1m== %s ==\033[0m\n" "$1"; }

# expect <name> <cmd...>: pass if the command's exit code is 0.
expect() {
  local name=$1; shift
  local out
  if out=$("$@" 2>&1); then ok "$name"
  else fail "$name" "$(echo "$out" | head -1)"
  fi
}

# expect_nonempty <name> <cmd...>: pass if the command exits 0 AND emits text.
expect_nonempty() {
  local name=$1; shift
  local out
  if ! out=$("$@" 2>&1); then fail "$name" "$(echo "$out" | head -1)"; return; fi
  if [ -z "$out" ]; then fail "$name" "(empty output)"
  else ok "$name"
  fi
}

# Run a command as the interviewee IAM user (clean env, no ambient creds).
as_interviewee() {
  env -u AWS_PROFILE -u AWS_DEFAULT_PROFILE -u AWS_SESSION_TOKEN \
      AWS_ACCESS_KEY_ID="$INTERVIEWEE_AK" \
      AWS_SECRET_ACCESS_KEY="$INTERVIEWEE_SK" \
      "$@"
}

# ---- prerequisites --------------------------------------------------------

section "Prerequisites"
for bin in aws kubectl terraform jq; do
  if command -v "$bin" >/dev/null 2>&1; then ok "$bin installed"
  else fail "$bin installed"
  fi
done
if [ "$SKIP_HELM" -eq 0 ]; then
  if command -v helm >/dev/null 2>&1; then ok "helm installed"
  else fail "helm installed"
  fi
fi

# ---- terraform outputs (from terraform/aws) -------------------------------

section "Terraform outputs (terraform/aws)"
cd "$REPO_ROOT/terraform/aws"
INTERVIEWEE_AK=$(terraform output -raw interviewee_access_key 2>/dev/null || echo "")
INTERVIEWEE_SK=$(terraform output -raw interviewee_secret_key 2>/dev/null || echo "")
TF_CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
cd "$REPO_ROOT"

if [ -n "$INTERVIEWEE_AK" ] && [ -n "$INTERVIEWEE_SK" ]; then
  ok "interviewee credentials available"
else
  fail "interviewee credentials available" "did terraform apply -var interviewee_name=... finish?"
fi
if [ "$TF_CLUSTER_NAME" = "$CLUSTER_NAME" ]; then
  ok "cluster_name output matches \$CLUSTER_NAME ($CLUSTER_NAME)"
else
  fail "cluster_name output matches \$CLUSTER_NAME" "tf=$TF_CLUSTER_NAME env=$CLUSTER_NAME"
fi

# ---- AWS-side cluster checks ----------------------------------------------

section "EKS control plane (admin)"
CLUSTER_STATUS=$(aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" --query 'cluster.status' --output text 2>/dev/null || echo "MISSING")
if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then ok "EKS cluster ACTIVE"
else fail "EKS cluster ACTIVE" "status=$CLUSTER_STATUS"
fi

for addon in vpc-cni kube-proxy coredns; do
  STATUS=$(aws eks describe-addon --region "$REGION" --cluster-name "$CLUSTER_NAME" --addon-name "$addon" --query 'addon.status' --output text 2>/dev/null || echo "MISSING")
  if [ "$STATUS" = "ACTIVE" ]; then ok "EKS addon $addon ACTIVE"
  else fail "EKS addon $addon ACTIVE" "status=$STATUS"
  fi
done

NG=$(aws eks list-nodegroups --region "$REGION" --cluster-name "$CLUSTER_NAME" --query 'nodegroups[0]' --output text 2>/dev/null || echo "")
if [ -n "$NG" ] && [ "$NG" != "None" ]; then
  STATUS=$(aws eks describe-nodegroup --region "$REGION" --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NG" --query 'nodegroup.status' --output text 2>/dev/null || echo "MISSING")
  if [ "$STATUS" = "ACTIVE" ]; then ok "node group $NG ACTIVE"
  else fail "node group $NG ACTIVE" "status=$STATUS"
  fi
else
  fail "node group present"
fi

# ---- kubectl as admin -----------------------------------------------------

section "Kubernetes (admin context)"
if aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" --alias "$ADMIN_CTX" >/dev/null 2>&1; then
  ok "update-kubeconfig (admin)"
else
  fail "update-kubeconfig (admin)"
fi

expect "all nodes Ready (≤2min)" \
  kubectl --context="$ADMIN_CTX" wait --for=condition=ready nodes --all --timeout=2m

# Helper: pass if "<ready>/<desired>" is "N/N" with N>0. Avoids the awk
# `exit 0` -> END `exit 1` foot-gun by doing the comparison in bash.
check_ready_over_desired() {
  local label=$1 jsonpath=$2
  shift 2
  local out ready desired
  out=$(kubectl --context="$ADMIN_CTX" -n kube-system "$@" -o jsonpath="$jsonpath" 2>/dev/null) || { fail "$label"; return; }
  ready=${out%/*}
  desired=${out#*/}
  if [ -n "$ready" ] && [ -n "$desired" ] && [ "$ready" = "$desired" ] && [ "$ready" -gt 0 ] 2>/dev/null; then
    ok "$label"
  else
    fail "$label" "got: $out"
  fi
}

for ds in aws-node kube-proxy; do
  check_ready_over_desired "kube-system/$ds DaemonSet healthy" \
    '{.status.numberReady}/{.status.desiredNumberScheduled}' \
    get ds "$ds"
done

check_ready_over_desired "kube-system/coredns Deployment healthy" \
  '{.status.readyReplicas}/{.spec.replicas}' \
  get deploy coredns

# ---- helm releases (terraform/aws-helm) -----------------------------------

if [ "$SKIP_HELM" -eq 0 ]; then
  section "Helm releases (terraform/aws-helm)"
  HELM_JSON=$(helm --kube-context "$ADMIN_CTX" list -A -o json 2>/dev/null || echo "[]")
  for spec in \
      "aws-load-balancer-controller:aws-load-balancer-controller" \
      "external-dns:external-dns" \
      "cluster-autoscaler:cluster-autoscaler" \
      "metrics-server:kube-system"; do
    release="${spec%%:*}"
    ns="${spec##*:}"
    if echo "$HELM_JSON" | jq -e --arg r "$release" --arg n "$ns" \
        '.[] | select(.name==$r and .namespace==$n and .status=="deployed")' >/dev/null 2>&1; then
      ok "release $release in $ns deployed"
    else
      fail "release $release in $ns deployed"
    fi
  done

  expect_nonempty "metrics-server functional (kubectl top nodes returns data)" \
    kubectl --context="$ADMIN_CTX" top nodes --no-headers
fi

# ---- interviewee path -----------------------------------------------------

if [ -n "$INTERVIEWEE_AK" ]; then
  section "Interviewee credentials + access entry"

  ARN=$(as_interviewee aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo "")
  if echo "$ARN" | grep -q ":user/"; then ok "STS identity is an IAM user ($ARN)"
  else fail "STS identity is an IAM user" "got: $ARN"
  fi

  expect "interviewee aws eks describe-cluster" \
    as_interviewee aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" --query 'cluster.status' --output text

  if as_interviewee aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" --alias "$INTV_CTX" >/dev/null 2>&1; then
    ok "interviewee update-kubeconfig"
  else
    fail "interviewee update-kubeconfig"
  fi

  expect_nonempty "interviewee kubectl get nodes (RBAC via access entry)" \
    as_interviewee kubectl --context="$INTV_CTX" get nodes --no-headers

  expect_nonempty "interviewee kubectl get secrets -n kube-system (admin scope)" \
    as_interviewee kubectl --context="$INTV_CTX" get secrets -n kube-system --no-headers
fi

# ---- summary --------------------------------------------------------------

section "Summary"
printf "  %d passed, %d failed\n" "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf "\n  Failed checks:\n"
  for f in "${FAILED[@]}"; do printf "    - %s\n" "$f"; done
fi
exit "$FAIL"
