#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Callable, Iterable


ROOT_DIR = Path(__file__).resolve().parent.parent
BACKUP_DIR = ROOT_DIR / "backups"
INCLUDE_PATHS = (
    Path("compose.yaml"),
    Path(".env"),
    Path("data"),
    Path("napcat/config"),
    Path("napcat/qq"),
)
RESTORE_ITEM_PATHS: dict[str, tuple[Path, ...]] = {
    "config-files": (Path(".env"), Path("compose.yaml")),
    "data": (Path("data"),),
    "napcat-config": (Path("napcat/config"),),
    "napcat-qq": (Path("napcat/qq"),),
}
VALID_RESTORE_ITEMS = ("all", *RESTORE_ITEM_PATHS.keys())
ACCESS_HELP = """
访问地址：
- AstrBot WebUI: http://<服务器IP>:6185
- NapCat WebUI:  http://<服务器IP>:6099/webui

AstrBot 默认账号：
- 用户名： astrbot
- 密码： astrbot

NapCat 接 AstrBot 的反向 WebSocket：
- URL: ws://astrbot:6199/ws
""".strip()


class DeployError(Exception):
    pass


@dataclass
class Colors:
    reset: str = ""
    title: str = ""
    menu: str = ""
    ok: str = ""
    warn: str = ""
    err: str = ""
    hint: str = ""

    @classmethod
    def for_stdout(cls) -> "Colors":
        if not sys.stdout.isatty():
            return cls()
        return cls(
            reset="\033[0m",
            title="\033[1;36m",
            menu="\033[1;34m",
            ok="\033[1;32m",
            warn="\033[1;33m",
            err="\033[1;31m",
            hint="\033[0;37m",
        )


COLORS = Colors.for_stdout()


def print_info(message: str) -> None:
    print(f"{COLORS.hint}{message}{COLORS.reset}")


def print_ok(message: str) -> None:
    print(f"{COLORS.ok}{message}{COLORS.reset}")


def print_warn(message: str) -> None:
    print(f"{COLORS.warn}{message}{COLORS.reset}")


def print_error(message: str) -> None:
    print(f"{COLORS.err}{message}{COLORS.reset}", file=sys.stderr)


def require_command(command: str) -> None:
    if shutil.which(command):
        return
    raise DeployError(f"缺少依赖命令：{command}")


def subprocess_error_detail(exc: subprocess.CalledProcessError) -> str:
    if exc.stderr:
        return exc.stderr.strip()
    if exc.stdout:
        return exc.stdout.strip()
    return str(exc)


def require_docker_compose() -> None:
    require_command("docker")
    try:
        run_command(["docker", "compose", "version"], capture_output=True)
    except subprocess.CalledProcessError as exc:
        detail = subprocess_error_detail(exc)
        raise DeployError(
            "当前环境不可用 `docker compose`。\n"
            "请先安装 Docker Compose Plugin，或确认你的 Docker 版本已包含该子命令。\n"
            f"原始错误：{detail}"
        ) from exc


def run_command(args: list[str], *, capture_output: bool = False, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=ROOT_DIR,
        text=True,
        capture_output=capture_output,
        check=check,
    )


def get_running_services() -> str:
    require_docker_compose()
    try:
        result = run_command(
            ["docker", "compose", "ps", "--services", "--status", "running"],
            capture_output=True,
        )
    except subprocess.CalledProcessError as exc:
        detail = subprocess_error_detail(exc)
        raise DeployError(f"无法检查容器运行状态：{detail}") from exc
    return result.stdout.strip()


def compose_version() -> str:
    try:
        result = run_command(["docker", "compose", "version", "--short"], capture_output=True)
    except subprocess.CalledProcessError:
        return "unknown"
    return result.stdout.strip() or "unknown"


def tar_member_names(archive_path: Path) -> set[str]:
    with tarfile.open(archive_path, "r:gz") as archive:
        return set(archive.getnames())


def print_manifest(archive_path: Path) -> None:
    with tarfile.open(archive_path, "r:gz") as archive:
        member = archive.extractfile("manifest.txt")
        if member is None:
            raise DeployError("备份文件缺少 manifest.txt。")
        sys.stdout.write(member.read().decode("utf-8"))


