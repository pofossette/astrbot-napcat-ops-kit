#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 1 ]]; then
  echo "Usage: ./scripts/restore.sh <backup.tar.gz> [--force]"
  exit 1
fi

ARCHIVE_PATH="$1"
FORCE_RESTORE="${2:-}"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "Backup archive not found: $ARCHIVE_PATH" >&2
  exit 1
fi

if [[ "$FORCE_RESTORE" != "" && "$FORCE_RESTORE" != "--force" ]]; then
  echo "Unknown option: $FORCE_RESTORE" >&2
  exit 1
fi

if [[ "$FORCE_RESTORE" != "--force" ]]; then
  cat <<'EOF'
Restore will overwrite the current data/config directories.
Run again with --force after stopping the stack:
  ./scripts/down.sh
  ./scripts/restore.sh <backup.tar.gz> --force
EOF
  exit 1
fi

mkdir -p data napcat/config napcat/qq
rm -rf data napcat/config napcat/qq

tar -xzf "$ARCHIVE_PATH" -C "$ROOT_DIR"

printf 'Backup restored from: %s\n' "$ARCHIVE_PATH"
printf 'Next step: ./scripts/up.sh\n'
