# AstrBot + NapCat Docker Compose 方案

这个目录提供一套最小可用的 `AstrBot + NapCat` 联合部署方案，用于把 QQ 个人号接入 AstrBot。

## 最基本操作

第一次部署，只需要按下面做：

### 1. 启动

推荐直接使用交互式入口：

```bash
python3 scripts/manage.py
```

如果你更习惯直接执行命令：

```bash
python3 scripts/up.py
```

中国大陆服务器可改用：

```bash
python3 scripts/up.py --domestic
```

### 2. 打开管理页面

- AstrBot: `http://<服务器IP>:6185`
- NapCat: `http://<服务器IP>:6099/webui`

AstrBot 默认账号密码：

- 用户名：`astrbot`
- 密码：`astrbot`

### 3. 登录 QQ

打开 NapCat WebUI，完成 QQ 扫码登录。
如果需要查看登录 Token 或二维码信息：

```bash
python3 scripts/logs.py napcat
```

### 4. 在 AstrBot 中创建 QQ 机器人

进入 AstrBot WebUI 后：

1. 打开 `机器人`
2. 创建一个 `OneBot v11` 机器人
3. 填写：
   - `启用`: 勾选
   - `反向 WebSocket 主机地址`: `0.0.0.0`
   - `反向 WebSocket 端口`: `6199`
   - `Token`: 留空，或与 NapCat 保持一致
   - `ID`: 任意，例如 `qq-private`

### 5. 验证是否接通

去 AstrBot WebUI 的 `控制台`，确认出现：

- `aiocqhttp(OneBot v11) 适配器已连接`

然后用你的 QQ 私聊机器人账号发送：

```text
/help
```

如果能收到 AstrBot 响应，说明接入成功。

## 目录

- [最基本操作](#最基本操作)
- [常用命令](#常用命令)
- [备份与恢复](#备份与恢复)
- [补充说明](#补充说明)
- [目录结构](#目录结构)
- [风险和注意事项](#风险和注意事项)
- [参考](#参考)

## 常用命令

启动：

```bash
python3 scripts/up.py
```

国内模式启动：

```bash
python3 scripts/up.py --domestic
```

查看全部日志：

```bash
python3 scripts/logs.py
```

查看 AstrBot 日志：

```bash
python3 scripts/logs.py astrbot
```

查看 NapCat 日志：

```bash
python3 scripts/logs.py napcat
```

停止：

```bash
python3 scripts/down.py
```

交互式管理：

```bash
python3 scripts/manage.py
```

## 备份与恢复

创建备份：

```bash
python3 scripts/backup.py
```

在线备份：

```bash
python3 scripts/backup.py --allow-live
```

创建备份并仅保留最近 7 份：

```bash
python3 scripts/backup.py --keep 7
```

恢复：

```bash
python3 scripts/down.py
python3 scripts/restore.py ./backups/qqbot-backup-YYYYmmdd-HHMMSS.tar.gz --force
python3 scripts/up.py
```

可选恢复部分数据：

```bash
python3 scripts/restore.py ./backups/qqbot-backup-YYYYmmdd-HHMMSS.tar.gz --force --only data
python3 scripts/restore.py ./backups/qqbot-backup-YYYYmmdd-HHMMSS.tar.gz --force --only napcat-qq
python3 scripts/restore.py ./backups/qqbot-backup-YYYYmmdd-HHMMSS.tar.gz --force --only config-files
```

默认备份内容：

- `.env`
- `compose.yaml`
- `./data`
- `./napcat/config`
- `./napcat/qq`

## 补充说明

### 这套方案适合什么

适合：

- `QQ 私人账号` 接入
- `NapCat` 作为协议端
- `AstrBot` 作为机器人框架
- 两个容器通过同一个 Docker 网络通信

不适合：

- QQ 官方机器人账号
- 企业微信、微信公众号之类的官方平台接入
- 希望完全避免协议风控的场景

### 前提条件

1. 已安装 Docker 和 Docker Compose Plugin。
2. 准备一个可扫码登录的 QQ 号。
3. 服务器能访问 Docker Hub，或你自行替换镜像源。

### 访问地址

- AstrBot WebUI: `http://<服务器IP>:6185`
- AstrBot OneBot 监听端口: `6199`
- NapCat WebUI: `http://<服务器IP>:6099/webui`

### 国内可用配置

项目提供：

- `.env.domestic.example`
- `python3 scripts/up.py --domestic`

这会把 AstrBot 镜像切到：

```env
ASTRBOT_IMAGE=m.daocloud.io/docker.io/soulter/astrbot:latest
```

NapCat 和 Watchtower 如需更稳妥地拉取，建议在宿主机 Docker daemon 上配置镜像加速器。示例文件见：

- [docker/daemon-mirror.example.json](/home/wunai/project/qqbot/docker/daemon-mirror.example.json)

### 自动更新

项目内置了 `watchtower`，按 `WATCHTOWER_SCHEDULE` 定时检查并更新已打标签的服务。

默认值：

```env
WATCHTOWER_SCHEDULE=0 0 5 * * *
```

查看日志：

```bash
python3 scripts/logs.py watchtower
```

### 持久化目录

- AstrBot 数据目录：`./data`
- NapCat 配置目录：`./napcat/config`
- QQ 登录态目录：`./napcat/qq`

重建容器不会丢失这些目录中的数据。

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
    ├── backup.py
    ├── deploy_lib.py
    ├── down.py
    ├── logs.py
    ├── manage.py
    ├── restore.py
    └── up.py
```

## 风险和注意事项

- NapCat 属于 QQ 非官方协议端，存在风控、登录失效、扫码异常等不确定性
- 不建议使用主力 QQ 号进行高频自动化操作
- 如果你把 `6099` 直接暴露到公网，请务必自行通过防火墙、反向代理或端口白名单保护 WebUI
- 当前方案保留了 AstrBot 的 `6199` 端口映射；如果你确认只在同一 Docker 网络内使用，也可以后续删掉宿主机端口映射来减少暴露面
- 自动更新虽然方便，但可能在你不关注的时间点重启机器人。生产环境建议先固定版本测试，再决定是否开启

## 参考

- AstrBot Docker 部署文档：<https://docs.astrbot.app/deploy/astrbot/docker.html>
- AstrBot 接入 NapCat 文档：<https://docs.astrbot.app/deploy/platform/aiocqhttp/napcat.html>
- NapCat-Docker 仓库：<https://github.com/NapNeko/NapCat-Docker>
- Watchtower 官方文档：<https://containrrr.dev/watchtower/>
