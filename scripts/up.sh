#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
ensure_root_dir

MODE="${1:-default}"

require_command docker

mkdir -p data napcat/config napcat/qq

if [[ ! -f .env ]]; then
  if [[ "$MODE" == "--domestic" ]]; then
    cp .env.domestic.example .env
  else
    cp .env.example .env
  fi
  sed -i "s/^NAPCAT_UID=.*/NAPCAT_UID=$(id -u)/" .env
  sed -i "s/^NAPCAT_GID=.*/NAPCAT_GID=$(id -g)/" .env
fi

docker compose up -d

cat <<'EOF'

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
EOF
