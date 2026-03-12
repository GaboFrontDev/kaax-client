#!/usr/bin/env bash
set -euo pipefail
ENV_NAME="${1:-dev}"
AGENT_NAME="${2:-default}"
source "$(dirname "${BASH_SOURCE[0]}")/_cdk_env.sh"
_cdk_run diff
