#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/archive.sh
source "$SCRIPT_DIR/lib/archive.sh"
# shellcheck source=lib/ui.sh
source "$SCRIPT_DIR/lib/ui.sh"
ensure_root_dir

run_script() {
  local script="$1"
  shift || true
  "$ROOT_DIR/scripts/$script" "$@"
}

get_running_services() {
  get_docker_running_services
}

show_header() {
  printf '\n%sQQBot 管理菜单%s\n' "$COLOR_TITLE" "$COLOR_RESET"
  printf '%s1.%s 启动服务\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s2.%s 启动服务（国内模式）\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s3.%s 查看服务状态\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s4.%s 停止服务\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s5.%s 重启服务\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s6.%s 查看最近日志\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s7.%s 持续跟随日志\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s8.%s 一键安全备份\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s9.%s 自定义备份\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s10.%s 验证备份\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s11.%s 备份详情\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s12.%s 恢复备份\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s13.%s 显示访问说明\n' "$COLOR_MENU" "$COLOR_RESET"
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
  local mode="$1"
  local tail_lines=""

  echo
  printf '%s日志选项：%s\n' "$COLOR_TITLE" "$COLOR_RESET"
  printf '%s1.%s 全部服务\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s2.%s astrbot\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s3.%s napcat\n' "$COLOR_MENU" "$COLOR_RESET"
  printf '%s4.%s watchtower\n' "$COLOR_MENU" "$COLOR_RESET"
  if [[ "$mode" == "recent" ]]; then
    read -r -p "最近日志行数 [默认 100]: " tail_lines
    tail_lines="${tail_lines:-100}"
  fi
  read -r -p "请选择 [1-4，默认 1]: " log_choice

  case "${log_choice:-1}" in
    1)
      if [[ "$mode" == "recent" ]]; then
        run_action "查看最近日志" run_script "logs.sh" "--no-follow" "--tail" "$tail_lines"
      else
        run_script "logs.sh"
      fi
      ;;
    2)
      if [[ "$mode" == "recent" ]]; then
        run_action "查看 astrbot 最近日志" run_script "logs.sh" "--no-follow" "--tail" "$tail_lines" "astrbot"
      else
        run_script "logs.sh" "astrbot"
      fi
      ;;
    3)
      if [[ "$mode" == "recent" ]]; then
        run_action "查看 napcat 最近日志" run_script "logs.sh" "--no-follow" "--tail" "$tail_lines" "napcat"
      else
        run_script "logs.sh" "napcat"
      fi
      ;;
    4)
      if [[ "$mode" == "recent" ]]; then
        run_action "查看 watchtower 最近日志" run_script "logs.sh" "--no-follow" "--tail" "$tail_lines" "watchtower"
      else
        run_script "logs.sh" "watchtower"
      fi
      ;;
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

safe_backup() {
  local archive_path keep_count restart_needed="false"
  local args=()
  local running_services

  echo
  print_info "该流程会在必要时自动停止服务，创建离线备份，再恢复服务。"
  read -r -p "备份输出路径（默认留空，写入 ./backups）: " archive_path
  read -r -p "是否保留最近 N 份默认命名备份？留空表示不清理: " keep_count

  if [[ -n "$archive_path" ]]; then
    args+=("$archive_path")
  fi
  if [[ -n "$keep_count" ]]; then
    args+=("--keep" "$keep_count")
  fi

  running_services="$(get_running_services)" || return 1
  if [[ -n "$running_services" ]]; then
    restart_needed="true"
    print_warn "检测到运行中容器，将先停止服务后再备份。"
    run_action "停止服务" run_script "down.sh" || return 1
  fi

  if ! run_action "创建离线备份" run_script "backup.sh" "${args[@]}"; then
    if [[ "$restart_needed" == "true" ]]; then
      print_warn "备份失败，正在尝试恢复服务。"
      run_action "恢复启动服务" run_script "up.sh" || true
    fi
    return 1
  fi

  if [[ "$restart_needed" == "true" ]]; then
    run_action "恢复启动服务" run_script "up.sh" || return 1
  fi
}

list_backups() {
  list_backup_table
}

show_backup_details() {
  local archive_path="$1"

  run_action "查看备份详情" ls -lh "$archive_path" || return 1
  echo
  run_action "读取备份 manifest" print_manifest "$archive_path"
}

select_backup_path() {
  local backups=()
  local index selection

  SELECTED_BACKUP_PATH=""

  while IFS= read -r line; do
    backups+=("$line")
  done < <(list_backup_files)

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
  read -r -p "请选择操作 [0-13]: " choice

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
      run_action "重启服务" run_script "down.sh" && run_action "启动服务" run_script "up.sh"
      pause
      ;;
    6)
      choose_log_service "recent"
      pause
      ;;
    7)
      choose_log_service "follow"
      pause
      ;;
    8)
      safe_backup
      pause
      ;;
    9)
      create_backup
      pause
      ;;
    10)
      echo
      select_backup_path || {
        pause
        continue
      }
      if verify_backup_archive "$SELECTED_BACKUP_PATH"; then
        print_ok "备份校验通过：$SELECTED_BACKUP_PATH"
      else
        print_error "备份校验失败：$SELECTED_BACKUP_PATH"
      fi
      pause
      ;;
    11)
      echo
      select_backup_path || {
        pause
        continue
      }
      show_backup_details "$SELECTED_BACKUP_PATH"
      pause
      ;;
    12)
      restore_backup
      pause
      ;;
    13)
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
