#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORKFLOW_PATH="$ROOT_DIR/.github/workflows/deploy-vps-compose.yml"
DOC_PATH="$ROOT_DIR/docs/deploy-vps-compose/README.md"
EXAMPLE_PATH="$ROOT_DIR/docs/deploy-vps-compose/release.example.yml"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
[[ -f "$WORKFLOW_PATH" ]] || {
  echo "Missing workflow: $WORKFLOW_PATH" >&2
  exit 1
}
EXTRACTED_SCRIPT="$TMP_DIR/deploy.sh"
ruby - "$WORKFLOW_PATH" "$EXTRACTED_SCRIPT" <<'RUBY'
require "yaml"
workflow = YAML.safe_load(File.read(ARGV.fetch(0)), [], [], true)
step = workflow.fetch("jobs").fetch("deploy").fetch("steps").find do |candidate|
  candidate["id"] == "deploy"
end
abort "Missing jobs.deploy step with id: deploy" unless step
File.write(ARGV.fetch(1), step.fetch("run"))
RUBY
chmod +x "$EXTRACTED_SCRIPT"
BIN_DIR="$TMP_DIR/bin"
mkdir -p "$BIN_DIR"
cat >"$BIN_DIR/ssh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'ssh %s\n' "$*" >>"$COMMAND_LOG"
if [[ "$*" == *"docker login"* ]]; then
  token=""
  IFS= read -r token || true
  [[ "$token" == "$EXPECTED_GHCR_TOKEN" ]]
  printf 'ghcr-token-via-stdin\n' >>"$COMMAND_LOG"
fi
if [[ "$*" == *"config --images"* ]]; then
  case ${SSH_CONFIG_RESULT:-resolved} in
    missing-tag)
      echo "Resolved Compose images do not use the requested image tag." >&2
      exit 1
      ;;
    mixed-application-latest)
      [[ "$*" == *"matching_images="* ]] \
        && [[ "$*" == *"awk -v prefix="* ]] || exit 0
      printf '%s\\n' "ghcr.io/example/app:v1.2.3" "ghcr.io/example/app:latest" "postgres:16"
      echo "Application images matching application-image-prefix must use the requested image tag." >&2
      exit 1
      ;;
    no-matching-application)
      [[ "$*" == *"matching_images="* ]] \
        && [[ "$*" == *"awk -v prefix="* ]] || exit 0
      printf '%s\\n' "postgres:16"
      echo "No resolved Compose image matches application-image-prefix." >&2
      exit 1
      ;;
    resolved)
      printf '%s\\n' "ghcr.io/example/app:v1.2.3" "postgres:16"
      ;;
  esac
fi
if [[ "$*" == *"--wait-timeout"* ]]; then
  case ${SSH_DEPLOY_RESULT:-healthy} in
    unhealthy)
      printf 'HEALTH|app|running|unhealthy\n'
      exit 1
      ;;
    missing-healthcheck)
      printf 'HEALTH|app|running|\n'
      exit 1
      ;;
    healthy)
      printf 'HEALTH|app|running|healthy\n'
      ;;
  esac
