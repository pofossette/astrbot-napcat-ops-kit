#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BACKUP_DIR="$ROOT_DIR/backups"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
ARCHIVE_PATH=""
ALLOW_LIVE_BACKUP="false"
KEEP_COUNT=""
TMP_DIR="$(mktemp -d)"

usage() {
  cat <<'EOF'
用法：
  ./scripts/backup.sh [备份文件路径] [--allow-live] [--keep N]

说明：
  --allow-live  允许在容器仍在运行时继续备份
  --keep N      仅保留 backups/ 目录下最近 N 份默认命名备份
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '缺少依赖命令：%s\n' "$1" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-live)
      ALLOW_LIVE_BACKUP="true"
      shift
      ;;
    --keep)
      if [[ $# -lt 2 ]]; then
        echo "参数 --keep 需要提供一个数字。" >&2
        usage
        exit 1
      fi
      KEEP_COUNT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      printf '未知参数：%s\n' "$1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -n "$ARCHIVE_PATH" ]]; then
        echo "只能指定一个备份文件路径。" >&2
        usage
        exit 1
      fi
      ARCHIVE_PATH="$1"
      shift
      ;;
  esac
done

if [[ -z "$ARCHIVE_PATH" ]]; then
  ARCHIVE_PATH="$BACKUP_DIR/qqbot-backup-$TIMESTAMP.tar.gz"
fi

if [[ -n "$KEEP_COUNT" && ! "$KEEP_COUNT" =~ ^[0-9]+$ ]]; then
  echo "参数 --keep 只能是非负整数。" >&2
  exit 1
fi

ARCHIVE_DIR="$(dirname "$ARCHIVE_PATH")"
ARCHIVE_NAME="$(basename "$ARCHIVE_PATH")"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

require_command docker
require_command tar
require_command mktemp

mkdir -p "$ARCHIVE_DIR"

RUNNING_SERVICES="$(docker compose ps --services --status running 2>/dev/null || true)"
if [[ -n "$RUNNING_SERVICES" && "$ALLOW_LIVE_BACKUP" != "true" ]]; then
  cat <<EOF
检测到以下容器仍在运行：
$RUNNING_SERVICES

为保证 SQLite 和运行时数据的一致性，建议先执行：
  ./scripts/down.sh

如果你明确接受在线备份风险，可改用：
  ./scripts/backup.sh --allow-live
EOF
  exit 1
fi

if [[ -n "$RUNNING_SERVICES" && "$ALLOW_LIVE_BACKUP" == "true" ]]; then
  echo "警告：当前正在执行在线备份，归档中的数据库和运行时文件可能不是严格一致快照。"
fi

# 把备份元信息写进归档，方便后续核对来源和内容。
cat >"$TMP_DIR/manifest.txt" <<EOF
backup_created_at=$(date '+%Y-%m-%d %H:%M:%S %z')
project_root=$ROOT_DIR
archive_name=$ARCHIVE_NAME
docker_compose_version=$(docker compose version --short 2>/dev/null || echo unknown)
included_paths=.env compose.yaml data napcat/config napcat/qq
running_services=$(printf '%s' "$RUNNING_SERVICES" | tr '\n' ',' | sed 's/,$//')
EOF

INCLUDE_PATHS=(
  "compose.yaml"
  ".env"
  "data"
  "napcat/config"
  "napcat/qq"
)

# 只打包当前实际存在的路径，避免首次部署时因目录缺失报错。
EXISTING_PATHS=()
for path in "${INCLUDE_PATHS[@]}"; do
  if [[ -e "$path" ]]; then
    EXISTING_PATHS+=("$path")
  fi
done

if [[ ${#EXISTING_PATHS[@]} -eq 0 ]]; then
  echo "没有找到可备份的路径，请先确认项目已初始化。" >&2
  exit 1
fi

tar -czf "$ARCHIVE_PATH" -C "$ROOT_DIR" "${EXISTING_PATHS[@]}" -C "$TMP_DIR" "manifest.txt"

printf '备份已创建：%s\n' "$ARCHIVE_PATH"

if [[ -n "$KEEP_COUNT" ]]; then
  mapfile -t BACKUP_FILES < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'qqbot-backup-*.tar.gz' -printf '%T@ %p\n' | sort -rn | awk '{print $2}')
  if (( ${#BACKUP_FILES[@]} > KEEP_COUNT )); then
    for old_backup in "${BACKUP_FILES[@]:KEEP_COUNT}"; do
      rm -f "$old_backup"
      printf '已清理旧备份：%s\n' "$old_backup"
    done
  fi
fi
