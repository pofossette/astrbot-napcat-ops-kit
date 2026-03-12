#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
TEST_ROOT="$TMP_DIR/project"
FAKE_BIN="$TMP_DIR/bin"
BACKUP_PATH="$TMP_DIR/test-backup.tar.gz"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/scripts/lib" "$TEST_ROOT/docker" "$TEST_ROOT/data" "$FAKE_BIN"
cp "$ROOT_DIR/scripts/backup.sh" "$TEST_ROOT/scripts/backup.sh"
cp "$ROOT_DIR/scripts/restore.sh" "$TEST_ROOT/scripts/restore.sh"
cp "$ROOT_DIR/scripts/logs.sh" "$TEST_ROOT/scripts/logs.sh"
cp "$ROOT_DIR/scripts/lib/common.sh" "$TEST_ROOT/scripts/lib/common.sh"
cp "$ROOT_DIR/scripts/lib/archive.sh" "$TEST_ROOT/scripts/lib/archive.sh"
cp "$ROOT_DIR/scripts/lib/ui.sh" "$TEST_ROOT/scripts/lib/ui.sh"
chmod +x "$TEST_ROOT/scripts/"*.sh

cat >"$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "compose" ]]; then
  exit 1
fi
shift

case "${1:-}" in
  ps)
    if [[ "${DOCKER_PS_FAIL:-0}" == "1" ]]; then
      echo "permission denied" >&2
      exit 1
    fi
    if [[ "${DOCKER_RUNNING:-0}" == "1" ]]; then
      printf 'astrbot\nnapcat\n'
    fi
    ;;
  version)
    echo "fake-compose"
    ;;
  logs)
    echo "fake logs"
    ;;
  *)
    ;;
esac
EOF
chmod +x "$FAKE_BIN/docker"

cat >"$TEST_ROOT/compose.yaml" <<'EOF'
services: {}
EOF
cat >"$TEST_ROOT/.env" <<'EOF'
EXAMPLE=1
EOF
cat >"$TEST_ROOT/data/demo.txt" <<'EOF'
demo
EOF

run_in_test_root() {
  PATH="$FAKE_BIN:$PATH" "$@"
}

assert_contains() {
  local text="$1"
  local pattern="$2"
  if [[ "$text" != *"$pattern"* ]]; then
    echo "assert_contains failed: missing '$pattern'" >&2
    exit 1
  fi
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -Fq "$pattern" "$file"; then
    echo "assert_file_contains failed: $file missing '$pattern'" >&2
    exit 1
  fi
}

backup_output="$(
  cd "$TEST_ROOT"
  run_in_test_root ./scripts/backup.sh "$BACKUP_PATH"
)"
assert_contains "$backup_output" "备份已创建"
manifest_output="$(tar -xOf "$BACKUP_PATH" manifest.txt)"
assert_contains "$manifest_output" "included_paths=compose.yaml .env data"
assert_contains "$manifest_output" "backup_mode=offline"

live_error="$(
  cd "$TEST_ROOT"
  DOCKER_RUNNING=1 run_in_test_root ./scripts/backup.sh "$TMP_DIR/live.tar.gz" 2>&1 || true
)"
assert_contains "$live_error" "检测到以下容器仍在运行"

permission_error="$(
  cd "$TEST_ROOT"
  DOCKER_PS_FAIL=1 run_in_test_root ./scripts/backup.sh "$TMP_DIR/fail.tar.gz" 2>&1 || true
)"
assert_contains "$permission_error" "无法检查容器运行状态"

mkdir -p "$TEST_ROOT/backups"
cp "$BACKUP_PATH" "$TEST_ROOT/backups/restore.tar.gz"
cat >"$TEST_ROOT/data/demo.txt" <<'EOF'
changed
EOF

restore_output="$(
  cd "$TEST_ROOT"
  run_in_test_root ./scripts/restore.sh "$TEST_ROOT/backups/restore.tar.gz" --force --only config-files --only data
)"
assert_contains "$restore_output" "备份已恢复"
assert_file_contains "$TEST_ROOT/data/demo.txt" "demo"

bad_archive="$TMP_DIR/bad.tar.gz"
tar -czf "$bad_archive" -C "$TEST_ROOT" compose.yaml
invalid_restore="$(
  cd "$TEST_ROOT"
  run_in_test_root ./scripts/restore.sh "$bad_archive" --force 2>&1 || true
)"
assert_contains "$invalid_restore" "缺少 manifest.txt"
assert_file_contains "$TEST_ROOT/data/demo.txt" "demo"

log_output="$(
  cd "$TEST_ROOT"
  run_in_test_root ./scripts/logs.sh --no-follow --tail 10
)"
assert_contains "$log_output" "正在查看全部服务日志"

echo "smoke tests passed"
