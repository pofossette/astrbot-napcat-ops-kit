#!/usr/bin/env bash

if [[ -t 1 ]]; then
  COLOR_RESET=$'\033[0m'
  COLOR_TITLE=$'\033[1;36m'
  COLOR_MENU=$'\033[1;34m'
  COLOR_OK=$'\033[1;32m'
  COLOR_WARN=$'\033[1;33m'
  COLOR_ERR=$'\033[1;31m'
  COLOR_HINT=$'\033[0;37m'
else
  COLOR_RESET=""
  COLOR_TITLE=""
  COLOR_MENU=""
  COLOR_OK=""
  COLOR_WARN=""
  COLOR_ERR=""
  COLOR_HINT=""
fi

print_info() {
  printf '%s%s%s\n' "$COLOR_HINT" "$1" "$COLOR_RESET"
}

print_ok() {
  printf '%s%s%s\n' "$COLOR_OK" "$1" "$COLOR_RESET"
}

print_warn() {
  printf '%s%s%s\n' "$COLOR_WARN" "$1" "$COLOR_RESET"
}

print_error() {
  printf '%s%s%s\n' "$COLOR_ERR" "$1" "$COLOR_RESET" >&2
}

pause() {
  read -r -p "按回车继续..." _
}

run_action() {
  local description="$1"
  shift

  print_info "正在执行：$description"
  if "$@"; then
    print_ok "执行完成：$description"
    return 0
  fi

  print_error "执行失败：$description"
  print_warn "如果提示和 Docker 权限、运行中容器或路径有关，请先按脚本提示处理后重试。"
  return 1
}
