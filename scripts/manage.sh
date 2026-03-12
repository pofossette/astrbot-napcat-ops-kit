#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

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

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '缺少依赖命令：%s\n' "$1" >&2
    exit 1
  fi
}

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

run_script() {
  local script="$1"
  shift || true
  "$ROOT_DIR/scripts/$script" "$@"
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

show_header() {
  printf '\n%sQQBot 管理菜单%s\n' "$COLOR_TITLE" "$COLOR_RESET"
  printf '%s1.%s 启动服务\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s2.%s 启动服务（国内模式）\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s3.%s 查看服务状态\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s4.%s 停止服务\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s5.%s 查看日志\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s6.%s 创建备份\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s7.%s 恢复备份\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s8.%s 显示访问说明\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s0.%s 退出\n' "$COLOR_MENU" "$COLOR_RESET"
}

show_access_help() {
  printf '\n%s访问地址：%s\n' "$COLOR_TITLE" "$COLOR_RESET"
  printf '%s- AstrBot WebUI:%s http://<服务器IP>:6185\n' "$COLOR_HINT" "$COLOR_RESET"
  printf '%s- NapCat WebUI:%s  http://<服务器IP>:6099/webui\n' "$COLOR_HINT" "$COLOR_RESET"
  printf '\n%sAstrBot 默认账号：%s\n' "$COLOR_TITLE" "$COLOR_RESET"
  printf '%s- 用户名：%s astrbot\n' "$COLOR_HINT" "$COLOR_RESET"
  printf '%s- 密码：%s astrbot\n' "$COLOR_HINT" "$COLOR_RESET"
  printf '\n%sNapCat 接 AstrBot 的反向 WebSocket：%s\n' "$COLOR_TITLE" "$COLOR_RESET"
  printf '%s- URL:%s ws://astrbot:6199/ws\n' "$COLOR_HINT" "$COLOR_RESET"
}

show_status() {
  require_command docker
  docker compose ps
}

choose_log_service() {
  echo
  printf '%s日志选项：%s\n' "$COLOR_TITLE" "$COLOR_RESET"
  printf '%s1.%s 全部服务\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s2.%s astrbot\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s3.%s napcat\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s4.%s watchtower\n' "$COLOR_MENU" "$COLOR_RESET"
  read -r -p "请选择 [1-4，默认 1]: " log_choice

  case "${log_choice:-1}" in
    1) run_script "logs.sh" ;;
    2) run_script "logs.sh" "astrbot" ;;
    3) run_script "logs.sh" "napcat" ;;
    4) run_script "logs.sh" "watchtower" ;;
    *)
      print_error "无效选择。"
      ;;
  esac
}

create_backup() {
  local archive_path allow_live keep_count
  local args=()

  echo
  print_info "默认建议离线备份。若服务仍在运行，除非你明确选择在线备份，否则脚本会拒绝执行。"
  read -r -p "备份输出路径（默认留空，写入 ./backups）: " archive_path
  read -r -p "是否允许在线备份？[y/N]: " allow_live
  read -r -p "是否保留最近 N 份默认命名备份？留空表示不清理: " keep_count

  if [[ -n "$archive_path" ]]; then
    args+=("$archive_path")
  fi

  case "${allow_live:-N}" in
    y|Y|yes|YES)
      args+=("--allow-live")
      ;;
  esac

  if [[ -n "$keep_count" ]]; then
    args+=("--keep" "$keep_count")
  fi

  run_action "创建备份" run_script "backup.sh" "${args[@]}"
}

list_backups() {
  find "$ROOT_DIR/backups" -maxdepth 1 -type f -name '*.tar.gz' -printf '%TY-%Tm-%Td %TH:%TM  %p\n' 2>/dev/null | sort -r || true
}

select_backup_path() {
  local backups=()
  local index selection

  SELECTED_BACKUP_PATH=""

  if [[ -d "$ROOT_DIR/backups" ]]; then
    while IFS= read -r line; do
      backups+=("$line")
    done < <(find "$ROOT_DIR/backups" -maxdepth 1 -type f -name '*.tar.gz' | sort -r)
  fi

  if (( ${#backups[@]} == 0 )); then
    print_warn "未找到 ./backups 下的备份文件，请手动输入完整路径。"
    read -r -p "备份文件路径: " selection
    SELECTED_BACKUP_PATH="$selection"
    return
  fi

  printf '\n%s最近备份：%s\n' "$COLOR_TITLE" "$COLOR_RESET"
  for index in "${!backups[@]}"; do
    printf '%s%s.%s %s\n' "$COLOR_MENU" "$((index + 1))" "$COLOR_RESET" "${backups[$index]}"
  done
  printf '%sM.%s 手动输入其他路径\n' "$COLOR_MENU" "$COLOR_RESET"

  read -r -p "请选择备份编号 [默认 1]: " selection
  selection="${selection:-1}"

  if [[ "$selection" == "m" || "$selection" == "M" ]]; then
    read -r -p "备份文件路径: " selection
    SELECTED_BACKUP_PATH="$selection"
    return
  fi

  if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#backups[@]} )); then
    SELECTED_BACKUP_PATH="${backups[$((selection - 1))]}"
    return
  fi

  print_error "无效选择。"
  return 1
}

restore_backup() {
  local archive_path restore_items confirm
  local args=()
  local item

  echo
  select_backup_path || return
  archive_path="$SELECTED_BACKUP_PATH"
  echo
  print_info "已选择备份：$archive_path"

  if [[ -z "$archive_path" ]]; then
    print_error "未提供备份文件路径。"
    return
  fi

  printf '\n%s可选恢复项：%s\n' "$COLOR_TITLE" "$COLOR_RESET"
  printf '%s- all%s\n' "$COLOR_HINT" "$COLOR_RESET"
  printf '%s- config-files%s\n' "$COLOR_HINT" "$COLOR_RESET"
  printf '%s- data%s\n' "$COLOR_HINT" "$COLOR_RESET"
  printf '%s- napcat-config%s\n' "$COLOR_HINT" "$COLOR_RESET"
  printf '%s- napcat-qq%s\n' "$COLOR_HINT" "$COLOR_RESET"
  read -r -p "恢复项（默认 all，可输入多个并用空格分隔）: " restore_items
  read -r -p "恢复会覆盖现有数据，是否继续？[y/N]: " confirm

  case "${confirm:-N}" in
    y|Y|yes|YES) ;;
    *)
      print_warn "已取消恢复。"
      return
      ;;
  esac

  args+=("$archive_path" "--force")
  if [[ -n "${restore_items:-}" ]]; then
    for item in $restore_items; do
      args+=("--only" "$item")
    done
  fi

  run_action "恢复备份" run_script "restore.sh" "${args[@]}"
}

while true; do
  show_header
  read -r -p "请选择操作 [0-8]: " choice

  case "${choice:-}" in
    1)
      run_action "启动服务" run_script "up.sh"
      pause
      ;;
    2)
      run_action "启动服务（国内模式）" run_script "up.sh" "--domestic"
      pause
      ;;
    3)
      run_action "查看服务状态" show_status
      pause
      ;;
    4)
      run_action "停止服务" run_script "down.sh"
      pause
      ;;
    5)
      choose_log_service
      ;;
    6)
      create_backup
      pause
      ;;
    7)
      restore_backup
      pause
      ;;
    8)
      show_access_help
      pause
      ;;
    0)
      exit 0
      ;;
    *)
      print_error "无效选择。"
      pause
      ;;
  esac
done
