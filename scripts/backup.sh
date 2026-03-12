#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BACKUP_DIR="$ROOT_DIR/backups"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
ARCHIVE_PATH="${1:-$BACKUP_DIR/qqbot-backup-$TIMESTAMP.tar.gz}"
ARCHIVE_DIR="$(dirname "$ARCHIVE_PATH")"
ARCHIVE_NAME="$(basename "$ARCHIVE_PATH")"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

mkdir -p "$ARCHIVE_DIR"

cat >"$TMP_DIR/manifest.txt" <<EOF
backup_created_at=$(date '+%Y-%m-%d %H:%M:%S %z')
project_root=$ROOT_DIR
archive_name=$ARCHIVE_NAME
docker_compose_version=$(docker compose version --short 2>/dev/null || echo unknown)
included_paths=.env compose.yaml data napcat/config napcat/qq
EOF

INCLUDE_PATHS=(
  "compose.yaml"
  ".env"
  "data"
  "napcat/config"
  "napcat/qq"
)

EXISTING_PATHS=()
for path in "${INCLUDE_PATHS[@]}"; do
  if [[ -e "$path" ]]; then
    EXISTING_PATHS+=("$path")
  fi
done

tar -czf "$ARCHIVE_PATH" -C "$ROOT_DIR" "${EXISTING_PATHS[@]}" -C "$TMP_DIR" "manifest.txt"

printf 'Backup created: %s\n' "$ARCHIVE_PATH"

