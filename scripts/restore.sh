#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
ensure_root_dir
TMP_DIR="$(mktemp -d)"
STAGE_DIR="$TMP_DIR/stage"
ROLLBACK_DIR="$TMP_DIR/rollback"
RESTORE_STARTED="false"

usage() {
  cat <<'EOF'
用法：
  ./scripts/restore.sh <backup.tar.gz> [--force] [--only 项]

可选恢复项：
  all            恢复全部内容（默认）
  config-files   恢复 .env 和 compose.yaml
  data           恢复 AstrBot 数据目录
  napcat-config  恢复 NapCat 配置目录
  napcat-qq      恢复 NapCat QQ 登录态目录

示例：
  ./scripts/restore.sh ./backups/demo.tar.gz --force
  ./scripts/restore.sh ./backups/demo.tar.gz --force --only data
  ./scripts/restore.sh ./backups/demo.tar.gz --force --only napcat-qq --only napcat-config
EOF
}

contains_item() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

cleanup() {
  local exit_code=$?
  local path

  if [[ "$exit_code" -ne 0 && "$RESTORE_STARTED" == "true" ]]; then
    for path in "${CLEAN_PATHS[@]:-}"; do
      rm -rf "$ROOT_DIR/$path"
      if [[ -e "$ROLLBACK_DIR/$path" ]]; then
        mkdir -p "$(dirname "$ROOT_DIR/$path")"
        mv "$ROLLBACK_DIR/$path" "$ROOT_DIR/$path"
      fi
    done
  fi

  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

ARCHIVE_PATH="$1"
shift

FORCE_RESTORE="false"
RESTORE_ITEMS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE_RESTORE="true"
      shift
      ;;
    --only)
      if [[ $# -lt 2 ]]; then
        echo "参数 --only 需要提供恢复项。" >&2
        usage
        exit 1
      fi
      RESTORE_ITEMS+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '未知参数：%s\n' "$1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "未找到备份文件：$ARCHIVE_PATH" >&2
  exit 1
fi

if [[ "$FORCE_RESTORE" != "true" ]]; then
  cat <<'EOF'
恢复会覆盖当前的数据和配置目录。
请先停止容器，再带上 --force 重新执行：
  ./scripts/down.sh
  ./scripts/restore.sh <backup.tar.gz> --force
EOF
  exit 1
fi

require_command docker
require_command tar

RUNNING_SERVICES="$(get_docker_running_services)"
if [[ -n "$RUNNING_SERVICES" ]]; then
  cat <<EOF
检测到以下容器仍在运行：
$RUNNING_SERVICES

恢复前必须先停止容器，避免正在运行的服务继续写入：
  ./scripts/down.sh
EOF
  exit 1
fi

if ! tar -tzf "$ARCHIVE_PATH" manifest.txt >/dev/null 2>&1; then
  echo "备份文件缺少 manifest.txt，无法确认是否为有效备份。" >&2
  exit 1
fi

if [[ ${#RESTORE_ITEMS[@]} -eq 0 ]]; then
  RESTORE_ITEMS=("all")
fi

VALID_ITEMS=("all" "config-files" "data" "napcat-config" "napcat-qq")
for item in "${RESTORE_ITEMS[@]}"; do
  if ! contains_item "$item" "${VALID_ITEMS[@]}"; then
    printf '不支持的恢复项：%s\n' "$item" >&2
    usage
    exit 1
  fi
done

if contains_item "all" "${RESTORE_ITEMS[@]}" && [[ ${#RESTORE_ITEMS[@]} -gt 1 ]]; then
  echo "参数 all 不能和其他 --only 同时使用。" >&2
  exit 1
fi

ARCHIVE_CHECK_PATHS=("manifest.txt")
EXTRACT_PATHS=()
CLEAN_PATHS=()
declare -A ITEM_PATHS=(
  ["config-files"]=".env compose.yaml"
  ["data"]="data"
  ["napcat-config"]="napcat/config"
  ["napcat-qq"]="napcat/qq"
)

if contains_item "all" "${RESTORE_ITEMS[@]}"; then
  RESTORE_ITEMS=("config-files" "data" "napcat-config" "napcat-qq")
fi

for item in "${RESTORE_ITEMS[@]}"; do
  for path in ${ITEM_PATHS[$item]}; do
    ARCHIVE_CHECK_PATHS+=("$path")
    EXTRACT_PATHS+=("$path")
    CLEAN_PATHS+=("$path")
  done
done

for path in "${ARCHIVE_CHECK_PATHS[@]}"; do
  if ! tar -tzf "$ARCHIVE_PATH" "$path" >/dev/null 2>&1; then
    printf '备份文件中缺少必要路径：%s\n' "$path" >&2
    exit 1
  fi
done

mkdir -p "$STAGE_DIR" "$ROLLBACK_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$STAGE_DIR" "${EXTRACT_PATHS[@]}"

for path in "${EXTRACT_PATHS[@]}"; do
  if [[ ! -e "$STAGE_DIR/$path" ]]; then
    printf '备份文件解压后缺少必要路径：%s\n' "$path" >&2
    exit 1
  fi
done

RESTORE_STARTED="true"

# 先把现有数据移到回滚目录，再用已解压的目标内容整体替换，避免中途失败时留下半恢复状态。
for path in "${CLEAN_PATHS[@]}"; do
  if [[ -e "$ROOT_DIR/$path" ]]; then
    mkdir -p "$(dirname "$ROLLBACK_DIR/$path")"
    mv "$ROOT_DIR/$path" "$ROLLBACK_DIR/$path"
  fi

  mkdir -p "$(dirname "$ROOT_DIR/$path")"
  mv "$STAGE_DIR/$path" "$ROOT_DIR/$path"
done

RESTORE_STARTED="false"

printf '备份已恢复：%s\n' "$ARCHIVE_PATH"
printf '已恢复内容：%s\n' "${RESTORE_ITEMS[*]}"
printf '下一步请执行：./scripts/up.sh\n'