def list_backup_files() -> list[Path]:
    if not BACKUP_DIR.exists():
        return []
    return sorted(BACKUP_DIR.glob("*.tar.gz"), reverse=True)


def list_backup_table() -> list[str]:
    rows: list[str] = []
    for path in list_backup_files():
        modified = datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
        rows.append(f"{modified}  {path}")
    return rows


def verify_backup_archive(archive_path: Path) -> None:
    if not archive_path.is_file():
        raise DeployError(f"未找到备份文件：{archive_path}")
    names = tar_member_names(archive_path)
    if "manifest.txt" not in names:
        raise DeployError("备份文件缺少 manifest.txt。")
    with tarfile.open(archive_path, "r:gz") as archive:
        member = archive.extractfile("manifest.txt")
        if member is None:
            raise DeployError("备份文件缺少 manifest.txt。")
        manifest = member.read().decode("utf-8")
    included_paths = ""
    for line in manifest.splitlines():
        if line.startswith("included_paths="):
            included_paths = line.split("=", 1)[1].strip()
            break
    if not included_paths:
        raise DeployError("manifest.txt 缺少 included_paths。")
    for path in included_paths.split():
        if path not in names:
            raise DeployError(f"备份文件缺少 manifest 声明的路径：{path}")


def command_up(domestic: bool = False) -> None:
    from up import ensure_directories, initialize_env, run_compose_up

    require_docker_compose()
    ensure_directories()
    initialize_env(domestic=domestic)
    run_compose_up()
    print()
    print(
        """
服务已启动。

下一步：
1. 打开 AstrBot: http://<服务器IP>:6185
2. 打开 NapCat:  http://<服务器IP>:6099/webui
3. 在 NapCat WebUI 中登录 QQ
4. 在 AstrBot 中创建一个 OneBot v11 机器人：
   host=0.0.0.0 port=6199
5. 在 NapCat 中添加 WebSockets Client：
   url=ws://astrbot:6199/ws

AstrBot 默认账号：
用户名：astrbot
密码：astrbot
""".strip()
    )


def command_down() -> None:
    require_docker_compose()
    print("正在停止容器服务...")
    try:
        run_command(["docker", "compose", "down"], capture_output=True)
    except subprocess.CalledProcessError as exc:
        detail = subprocess_error_detail(exc)
        raise DeployError(f"停止容器服务失败：{detail}") from exc
    print("容器服务已停止。")


def command_logs(service: str = "", follow: bool = True, tail_lines: str = "") -> None:
    require_docker_compose()
    args = ["docker", "compose", "logs"]
    if follow:
        args.append("-f")
    if tail_lines:
        args.extend(["--tail", tail_lines])
    if service:
        print(f"正在查看服务日志：{service}")
        args.append(service)
    else:
        print("正在查看全部服务日志...")
    try:
        run_command(args)
    except subprocess.CalledProcessError as exc:
        detail = subprocess_error_detail(exc)
        raise DeployError(f"查看日志失败：{detail}") from exc


