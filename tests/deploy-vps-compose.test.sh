#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORKFLOW_PATH="$ROOT_DIR/.github/workflows/deploy-vps-compose.yml"
DOC_PATH="$ROOT_DIR/docs/deploy-vps-compose/README.md"
EXAMPLE_PATH="$ROOT_DIR/docs/deploy-vps-compose/release.example.yml"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
[[ -f "$WORKFLOW_PATH" ]] || { echo "Missing workflow: $WORKFLOW_PATH" >&2; exit 1; }
EXTRACTED_SCRIPT="$TMP_DIR/deploy.sh"
ruby - "$WORKFLOW_PATH" "$EXTRACTED_SCRIPT" <<'RUBY'
require "yaml"
workflow = YAML.safe_load(File.read(ARGV.fetch(0)), [], [], true)
step = workflow.fetch("jobs").fetch("deploy").fetch("steps").find { |candidate| candidate["id"] == "deploy" }
abort "Missing jobs.deploy step with id: deploy" unless step
File.write(ARGV.fetch(1), step.fetch("run"))
RUBY
chmod +x "$EXTRACTED_SCRIPT"
BIN_DIR="$TMP_DIR/bin"
mkdir -p "$BIN_DIR"
cat >"$BIN_DIR/docker" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'docker %s\n' "$*" >>"$COMMAND_LOG"
if [[ "${1:-}" == login ]]; then
  IFS= read -r token || true
  [[ "$token" == "$EXPECTED_GHCR_TOKEN" ]]
  printf 'ghcr-token-via-stdin\n' >>"$COMMAND_LOG"
  printf '%s\n' "${DOCKER_CONFIG:-}" >"$FAKE_DOCKER_CONFIG_PATH"
  exit 0