fi
STUB
chmod +x "$BIN_DIR/ssh"
cat >"$BIN_DIR/scp" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'scp %s\n' "$*" >>"$COMMAND_LOG"
STUB
chmod +x "$BIN_DIR/scp"
BASE_DIR="$TMP_DIR/caller"
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
run_deploy() {
  local output_file=$1
  shift
  (
    cd "$BASE_DIR"
    env \
      PATH="$BIN_DIR:$PATH" \
      HOME="$TMP_DIR/home" \
      COMMAND_LOG="$TMP_DIR/commands.log" \
      EXPECTED_GHCR_TOKEN="test-token" \
      INPUT_IMAGE_TAG="v1.2.3" \
      INPUT_APPLICATION_IMAGE_PREFIX="ghcr.io/example/app" \
      INPUT_DEPLOY_PATH="/srv/compose/example" \
      INPUT_HEALTH_TIMEOUT_SECONDS="300" \
      DEPLOY_HOST="vps.example.com" \
      DEPLOY_PORT="22" \
      DEPLOY_USER="deploy" \
      DEPLOY_KEY="test-private-key" \
      DEPLOY_KNOWN_HOSTS="vps.example.com ssh-ed25519 test-key" \
      GHCR_USERNAME="example" \
      GHCR_TOKEN="test-token" \
      GITHUB_REPOSITORY="example/app" \
      GITHUB_RUN_ID="123" \
      GITHUB_RUN_ATTEMPT="1" \
      GITHUB_STEP_SUMMARY="$TMP_DIR/summary.md" \
      "$@" \
      bash "$EXTRACTED_SCRIPT"
  ) >"$output_file" 2>&1
}
assert_failure() {
  local name=$1
  local expected=$2
  shift 2
  local output_file="$TMP_DIR/$name.log"
  if run_deploy "$output_file" "$@"; then
    echo "Expected failure: $name" >&2
    exit 1
  fi
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
assert_failure missing-image-tag "compose.prod.yaml must use IMAGE_TAG in an image reference."
write_valid_compose
assert_failure invalid-tag "Invalid image tag" INPUT_IMAGE_TAG="release/v1"
assert_failure invalid-application-image-prefix "application-image-prefix contains unsupported characters." INPUT_APPLICATION_IMAGE_PREFIX="ghcr.io/example/app;whoami"
assert_failure invalid-path "Invalid deployment path" INPUT_DEPLOY_PATH="/srv/../root"
assert_failure invalid-timeout "health-timeout-seconds must be an integer between 1 and 3600." INPUT_HEALTH_TIMEOUT_SECONDS="0"
assert_failure invalid-port "DEPLOY_PORT must be an integer between 1 and 65535." DEPLOY_PORT="invalid"
assert_failure invalid-host "DEPLOY_HOST contains unsupported characters." DEPLOY_HOST="vps.example.com;whoami"
assert_failure invalid-user "DEPLOY_USER contains unsupported characters." DEPLOY_USER="deploy user"
: >"$TMP_DIR/commands.log"
run_deploy "$TMP_DIR/success.log"
grep -F "ghcr-token-via-stdin" "$TMP_DIR/commands.log" >/dev/null
grep -F "StrictHostKeyChecking=yes" "$TMP_DIR/commands.log" >/dev/null
grep -F "docker compose" "$TMP_DIR/commands.log" >/dev/null
grep -F -- "--wait-timeout 300" "$TMP_DIR/commands.log" >/dev/null
grep -F "config --images" "$TMP_DIR/commands.log" >/dev/null
if grep -F "test-token" "$TMP_DIR/commands.log" >/dev/null; then
  echo "GHCR token leaked into command arguments." >&2
  exit 1
fi
grep -F "app|running|healthy" "$TMP_DIR/summary.md" >/dev/null
line_number() {
  grep -n -m 1 -F -- "$1" "$TMP_DIR/commands.log" | cut -d: -f1
}
preflight_line=$(line_number "command -v docker")
scp_line=$(line_number "scp ")
validation_line=$(line_number "config --images")
login_line=$(line_number "docker login")
deploy_line=$(line_number "--wait-timeout 300")
(( preflight_line < scp_line ))
(( scp_line < validation_line ))
(( validation_line < login_line ))
(( login_line < deploy_line ))
write_valid_compose
assert_failure unresolved-image-tag "Resolved Compose images do not use the requested image tag." SSH_CONFIG_RESULT="missing-tag"
assert_failure mixed-application-image "Application images matching application-image-prefix must use the requested image tag." SSH_CONFIG_RESULT="mixed-application-latest"
assert_failure no-matching-application-image "No resolved Compose image matches application-image-prefix." SSH_CONFIG_RESULT="no-matching-application"
assert_failure unhealthy-container "app|running|unhealthy" SSH_DEPLOY_RESULT="unhealthy"
assert_failure missing-healthcheck "app|running|" SSH_DEPLOY_RESULT="missing-healthcheck"
if grep -F "StrictHostKeyChecking=no" "$WORKFLOW_PATH" >/dev/null; then
  echo "Workflow disables SSH host verification." >&2
  exit 1
fi
grep -F -- "--password-stdin" "$WORKFLOW_PATH" >/dev/null
grep -F 'docker_config=\$(mktemp -d)' "$WORKFLOW_PATH" >/dev/null
grep -F 'rm -rf \"\$docker_config\"' "$WORKFLOW_PATH" >/dev/null
grep -F "running\\|healthy" "$WORKFLOW_PATH" >/dev/null
grep -F "application-image-prefix" "$WORKFLOW_PATH" >/dev/null
grep -F "INPUT_APPLICATION_IMAGE_PREFIX" "$WORKFLOW_PATH" >/dev/null
grep -F "No resolved Compose image matches application-image-prefix." "$WORKFLOW_PATH" >/dev/null
grep -F "Application images matching application-image-prefix must use the requested image tag." "$WORKFLOW_PATH" >/dev/null
[[ -f "$DOC_PATH" ]]
[[ -f "$EXAMPLE_PATH" ]]
grep -F "deploy-vps-compose" "$ROOT_DIR/README.md" >/dev/null
grep -F "needs: build" "$EXAMPLE_PATH" >/dev/null
grep -F 'needs.build.outputs.image_tag' "$EXAMPLE_PATH" >/dev/null
grep -F 'needs.build.outputs.image_name' "$EXAMPLE_PATH" >/dev/null
printf 'ok\n'