def create_backup(archive_path: str = "", allow_live: bool = False, keep_count: str = "") -> Path:
    require_docker_compose()
    require_command("tar")
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    archive = Path(archive_path) if archive_path else BACKUP_DIR / f"qqbot-backup-{timestamp}.tar.gz"
    if keep_count and not keep_count.isdigit():
        raise DeployError("参数 --keep 只能是非负整数。")
    archive.parent.mkdir(parents=True, exist_ok=True)

    running_services = get_running_services()
    backup_mode = "offline"
    if running_services and not allow_live:
        raise DeployError(
            "检测到以下容器仍在运行：\n"
            f"{running_services}\n\n"
            "为保证 SQLite 和运行时数据的一致性，建议先执行：\n"
            "  ./scripts/down.sh\n\n"
            "如果你明确接受在线备份风险，可改用：\n"
            "  ./scripts/backup.sh --allow-live"
        )
    if running_services and allow_live:
        backup_mode = "live"
        print("警告：当前正在执行在线备份，归档中的数据库和运行时文件可能不是严格一致快照。")

    existing_paths = [path for path in INCLUDE_PATHS if (ROOT_DIR / path).exists()]
    if not existing_paths:
        raise DeployError("没有找到可备份的路径，请先确认项目已初始化。")

    manifest_lines = [
        f"backup_created_at={datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S %z')}",
        f"project_root={ROOT_DIR}",
        f"archive_name={archive.name}",
        f"docker_compose_version={compose_version()}",
        f"backup_mode={backup_mode}",
        f"included_paths={' '.join(str(path) for path in existing_paths)}",
        f"running_services={','.join(running_services.splitlines())}",
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        manifest_path = Path(tmpdir) / "manifest.txt"
        manifest_path.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")
        with tarfile.open(archive, "w:gz") as tar:
            for path in existing_paths:
                tar.add(ROOT_DIR / path, arcname=str(path))
            tar.add(manifest_path, arcname="manifest.txt")

    print(f"备份已创建：{archive}")
    prune_backups(keep_count)
    return archive


def prune_backups(keep_count: str) -> None:
    if not keep_count:
        return
    limit = int(keep_count)
    backup_files = sorted(
        BACKUP_DIR.glob("qqbot-backup-*.tar.gz"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    for old_backup in backup_files[limit:]:
        old_backup.unlink(missing_ok=True)
        print(f"已清理旧备份：{old_backup}")


def resolve_restore_items(items: list[str]) -> list[str]:
    restore_items = items or ["all"]
    for item in restore_items:
        if item not in VALID_RESTORE_ITEMS:
            raise DeployError(f"不支持的恢复项：{item}")
    if "all" in restore_items and len(restore_items) > 1:
        raise DeployError("参数 all 不能和其他 --only 同时使用。")
    if restore_items == ["all"]:
        return list(RESTORE_ITEM_PATHS)
    return restore_items


def restore_backup(archive_path: str, force: bool = False, restore_items: list[str] | None = None) -> None:
    archive = Path(archive_path)
    if not archive.is_file():
        raise DeployError(f"未找到备份文件：{archive}")
    if not force:
        raise DeployError(
            "恢复会覆盖当前的数据和配置目录。\n"
            "请先停止容器，再带上 --force 重新执行：\n"
            "  ./scripts/down.sh\n"
            "  ./scripts/restore.sh <backup.tar.gz> --force"
        )

    require_docker_compose()
    require_command("tar")
    running_services = get_running_services()
    if running_services:
        raise DeployError(
            "检测到以下容器仍在运行：\n"
            f"{running_services}\n\n"
            "恢复前必须先停止容器，避免正在运行的服务继续写入：\n"
            "  ./scripts/down.sh"
        )

    names = tar_member_names(archive)
    if "manifest.txt" not in names:
        raise DeployError("备份文件缺少 manifest.txt，无法确认是否为有效备份。")

    selected_items = resolve_restore_items(restore_items or [])
    extract_paths: list[Path] = []
    for item in selected_items:
        extract_paths.extend(RESTORE_ITEM_PATHS[item])
    for path in extract_paths:
        if str(path) not in names:
            raise DeployError(f"备份文件中缺少必要路径：{path}")

    rollback_entries: list[tuple[Path, Path]] = []
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        stage_dir = tmp_path / "stage"
        rollback_dir = tmp_path / "rollback"
        stage_dir.mkdir()
        rollback_dir.mkdir()
        with tarfile.open(archive, "r:gz") as tar:
            members = [
                member
                for member in tar.getmembers()
                if any(
                    member.name == str(path) or member.name.startswith(f"{path}/")
                    for path in extract_paths
                )
            ]
            tar.extractall(stage_dir, members=members)
        for path in extract_paths:
            staged = stage_dir / path
            if not staged.exists():
                raise DeployError(f"备份文件解压后缺少必要路径：{path}")
        try:
            for path in extract_paths:
                target = ROOT_DIR / path
                backup_target = rollback_dir / path
                if target.exists():
                    backup_target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(target), str(backup_target))
                    rollback_entries.append((target, backup_target))
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(stage_dir / path), str(target))
        except Exception as exc:
            for target, backup_target in rollback_entries:
                if target.exists():
                    if target.is_dir():
                        shutil.rmtree(target)
                    else:
                        target.unlink()
                if backup_target.exists():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(backup_target), str(target))
            raise exc

    print(f"备份已恢复：{archive}")
    print(f"已恢复内容：{' '.join(selected_items)}")
    print("下一步请执行：./scripts/up.sh")