fi
if [[ "$*" == *"compose version"* || "$*" == *"config --quiet"* || "$*" == *" pull"* ]]; then exit 0; fi
if [[ "$*" == *"config --images"* ]]; then printf '%s\n' "$FAKE_COMPOSE_IMAGES"; exit 0; fi
if [[ "$*" == *" up "* ]]; then [[ ${FAKE_UP_RESULT:-healthy} == healthy ]] && exit 0 || exit 1; fi
if [[ "$*" == *"ps --all"* && "$*" == *"--format"* ]]; then printf '%s\n' "$FAKE_HEALTH_ROWS"; exit 0; fi
if [[ "$*" == *"ps --all"* ]]; then printf '%s\n' "$FAKE_HEALTH_ROWS"; exit 0; fi
echo "Unexpected fake docker command: $*" >&2
exit 1
STUB
chmod +x "$BIN_DIR/docker"
cat >"$BIN_DIR/mv" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${FAKE_MV_FAILURE:-no} == yes ]]; then echo "Simulated atomic rename failure." >&2; exit 1; fi
exec /bin/mv "$@"
STUB
chmod +x "$BIN_DIR/mv"
cat >"$BIN_DIR/ssh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'ssh %s\n' "$*" >>"$COMMAND_LOG"
bash -c "${!#}"
STUB
chmod +x "$BIN_DIR/ssh"
cat >"$BIN_DIR/scp" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'scp %s\n' "$*" >>"$COMMAND_LOG"
destination=${!#}
remote_path=${destination#*:}
mkdir -p "$(dirname -- "$remote_path")"
cp compose.prod.yaml "$remote_path"
STUB
chmod +x "$BIN_DIR/scp"
BASE_DIR="$TMP_DIR/caller"
REMOTE_DIR="$TMP_DIR/remote/stack"
mkdir -p "$BASE_DIR"
write_valid_compose() {
  cat >"$BASE_DIR/compose.prod.yaml" <<'YAML'
services:
  app:
    image: ghcr.io/example/app:${IMAGE_TAG:?IMAGE_TAG is required}
    healthcheck:
      test: ["CMD", "true"]
  database:
    image: postgres:16
    healthcheck:
      test: ["CMD", "true"]
YAML
}
write_mixed_unversioned_compose() {
  cat >"$BASE_DIR/compose.prod.yaml" <<'YAML'
services:
  app:
    image: ghcr.io/example/app:${IMAGE_TAG:?IMAGE_TAG is required}
  worker:
    image: ghcr.io/example/app:latest
YAML
}
write_hard_coded_current_tag_compose() {
  cat >"$BASE_DIR/compose.prod.yaml" <<'YAML'
services:
  app:
    image: ghcr.io/example/app:${IMAGE_TAG:?IMAGE_TAG is required}
  worker:
    image: ghcr.io/example/app:v1.2.3
YAML
}
run_deploy() {
  local output_file=$1
  shift
  rm -rf "$REMOTE_DIR"
  mkdir -p "$REMOTE_DIR"
  : >"$TMP_DIR/commands.log"
  : >"$TMP_DIR/docker-config-path"
  (
    cd "$BASE_DIR"
    env PATH="$BIN_DIR:$PATH" HOME="$TMP_DIR/home" COMMAND_LOG="$TMP_DIR/commands.log" EXPECTED_GHCR_TOKEN="test-token" FAKE_DOCKER_CONFIG_PATH="$TMP_DIR/docker-config-path" FAKE_COMPOSE_IMAGES=$'ghcr.io/example/app:v1.2.3\npostgres:16' FAKE_HEALTH_ROWS="app|running|healthy" INPUT_IMAGE_TAG="v1.2.3" INPUT_APPLICATION_IMAGE_PREFIX="ghcr.io/example/app" INPUT_DEPLOY_PATH="$REMOTE_DIR" INPUT_HEALTH_TIMEOUT_SECONDS="300" DEPLOY_HOST="vps.example.com" DEPLOY_PORT="22" DEPLOY_USER="deploy" DEPLOY_KEY="test-private-key" DEPLOY_KNOWN_HOSTS="vps.example.com ssh-ed25519 test-key" GHCR_USERNAME="example" GHCR_TOKEN="test-token" GITHUB_REPOSITORY="example/app" GITHUB_RUN_ID="123" GITHUB_RUN_ATTEMPT="1" GITHUB_STEP_SUMMARY="$TMP_DIR/summary.md" "$@" bash "$EXTRACTED_SCRIPT"
  ) >"$output_file" 2>&1
}
assert_failure() {
  local name=$1 expected=$2 output_file
  shift 2
  output_file="$TMP_DIR/$name.log"
  if run_deploy "$output_file" "$@"; then echo "Expected failure: $name" >&2; exit 1; fi
  grep -F "$expected" "$output_file" >/dev/null
}
rm -f "$BASE_DIR/compose.prod.yaml"
assert_failure missing-compose "compose.prod.yaml is required at repository root."
: >"$BASE_DIR/compose.prod.yaml"
assert_failure empty-compose "compose.prod.yaml must be non-empty."
cat >"$BASE_DIR/compose.prod.yaml" <<'YAML'
services:
  app:
    image: ghcr.io/example/app:latest
YAML
assert_failure missing-image-tag "Every application image must use required IMAGE_TAG interpolation."
write_valid_compose
assert_failure invalid-tag "Invalid image tag" INPUT_IMAGE_TAG="release/v1"
assert_failure invalid-application-image-prefix "application-image-prefix contains unsupported characters." INPUT_APPLICATION_IMAGE_PREFIX="ghcr.io/example/app;whoami"
assert_failure invalid-path "Invalid deployment path" INPUT_DEPLOY_PATH="/srv/../root"
assert_failure invalid-timeout "health-timeout-seconds must be an integer between 1 and 3600." INPUT_HEALTH_TIMEOUT_SECONDS="0"
assert_failure invalid-port "DEPLOY_PORT must be an integer between 1 and 65535." DEPLOY_PORT="invalid"
assert_failure invalid-host "DEPLOY_HOST contains unsupported characters." DEPLOY_HOST="vps.example.com;whoami"
assert_failure invalid-user "DEPLOY_USER contains unsupported characters." DEPLOY_USER="deploy user"
write_mixed_unversioned_compose
assert_failure mixed-unversioned-application "Every application image must use required IMAGE_TAG interpolation."
write_hard_coded_current_tag_compose
assert_failure hard-coded-current-tag "Every application image must use required IMAGE_TAG interpolation."
write_valid_compose
run_deploy "$TMP_DIR/success.log"
grep -F "ghcr-token-via-stdin" "$TMP_DIR/commands.log" >/dev/null
grep -F "StrictHostKeyChecking=yes" "$TMP_DIR/commands.log" >/dev/null
grep -F -- "--wait-timeout 300" "$TMP_DIR/commands.log" >/dev/null
if grep -F "test-token" "$TMP_DIR/commands.log" >/dev/null; then echo "GHCR token leaked into command arguments." >&2; exit 1; fi
grep -F "app|running|healthy" "$TMP_DIR/summary.md" >/dev/null
summary_fence=$(printf '\140\140\140text')
grep -Fx "$summary_fence" "$TMP_DIR/summary.md" >/dev/null
[[ -f "$REMOTE_DIR/compose.prod.yaml" ]]
docker_config_path=$(cat "$TMP_DIR/docker-config-path")
[[ -n "$docker_config_path" && ! -d "$docker_config_path" ]]
line_number() { grep -n -m 1 -F -- "$1" "$TMP_DIR/commands.log" | cut -d: -f1; }
preflight_line=$(line_number "command -v docker")
scp_line=$(line_number "scp ")
validation_line=$(line_number "config --images")
login_line=$(line_number "docker login")
deploy_line=$(line_number "--wait-timeout 300")
(( preflight_line < scp_line && scp_line < validation_line && validation_line < login_line && login_line < deploy_line ))
write_valid_compose
assert_failure mixed-resolved-application "Application images matching application-image-prefix must use the requested image tag." FAKE_COMPOSE_IMAGES=$'ghcr.io/example/app:v1.2.3\nghcr.io/example/app:latest\npostgres:16'
assert_failure no-matching-application "No resolved Compose image matches application-image-prefix." FAKE_COMPOSE_IMAGES="postgres:16"
assert_failure unhealthy-container "app|running|unhealthy" FAKE_HEALTH_ROWS="app|running|unhealthy"
assert_failure missing-healthcheck "app|running|" FAKE_HEALTH_ROWS="app|running|"
write_valid_compose
assert_failure rename-failure "Simulated atomic rename failure." FAKE_MV_FAILURE=yes
if grep -E '^docker .* up --detach' "$TMP_DIR/commands.log" >/dev/null; then echo "Compose up ran after the atomic rename failed." >&2; exit 1; fi
if grep -F "StrictHostKeyChecking=no" "$WORKFLOW_PATH" >/dev/null; then echo "Workflow disables SSH host verification." >&2; exit 1; fi
grep -F -- "--password-stdin" "$WORKFLOW_PATH" >/dev/null
grep -F 'docker_config=\$(mktemp -d)' "$WORKFLOW_PATH" >/dev/null
grep -F 'rm -rf \"\$docker_config\"' "$WORKFLOW_PATH" >/dev/null
grep -F "running\\|healthy" "$WORKFLOW_PATH" >/dev/null
grep -F "application-image-prefix" "$WORKFLOW_PATH" >/dev/null
grep -F "INPUT_APPLICATION_IMAGE_PREFIX" "$WORKFLOW_PATH" >/dev/null
grep -F "Every application image must use required IMAGE_TAG interpolation." "$WORKFLOW_PATH" >/dev/null
grep -F "No resolved Compose image matches application-image-prefix." "$WORKFLOW_PATH" >/dev/null
grep -F "Application images matching application-image-prefix must use the requested image tag." "$WORKFLOW_PATH" >/dev/null
grep -F 'group: deploy-vps-compose-${{ github.repository }}' "$WORKFLOW_PATH" >/dev/null
[[ -f "$DOC_PATH" && -f "$EXAMPLE_PATH" ]]
grep -F "deploy-vps-compose" "$ROOT_DIR/README.md" >/dev/null
grep -F "needs: build" "$EXAMPLE_PATH" >/dev/null
grep -F 'needs.build.outputs.image_tag' "$EXAMPLE_PATH" >/dev/null
grep -F 'needs.build.outputs.image_name' "$EXAMPLE_PATH" >/dev/null
printf 'ok\n'
