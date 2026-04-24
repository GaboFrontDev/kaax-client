#!/usr/bin/env bash
set -euo pipefail

REGISTRY="registry.digitalocean.com/lw-api"
IMAGE="$REGISTRY/kaax-client"
APP_NAME="kaax-client"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC_TEMPLATE="$ROOT_DIR/.do/app.yaml"
TMP_SPEC="$(mktemp "${TMPDIR:-/tmp}/do-app-spec.XXXXXX.yaml")"
KEEP_DEPLOY_TAGS="${KEEP_DEPLOY_TAGS:-3}"

compute_deploy_tag() {
  local commit_short dirty_hash

  if ! commit_short="$(git -C "$ROOT_DIR" rev-parse --short=12 HEAD 2>/dev/null)"; then
    date -u +"deploy-%Y%m%d%H%M%S"
    return
  fi

  if [ -z "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]; then
    printf 'deploy-%s\n' "$commit_short"
    return
  fi

  dirty_hash="$(
    ROOT_DIR="$ROOT_DIR" python3 - <<'PY'
import hashlib
import os
from pathlib import Path

root = Path(os.environ["ROOT_DIR"])
targets = [
    "Dockerfile",
    "main.py",
    "client.py",
    "config.yaml",
    "pyproject.toml",
    "uv.lock",
    "states",
    "tools",
    "prompts",
    "core",
]
skip_dirs = {
    ".git",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".venv",
    "__pycache__",
}

digest = hashlib.sha256()

for target_name in targets:
    target = root / target_name
    if not target.exists():
        continue
    if target.is_file():
        digest.update(str(target.relative_to(root)).encode())
        digest.update(b"\0")
        digest.update(target.read_bytes())
        continue

    for path in sorted(
        p for p in target.rglob("*")
        if p.is_file() and not any(part in skip_dirs for part in p.parts)
    ):
        digest.update(str(path.relative_to(root)).encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())

print(digest.hexdigest()[:12])
PY
  )"

  printf 'deploy-%s-dirty-%s\n' "$commit_short" "$dirty_hash"
}

DEPLOY_TAG="$(compute_deploy_tag)"

cleanup() {
  rm -f "$TMP_SPEC"
}

trap cleanup EXIT

cleanup_old_deploy_tags() {
  local tags_json tags_to_delete

  if [ "${KEEP_DEPLOY_TAGS}" -lt 1 ]; then
    return
  fi

  if ! tags_json="$(doctl registry repository list-tags kaax-client --registry lw-api --output json 2>/dev/null)"; then
    echo "==> Skipping registry cleanup (tags unavailable)"
    return
  fi

  tags_to_delete="$(
    KEEP_DEPLOY_TAGS="$KEEP_DEPLOY_TAGS" CURRENT_DEPLOY_TAG="$DEPLOY_TAG" TAGS_JSON="$tags_json" \
    python3 - <<'PY'
import json
import os

keep = int(os.environ["KEEP_DEPLOY_TAGS"])
current = os.environ["CURRENT_DEPLOY_TAG"]
tags = json.loads(os.environ["TAGS_JSON"])

deploy_tags = [
    tag for tag in tags
    if str(tag.get("tag", "")).startswith("deploy-")
]
deploy_tags.sort(key=lambda item: item.get("updated_at", ""), reverse=True)

keep_tags: list[str] = []
for item in deploy_tags:
    tag_name = item["tag"]
    if tag_name == current and tag_name not in keep_tags:
        keep_tags.append(tag_name)
for item in deploy_tags:
    tag_name = item["tag"]
    if tag_name in keep_tags:
        continue
    keep_tags.append(tag_name)
    if len(keep_tags) >= keep:
        break

for item in deploy_tags:
    tag_name = item["tag"]
    if tag_name not in keep_tags:
        print(tag_name)
PY
  )"

  if [ -z "$tags_to_delete" ]; then
    return
  fi

  echo "==> Cleaning old deploy tags..."
  # shellcheck disable=SC2086
  doctl registry repository delete-tag kaax-client $tags_to_delete --registry lw-api --force
}

maybe_start_registry_gc() {
  doctl registry garbage-collection start lw-api \
    --include-untagged-manifests \
    --force \
    >/dev/null 2>&1 || true
}

render_spec() {
  local app_id="${1:-}"
  local current_json=""

  if [ -n "$app_id" ]; then
    current_json="$(doctl apps get "$app_id" --output json)"
  fi

  CURRENT_APP_JSON="$current_json" DEPLOY_TAG="$DEPLOY_TAG" \
  uv run --directory "$ROOT_DIR" python3 - "$SPEC_TEMPLATE" "$TMP_SPEC" <<'PY'
import json
import os
import sys
from pathlib import Path

import yaml


def load_dotenv(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.exists():
        return data
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in raw_line:
            continue
        key, value = raw_line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if value and len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        data[key] = value
    return data


spec_template = Path(sys.argv[1])
spec_output = Path(sys.argv[2])

spec = yaml.safe_load(spec_template.read_text())
deploy_tag = os.environ["DEPLOY_TAG"]
for service in spec.get("services", []):
    image = service.get("image")
    if isinstance(image, dict):
        image["tag"] = deploy_tag

local_env: dict[str, str] = {}
for env_path in (spec_template.parent.parent / ".env", spec_template.parent.parent / ".env.local"):
    local_env.update(load_dotenv(env_path))

current_app_json = os.environ.get("CURRENT_APP_JSON", "").strip()
current_envs: dict[str, dict] = {}
if current_app_json:
    current_app = json.loads(current_app_json)[0]
    for service in current_app.get("spec", {}).get("services", []):
        if service.get("name") != "api":
            continue
        for env in service.get("envs", []):
            current_envs[env["key"]] = env

missing: list[str] = []
for service in spec.get("services", []):
    for env in service.get("envs", []):
        env.setdefault("scope", "RUN_AND_BUILD_TIME")
        if env.get("type") != "SECRET":
            continue

        key = env["key"]
        local_value = local_env.get(key, "")
        if local_value:
            env["value"] = local_value
            continue

        current_value = current_envs.get(key, {}).get("value")
        if current_value:
            env["value"] = current_value
            continue

        missing.append(key)

if missing:
    raise SystemExit(f"Missing values for secrets: {', '.join(sorted(missing))}")

spec_output.write_text(yaml.safe_dump(spec, sort_keys=False))
PY
}

echo "==> Logging in to DO Registry..."
doctl registry login

echo "==> Building image..."
echo "    Using image tag: $DEPLOY_TAG"
docker build --platform linux/amd64 -t "$IMAGE:$DEPLOY_TAG" -t "$IMAGE:latest" .

echo "==> Pushing image..."
docker push "$IMAGE:$DEPLOY_TAG"
docker push "$IMAGE:latest"

echo "==> Deploying to DO App Platform..."
APP_ID=$(doctl apps list --no-header --format ID,Spec.Name | grep "$APP_NAME" | awk '{print $1}')

if [ -z "$APP_ID" ]; then
  render_spec
  echo "    Creating app (first deploy)..."
  doctl apps create --spec "$TMP_SPEC"
else
  render_spec "$APP_ID"
  echo "    Updating app $APP_ID..."
  doctl apps update "$APP_ID" --spec "$TMP_SPEC"
fi

cleanup_old_deploy_tags
maybe_start_registry_gc

echo "==> Done. Ver estado: doctl apps list"