def parse_backup_selection(selection: str, backups: list[Path]) -> Path:
    value = selection.strip() or "1"
    if value.lower() == "m":
        entered = input("备份文件路径: ").strip()
        return Path(entered)
    if value.isdigit():
        index = int(value)
        if 1 <= index <= len(backups):
            return backups[index - 1]
    raise DeployError("无效选择。")


def pause() -> None:
    input("按回车继续...")


def run_action(description: str, action: Callable[[], None]) -> bool:
    print_info(f"正在执行：{description}")
    try:
        action()
    except (DeployError, subprocess.CalledProcessError) as exc:
        print_error(f"执行失败：{description}")
        if isinstance(exc, subprocess.CalledProcessError):
            detail = subprocess_error_detail(exc)
        else:
            detail = str(exc).strip()
        if detail:
            print_error(detail)
        print_warn("如果提示和 Docker 权限、运行中容器或路径有关，请先按脚本提示处理后重试。")
        return False
    print_ok(f"执行完成：{description}")
    return True


def show_status() -> None:
    require_docker_compose()
    try:
        result = run_command(["docker", "compose", "ps"], capture_output=True)
    except subprocess.CalledProcessError as exc:
        detail = subprocess_error_detail(exc)
        raise DeployError(f"查看服务状态失败：{detail}") from exc
    if result.stdout:
        sys.stdout.write(result.stdout)


def choose_log_service(mode: str) -> None:
    print()
    print(f"{COLORS.title}日志选项：{COLORS.reset}")
    print(f"{COLORS.menu}1.{COLORS.reset} 全部服务")
    print(f"{COLORS.menu}2.{COLORS.reset} astrbot")
    print(f"{COLORS.menu}3.{COLORS.reset} napcat")
    print(f"{COLORS.menu}4.{COLORS.reset} watchtower")
    tail_lines = ""
    if mode == "recent":
        tail_lines = input("最近日志行数 [默认 100]: ").strip() or "100"
    choice = input("请选择 [1-4，默认 1]: ").strip() or "1"
    service = {"1": "", "2": "astrbot", "3": "napcat", "4": "watchtower"}.get(choice)
    if service is None:
        raise DeployError("无效选择。")
    command_logs(service=service, follow=(mode != "recent"), tail_lines=tail_lines)


def safe_backup_flow() -> None:
    print()
    print_info("该流程会在必要时自动停止服务，创建离线备份，再恢复服务。")
    archive_path = input("备份输出路径（默认留空，写入 ./backups）: ").strip()
    keep_count = input("是否保留最近 N 份默认命名备份？留空表示不清理: ").strip()
    restart_needed = False
    running_services = get_running_services()
    if running_services:
        restart_needed = True
        print_warn("检测到运行中容器，将先停止服务后再备份。")
        if not run_action("停止服务", command_down):
            return
    try:
        create_backup(archive_path=archive_path, allow_live=False, keep_count=keep_count)
    except Exception:
        if restart_needed:
            print_warn("备份失败，正在尝试恢复服务。")
            run_action("恢复启动服务", command_up)
        raise
    if restart_needed:
        command_up()


def create_backup_flow() -> None:
    print()
    print_info("默认建议离线备份。若服务仍在运行，除非你明确选择在线备份，否则脚本会拒绝执行。")
    archive_path = input("备份输出路径（默认留空，写入 ./backups）: ").strip()
    allow_live = input("是否允许在线备份？[y/N]: ").strip().lower() in {"y", "yes"}
    keep_count = input("是否保留最近 N 份默认命名备份？留空表示不清理: ").strip()
    create_backup(archive_path=archive_path, allow_live=allow_live, keep_count=keep_count)


def select_backup_path() -> Path:
    backups = list_backup_files()
    if not backups:
        print_warn("未找到 ./backups 下的备份文件，请手动输入完整路径。")
        return Path(input("备份文件路径: ").strip())
    print(f"\n{COLORS.title}最近备份：{COLORS.reset}")
    for index, path in enumerate(backups, start=1):
        print(f"{COLORS.menu}{index}.{COLORS.reset} {path}")
    print(f"{COLORS.menu}M.{COLORS.reset} 手动输入其他路径")
    selection = input("请选择备份编号 [默认 1]: ")
    return parse_backup_selection(selection, backups)


