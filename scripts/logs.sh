#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "缺少依赖命令：docker" >&2
  exit 1
fi

if [[ -n "${1:-}" ]]; then
  printf '正在查看服务日志：%s\n' "$1"
else
  echo "正在查看全部服务日志..."
fi

docker compose logs -f "${1:-}"
