#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "缺少依赖命令：docker" >&2
  exit 1
fi

echo "正在停止容器服务..."
docker compose down
echo "容器服务已停止。"
