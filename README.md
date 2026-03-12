# AstrBot + NapCat Docker Compose 方案

这个目录提供一套最小可用的 `AstrBot + NapCat` 联合部署方案，用于把 QQ 个人号接入 AstrBot。

## 首次使用

如果你是第一次部署，直接按下面顺序执行，不需要先看后面的细节。

### 1. 启动容器

中国大陆服务器建议直接用国内模式：

```bash
chmod +x scripts/*.sh
./scripts/up.sh --domestic
```

如果你的网络本身可以正常拉 Docker Hub，也可以用默认模式：

```bash
chmod +x scripts/*.sh
./scripts/up.sh
```

如果你希望用一个交互式入口来完成启动、停止、备份、恢复和查看日志，也可以直接运行：

```bash
chmod +x scripts/*.sh
./scripts/manage.sh
```

### 2. 登录 NapCat

打开：

- `http://<服务器IP>:6099/webui`

如果需要查看登录 Token 或二维码信息，执行：

```bash
./scripts/logs.sh napcat
```

然后在 NapCat WebUI 中完成 QQ 私人号扫码登录。

### 3. 登录 AstrBot

打开：

- `http://<服务器IP>:6185`

默认账号密码：

- 用户名：`astrbot`
- 密码：`astrbot`

### 4. 在 AstrBot 中创建 QQ 机器人

进入 AstrBot WebUI 后：

1. 打开 `机器人`
2. 创建一个 `OneBot v11` 机器人
3. 填写：
   - `启用`: 勾选
   - `反向 WebSocket 主机地址`: `0.0.0.0`
   - `反向 WebSocket 端口`: `6199`
   - `Token`: 留空，或与 NapCat 侧保持一致
   - `ID`: 任意，例如 `qq-private`

保存后，AstrBot 会开始监听 `6199` 端口。

### 5. 在 NapCat 中添加反向 WebSocket

进入 NapCat WebUI：

1. 打开 `网络配置`
2. 新建 `WebSockets客户端`
3. 填写：
   - `启用`: 勾选
   - `URL`: `ws://astrbot:6199/ws`
   - `消息格式`: `Array`
   - `心跳间隔`: `5000`
   - `重连间隔`: `5000`
   - `Token`: 如 AstrBot 配了 Token，这里填同一个

注意：

- URL 末尾必须保留 `/ws`
- 这里不要写 `0.0.0.0`

### 6. 验证是否接通

去 AstrBot WebUI 的 `控制台`，确认出现：

- `aiocqhttp(OneBot v11) 适配器已连接`

然后用你的 QQ 私聊机器人账号发送：

```text
/help
```

如果能收到 AstrBot 响应，说明私人 QQ 号 bot 已接入成功。

## 目录结构

```text
.
├── .env.example
├── compose.yaml
├── docker
│   └── daemon-mirror.example.json
├── data
├── napcat
│   ├── config
│   └── qq
└── scripts
    ├── backup.sh
    ├── down.sh
    ├── logs.sh
    ├── manage.sh
    ├── restore.sh
    └── up.sh
```

## 前提

1. 已安装 Docker 和 Docker Compose Plugin。
2. 准备一个可扫码登录的 QQ 号。
3. 服务器能访问 Docker Hub，或你自行替换镜像源。

## 这套方案适合什么场景

这套配置针对的是：

- `QQ 私人账号` 接入
- `NapCat` 作为协议端
- `AstrBot` 作为机器人框架
- 两个容器通过同一个 Docker 网络通信

不适用于：

- QQ 官方机器人账号
- 企业微信、微信公众号之类的官方平台接入
- 希望完全避免协议风控的场景

## 启动

首次启动：

```bash
chmod +x scripts/*.sh
./scripts/up.sh
```

脚本会自动：

1. 创建持久化目录。
2. 复制 `.env.example` 为 `.env`。
3. 自动写入当前用户的 `uid/gid`。
4. 执行 `docker compose up -d`。

如果你在中国大陆服务器部署，推荐首次直接使用国内模式：

```bash
./scripts/up.sh --domestic
```

这会优先用 `.env.domestic.example` 生成 `.env`。

如果你不想记多个命令，也可以直接运行：

```bash
./scripts/manage.sh
```

它会提供交互式菜单，集中处理：

- 启动服务
- 停止服务
- 查看状态
- 查看日志
- 创建备份
- 恢复备份

## 访问地址

- AstrBot WebUI: `http://<服务器IP>:6185`
- AstrBot OneBot 监听端口: `6199`
- NapCat WebUI: `http://<服务器IP>:6099/webui`

AstrBot 默认账号密码：

- 用户名：`astrbot`
- 密码：`astrbot`

## 自动更新

项目已内置 `watchtower` 容器，会按 `WATCHTOWER_SCHEDULE` 定时检查并更新打了标签的服务。

