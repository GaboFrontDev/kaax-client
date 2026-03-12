#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_cdk_env.sh"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not found." >&2; exit 1
fi
if ! command -v cdk >/dev/null 2>&1; then
  echo "cdk CLI not found. Install with: npm i -g aws-cdk" >&2; exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

_ensure_cdk_venv
source "$CDK_VENV_DIR/bin/activate"
cd "$CDK_DIR"

cdk bootstrap "aws://${ACCOUNT_ID}/${REGION}"
