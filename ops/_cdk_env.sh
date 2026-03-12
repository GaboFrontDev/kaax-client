#!/usr/bin/env bash
# Shared CDK environment setup for kaax-client ops scripts.
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/_cdk_env.sh"

CLIENT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CDK_DIR="$CLIENT_ROOT/infra/cdk"
CORE_CDK="$CLIENT_ROOT/core/infra/cdk"
CDK_VENV_DIR="$CDK_DIR/.venv"

_ensure_cdk_venv() {
  if [[ ! -d "$CDK_VENV_DIR" ]] || ! grep -Fq "$CDK_VENV_DIR" "$CDK_VENV_DIR/pyvenv.cfg" 2>/dev/null; then
    echo "Creating CDK venv..." >&2
    python3 -m venv "$CDK_VENV_DIR"
    echo "Installing CDK dependencies (this may take a minute)..." >&2
    "$CDK_VENV_DIR/bin/pip" install -r "$CORE_CDK/requirements.txt"
    echo "CDK venv ready." >&2
  fi
}

_cdk_run() {
  _ensure_cdk_venv
  source "$CDK_VENV_DIR/bin/activate"
  cd "$CDK_DIR"
  unset SECRET_NAME SECRET_ARN SECRET_KEYS

  local extra=()
  [[ -n "${CDK_SECRET_NAME:-}" ]] && extra+=(-c "secret_name=${CDK_SECRET_NAME}")
  [[ -n "${CDK_SECRET_ARN:-}"   ]] && extra+=(-c "secret_arn=${CDK_SECRET_ARN}")
  [[ -n "${CDK_SECRET_KEYS:-}"  ]] && extra+=(-c "secret_keys=${CDK_SECRET_KEYS}")

  echo "Running: cdk $* (env=${ENV_NAME:-dev} agent=${AGENT_NAME:-default})" >&2
  cdk "$@" \
    -c config="config/environments.json" \
    -c env="${ENV_NAME:-dev}" \
    -c agent="${AGENT_NAME:-default}" \
    -c dockerfile_dir="$CLIENT_ROOT" \
    ${extra[@]+"${extra[@]}"}
}
