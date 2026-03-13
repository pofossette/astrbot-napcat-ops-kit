#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

from deploy_lib import DeployError, require_docker_compose, subprocess_error_detail

ROOT_DIR = Path(__file__).resolve().parent.parent
DATA_DIRS = (
    ROOT_DIR / "data",
    ROOT_DIR / "napcat" / "config",
    ROOT_DIR / "napcat" / "qq",
)
STARTUP_MESSAGE = """
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


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Start QQBot services.")
    parser.add_argument(
        "--domestic",
        action="store_true",
        help="Initialize .env from .env.domestic.example when .env is missing.",
    )
    return parser.parse_args(argv)


def ensure_directories() -> None:
    for path in DATA_DIRS:
        path.mkdir(parents=True, exist_ok=True)


def update_env_ids(env_path: Path) -> None:
    uid = str(os.getuid())
    gid = str(os.getgid())
    lines: list[str] = []

    with env_path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            if raw_line.startswith("NAPCAT_UID="):
                lines.append(f"NAPCAT_UID={uid}\n")
            elif raw_line.startswith("NAPCAT_GID="):
                lines.append(f"NAPCAT_GID={gid}\n")
            else:
                lines.append(raw_line)

    with env_path.open("w", encoding="utf-8") as handle:
        handle.writelines(lines)


def initialize_env(domestic: bool) -> None:
    env_path = ROOT_DIR / ".env"
    if env_path.exists():
        return

    template_name = ".env.domestic.example" if domestic else ".env.example"
    template_path = ROOT_DIR / template_name
    shutil.copyfile(template_path, env_path)
    update_env_ids(env_path)


def run_compose_up() -> None:
    try:
        subprocess.run(
            ["docker", "compose", "up", "-d"],
            cwd=ROOT_DIR,
            text=True,
            capture_output=True,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        detail = subprocess_error_detail(exc)
        raise DeployError(f"启动容器服务失败：{detail}") from exc


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse_args(argv or sys.argv[1:])
        require_docker_compose()
        ensure_directories()
        initialize_env(domestic=args.domestic)
        run_compose_up()
        print()
        print(STARTUP_MESSAGE)
        return 0
    except DeployError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