def show_backup_details(archive_path: Path) -> None:
    size = archive_path.stat().st_size
    print(f"{archive_path}  {size} bytes")
    print()
    print_manifest(archive_path)


def restore_backup_flow() -> None:
    print()
    archive_path = select_backup_path()
    print()
    print_info(f"已选择备份：{archive_path}")
    print(f"\n{COLORS.title}可选恢复项：{COLORS.reset}")
    for item in VALID_RESTORE_ITEMS:
        print(f"{COLORS.hint}- {item}{COLORS.reset}")
    restore_items_text = input("恢复项（默认 all，可输入多个并用空格分隔）: ").strip()
    confirm = input("恢复会覆盖现有数据，是否继续？[y/N]: ").strip().lower()
    if confirm not in {"y", "yes"}:
        print_warn("已取消恢复。")
        return
    restore_items = restore_items_text.split() if restore_items_text else []
    restore_backup(str(archive_path), force=True, restore_items=restore_items)


def show_header() -> None:
    print(f"\n{COLORS.title}QQBot 管理菜单{COLORS.reset}")
    menu_items = (
        "1. 启动服务",
        "2. 启动服务（国内模式）",
        "3. 查看服务状态",
        "4. 停止服务",
        "5. 重启服务",
        "6. 查看最近日志",
        "7. 持续跟随日志",
        "8. 一键安全备份",
        "9. 自定义备份",
        "10. 验证备份",
        "11. 备份详情",
        "12. 恢复备份",
        "13. 显示访问说明",
        "0. 退出",
    )
    for item in menu_items:
        number, text = item.split(". ", 1)
        print(f"{COLORS.menu}{number}.{COLORS.reset} {text}")


def manage_loop() -> None:
    while True:
        show_header()
        choice = input("请选择操作 [0-13]: ").strip()
        if choice == "1":
            run_action("启动服务", lambda: command_up(False))
            pause()
        elif choice == "2":
            run_action("启动服务（国内模式）", lambda: command_up(True))
            pause()
        elif choice == "3":
            run_action("查看服务状态", show_status)
            pause()
        elif choice == "4":
            run_action("停止服务", command_down)
            pause()
        elif choice == "5":
            ok = run_action("停止服务", command_down)
            if ok:
                run_action("启动服务", lambda: command_up(False))
            pause()
        elif choice == "6":
            run_action("查看最近日志", lambda: choose_log_service("recent"))
            pause()
        elif choice == "7":
            run_action("持续跟随日志", lambda: choose_log_service("follow"))
            pause()
        elif choice == "8":
            run_action("一键安全备份", safe_backup_flow)
            pause()
        elif choice == "9":
            run_action("创建备份", create_backup_flow)
            pause()
        elif choice == "10":
            def verify() -> None:
                archive = select_backup_path()
                verify_backup_archive(archive)
                print_ok(f"备份校验通过：{archive}")
            run_action("验证备份", verify)
            pause()
        elif choice == "11":
            run_action("查看备份详情", lambda: show_backup_details(select_backup_path()))
            pause()
        elif choice == "12":
            run_action("恢复备份", restore_backup_flow)
            pause()
        elif choice == "13":
            print(f"\n{COLORS.title}访问说明{COLORS.reset}")
            print(ACCESS_HELP)
            pause()
        elif choice == "0":
            return
        else:
            print_error("无效选择。")
            pause()


def backup_cli(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="./scripts/backup.sh")
    parser.add_argument("archive_path", nargs="?")
    parser.add_argument("--allow-live", action="store_true")
    parser.add_argument("--keep")
    args = parser.parse_args(argv)
    create_backup(args.archive_path or "", args.allow_live, args.keep or "")
    return 0


def restore_cli(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="./scripts/restore.sh")
    parser.add_argument("archive_path")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--only", action="append", dest="restore_items")
    args = parser.parse_args(argv)
    restore_backup(args.archive_path, force=args.force, restore_items=args.restore_items or [])
    return 0


def logs_cli(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="./scripts/logs.sh", add_help=False)
    parser.add_argument("--follow", action="store_true", default=True)
    parser.add_argument("--no-follow", action="store_false", dest="follow")
    parser.add_argument("--tail")
    parser.add_argument("service", nargs="?")
    args = parser.parse_args(argv)
    command_logs(service=args.service or "", follow=args.follow, tail_lines=args.tail or "")
    return 0
