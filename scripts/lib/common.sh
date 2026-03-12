#!/usr/bin/env bash

ROOT_DIR="${ROOT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '缺少依赖命令：%s\n' "$1" >&2
    exit 1
  fi
}

get_docker_running_services() {
  local output
  require_command docker
  if ! output="$(docker compose ps --services --status running 2>&1)"; then
    printf '无法检查容器运行状态：%s\n' "$output" >&2
    return 1
  fi
  printf '%s' "$output"
}

ensure_root_dir() {
  cd "$ROOT_DIR"
}
