#!/usr/bin/env bash

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_LIB_DIR/common.sh"

print_manifest() {
  local archive_path="$1"
  tar -xOf "$archive_path" manifest.txt
}

list_backup_files() {
  find "$ROOT_DIR/backups" -maxdepth 1 -type f -name '*.tar.gz' | sort -r 2>/dev/null || true
}

list_backup_table() {
  find "$ROOT_DIR/backups" -maxdepth 1 -type f -name '*.tar.gz' -printf '%TY-%Tm-%Td %TH:%TM  %p\n' 2>/dev/null | sort -r || true
}

verify_backup_archive() {
  local archive_path="$1"
  local manifest included_paths
  local path

  if [[ ! -f "$archive_path" ]]; then
    printf '未找到备份文件：%s\n' "$archive_path" >&2
    return 1
  fi

  if ! tar -tzf "$archive_path" manifest.txt >/dev/null 2>&1; then
    echo "备份文件缺少 manifest.txt。" >&2
    return 1
  fi

  manifest="$(print_manifest "$archive_path")"
  included_paths="$(printf '%s\n' "$manifest" | awk -F= '$1=="included_paths"{print $2}')"
  if [[ -z "$included_paths" ]]; then
    echo "manifest.txt 缺少 included_paths。" >&2
    return 1
  fi

  for path in $included_paths; do
    if ! tar -tzf "$archive_path" "$path" >/dev/null 2>&1; then
      printf '备份文件缺少 manifest 声明的路径：%s\n' "$path" >&2
      return 1
    fi
  done
}
