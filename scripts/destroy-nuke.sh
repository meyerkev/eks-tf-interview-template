#!/usr/bin/env bash
set -euo pipefail

# Safe wrapper to run aws-nuke with the repo's aws-nuke.yaml
# Defaults to DRY RUN. Pass --yes to actually delete (adds --no-dry-run --force).
#
# Known issue with aws-nuke v3.64.x:
# It can get stuck in an infinite "waiting for removal" retry loop on a
# specific S3Object version even when no Object Lock / Legal Hold / MFA
# Delete is in play and a manual `aws s3api delete-object --version-id <id>`
# succeeds instantly. If you see "1 waiting" pinned for several minutes
# with no progress, kill aws-nuke and bulk-delete versions out-of-band:
#
#   aws s3api list-object-versions --bucket <bucket> --output json \
#     | jq -r '(.Versions // []) + (.DeleteMarkers // []) | .[]
#              | "\(.Key)\t\(.VersionId)"' \
#     | while IFS=$'\t' read -r k v; do
#         aws s3api delete-object --bucket <bucket> --key "$k" --version-id "$v"
#       done

# Run from the repo root so aws-nuke.yaml resolves correctly.
cd "$(dirname "$0")/.."

PROFILE="meyerkev-toybox"
CONFIG="aws-nuke.yaml"
DRY_RUN=1

usage() {
  cat <<EOF
Usage: $0 [--yes] [--profile <name>] [--config <path>] [--] [extra aws-nuke args]

Runs aws-nuke against this repo's config using the 'meyerkev-toybox' profile by default.

Options:
  --yes                 Perform deletion (adds --no-dry-run --force). Default is dry-run.
  --profile <name>      AWS named profile to use (default: ${PROFILE}).
  --config <path>       Path to aws-nuke config (default: ${CONFIG}).
  -h, --help            Show this help and exit.

Examples:
  Dry run (default):   $0
  Real delete:         $0 --yes
  Alternate profile:   $0 --profile my-profile
  Pass-through flags:  $0 -- --target "EC2*"
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      DRY_RUN=0; shift ;;
    --profile)
      PROFILE="$2"; shift 2 ;;
    --config)
      CONFIG="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; break ;;
    *)
      # Unrecognized here; let aws-nuke parse via pass-through
      break ;;
  esac
done

if ! command -v aws-nuke >/dev/null 2>&1; then
  echo "Error: aws-nuke is not installed or not in PATH." >&2
  echo "Install from: https://github.com/rebuy-de/aws-nuke/releases" >&2
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "Error: config file not found: $CONFIG" >&2
  exit 1
fi

echo "⚠️  aws-nuke is extremely destructive. Use disposable accounts only."
echo "Config: $CONFIG"
echo "Profile: $PROFILE"

# aws-nuke v3.x (ekristen fork) requires the `run` subcommand and uses
# `--no-alias-check` when the target account has no IAM alias set.
cmd=(aws-nuke run --config "$CONFIG" --profile "$PROFILE" --no-alias-check)

if [[ $DRY_RUN -eq 1 ]]; then
  echo "Running in DRY RUN mode (no resources will be deleted)."
else
  echo "Running with DELETION ENABLED (--no-dry-run --force)."
  cmd+=(--no-dry-run --force)
fi

# Append any additional args for aws-nuke after '--'
if [[ $# -gt 0 ]]; then
  cmd+=("$@")
fi

echo "+ ${cmd[*]}"
"${cmd[@]}"