默认值：

```env
WATCHTOWER_SCHEDULE=0 0 5 * * *
```

含义：

- 每天 `05:00:00` 检查一次更新
- 只更新 `astrbot` 和 `napcat`
- 更新后自动清理旧镜像

查看自动更新日志：

```bash
./scripts/logs.sh watchtower
```

注意：

- `watchtower` 会直接重建容器，升级时机器人会短暂中断。
- 该项目官方站点当前仍提供 Watchtower 文档，但生态里已经有“维护状态不积极”的讨论，所以更适合个人或轻量场景。如果你更重视稳定性，建议保留它做通知用途，手动升级业务容器。

## 国内可用配置

国内部署要分两层处理。

### 1. 项目内镜像覆盖

AstrBot 官方文档明确给出了大陆网络可用的 DaoCloud 镜像地址，因此我已经提供了：

- `.env.domestic.example`
- `./scripts/up.sh --domestic`

这会把 AstrBot 镜像切到：

```env
ASTRBOT_IMAGE=m.daocloud.io/docker.io/soulter/astrbot:latest
```

### 2. 宿主机 Docker 加速

NapCat 和 Watchtower 仍然默认从 Docker Hub 拉取。更稳妥的做法是在宿主机 Docker daemon 上配置镜像加速器。

示例文件见：

- [docker/daemon-mirror.example.json](/home/wunai/project/qqbot/docker/daemon-mirror.example.json)

你可以把其中地址替换成你自己的可用镜像加速器，然后写入宿主机：

```bash
sudo mkdir -p /etc/docker
sudo cp docker/daemon-mirror.example.json /etc/docker/daemon.json
sudo systemctl restart docker
```

完成后再执行：

```bash
docker pull mlikiowa/napcat-docker:latest
docker pull containrrr/watchtower:latest
```

如果你已经有自建 Harbor、阿里云个人镜像仓库或其他代理仓库，也可以直接把 `.env` 改成：

```env
NAPCAT_IMAGE=<你的镜像地址>/mlikiowa/napcat-docker:latest
WATCHTOWER_IMAGE=<你的镜像地址>/containrrr/watchtower:latest
```

## 配置顺序

### 1. 登录 NapCat

执行：

```bash
./scripts/logs.sh napcat
```

日志里会出现 NapCat WebUI 的登录信息和二维码。打开 WebUI 后，完成 QQ 扫码登录。

根据 NapCat-Docker 仓库说明，默认 WebUI 登录 Token 可从日志中查看；历史文档里常见默认值为 `napcat`，但实际以当前容器日志输出为准，不要硬编码假设。

### 2. 在 AstrBot 中创建 QQ 机器人

进入 AstrBot WebUI 后：

1. 打开 `机器人`。
2. 创建一个 `OneBot v11` 机器人。
3. 填写以下关键项：
   - `启用`: 勾选
   - `反向 WebSocket 主机地址`: `0.0.0.0`
   - `反向 WebSocket 端口`: `6199`
   - `Token`: 留空，或与 NapCat 侧保持一致
   - `ID`: 任意，例如 `qq-private`

保存后，AstrBot 会开始监听容器内的 `6199` 端口。

### 3. 在 NapCat 中添加反向 WebSocket

进入 NapCat WebUI：

1. 打开 `网络配置`。
2. 新建 `WebSockets客户端`。
3. 填写：
   - `启用`: 勾选
   - `URL`: `ws://astrbot:6199/ws`
   - `消息格式`: `Array`
   - `心跳间隔`: `5000`
   - `重连间隔`: `5000`
   - `Token`: 如 AstrBot 配了 Token，这里填同一个

说明：

- `astrbot` 是 Compose 内的服务名，两个容器在同一个 Docker 网络里可以直接互通。
- URL 末尾必须保留 `/ws`。
- 这里不要写 `0.0.0.0`。
- 如果 AstrBot 和 NapCat 不在同一个 Docker 网络，需要改成内网 IP 或公网 IP，但这不是当前方案推荐做法。

### 4. 配置 AstrBot 管理员

在 AstrBot 的平台配置里，把 `管理员 ID` 设置成你的 QQ 号，然后保存。

### 5. 验证是否真正接通

去 AstrBot WebUI 的 `控制台`，你应该看到类似下面的成功日志：

- `aiocqhttp(OneBot v11) 适配器已连接`

如果看到的是连接关闭或超时：

1. 检查 AstrBot 里监听端口是否真的是 `6199`
2. 检查 NapCat URL 是否是 `ws://astrbot:6199/ws`
3. 检查 URL 末尾是否保留 `/ws`
4. 检查 NapCat 侧是否把消息格式设成了 `Array`
5. 检查 Token 是否两边一致或都为空

接通后，使用 `私聊` 对你的 QQ 机器人账号发送：

```text
/help
```

