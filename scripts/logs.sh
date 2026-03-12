#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
ensure_root_dir
require_command docker

FOLLOW="true"
TAIL_LINES=""
SERVICE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --follow)
      FOLLOW="true"
      shift
      ;;
    --no-follow)
      FOLLOW="false"
      shift
      ;;
    --tail)
      if [[ $# -lt 2 ]]; then
        echo "参数 --tail 需要提供行数。" >&2
        exit 1
      fi
      TAIL_LINES="$2"
      shift 2
      ;;
    -*)
      printf '未知参数：%s\n' "$1" >&2
      exit 1
      ;;
    *)
      if [[ -n "$SERVICE" ]]; then
        echo "只能指定一个服务名。" >&2
        exit 1
      fi
      SERVICE="$1"
      shift
      ;;
  esac
done

LOG_ARGS=()
if [[ "$FOLLOW" == "true" ]]; then
  LOG_ARGS+=("-f")
fi
if [[ -n "$TAIL_LINES" ]]; then
  LOG_ARGS+=("--tail" "$TAIL_LINES")
fi

if [[ -n "$SERVICE" ]]; then
  printf '正在查看服务日志：%s\n' "$SERVICE"
else
  echo "正在查看全部服务日志..."
fi

docker compose logs "${LOG_ARGS[@]}" "${SERVICE:-}"