这是 AstrBot 官方文档给出的最终验证方式，更符合“私人 QQ 号 bot”场景。

## 常用命令

启动：

```bash
./scripts/up.sh
```

国内模式启动：

```bash
./scripts/up.sh --domestic
```

查看全部日志：

```bash
./scripts/logs.sh
```

查看 AstrBot 日志：

```bash
./scripts/logs.sh astrbot
```

查看 NapCat 日志：

```bash
./scripts/logs.sh napcat
```

创建备份：

```bash
./scripts/backup.sh
```

在线备份（不停止容器）：

```bash
./scripts/backup.sh --allow-live
```

创建备份并仅保留最近 7 份：

```bash
./scripts/backup.sh --keep 7
```

从备份恢复：

```bash
./scripts/down.sh
./scripts/restore.sh ./backups/qqbot-backup-YYYYmmdd-HHMMSS.tar.gz --force
./scripts/up.sh
```

停止：

```bash
./scripts/down.sh
```

## 持久化说明

- AstrBot 数据目录：`./data`
- NapCat 配置目录：`./napcat/config`
- QQ 登录态目录：`./napcat/qq`

重建容器不会丢失这些目录中的数据。

## 备份与恢复

项目内的持久化数据都落在宿主机目录，因此备份不需要导出容器，只需要打包这些目录和当前配置文件。

默认备份命令：

```bash
./scripts/backup.sh
```

如果容器仍在运行，脚本默认会中止并提示先停服务，以避免 SQLite 或运行时文件拿到不一致快照。

默认会生成：

- `./backups/qqbot-backup-时间戳.tar.gz`

备份内容包括：

- `.env`
- `compose.yaml`
- `./data`
- `./napcat/config`
- `./napcat/qq`

如果你想自定义输出文件名，也可以直接传路径：

```bash
./scripts/backup.sh /tmp/qqbot-prod-backup.tar.gz
```

如果你确认接受在线备份的风险，可以显式加上：

```bash
./scripts/backup.sh --allow-live
```

如果你希望自动清理历史备份，可以加上保留数量：

```bash
./scripts/backup.sh --keep 7
```

这会在 `./backups` 下仅保留最近 7 份默认命名的备份文件。

恢复前建议先停服务，避免运行中的容器继续写入数据：

```bash
./scripts/down.sh
./scripts/restore.sh ./backups/qqbot-backup-YYYYmmdd-HHMMSS.tar.gz --force
./scripts/up.sh
```

如果你只想恢复某一部分数据，也可以使用 `--only`：

```bash
./scripts/restore.sh ./backups/qqbot-backup-YYYYmmdd-HHMMSS.tar.gz --force --only data
./scripts/restore.sh ./backups/qqbot-backup-YYYYmmdd-HHMMSS.tar.gz --force --only napcat-qq
./scripts/restore.sh ./backups/qqbot-backup-YYYYmmdd-HHMMSS.tar.gz --force --only config-files
```

注意：

- `restore.sh` 会先校验备份包结构，再覆盖目标路径。
- 全量恢复会覆盖当前的 `.env`、`compose.yaml`、`data`、`napcat/config` 和 `napcat/qq`。
- 恢复不会自动保留你本地当前目录中的旧数据；如果要双保险，先手动再备份一次。
- 备份文件只包含业务数据和配置，不包含 Docker 镜像层；恢复后如本机无镜像，`./scripts/up.sh` 会重新拉取。
- 所有脚本都会先检查基础依赖，例如 `docker`、`tar`。

## 风险和注意事项

- NapCat 属于 QQ 非官方协议端，存在风控、登录失效、扫码异常等不确定性。
- 不建议使用主力 QQ 号进行高频自动化操作。
- 如果你把 `6099` 直接暴露到公网，请务必自行通过防火墙、反向代理或端口白名单保护 WebUI。
- 当前方案为了保证可用性，保留了 AstrBot 的 `6199` 端口映射；如果你确认只在同一 Docker 网络内使用，也可以后续删掉宿主机端口映射来减少暴露面。
- 自动更新虽然方便，但可能在你不关注的时间点重启机器人。生产环境建议先固定版本测试，再决定是否开启自动更新。
- 如果在中国大陆拉取镜像失败，AstrBot 可直接使用 `m.daocloud.io/docker.io/soulter/astrbot:latest`。NapCat 和 Watchtower 更建议通过宿主机 Docker 加速器或自建镜像代理解决。

## 参考

- AstrBot Docker 部署文档：<https://docs.astrbot.app/deploy/astrbot/docker.html>
- AstrBot 接入 NapCat 文档：<https://docs.astrbot.app/deploy/platform/aiocqhttp/napcat.html>
- NapCat-Docker 仓库：<https://github.com/NapNeko/NapCat-Docker>
- Watchtower 官方文档：<https://containrrr.dev/watchtower/>
