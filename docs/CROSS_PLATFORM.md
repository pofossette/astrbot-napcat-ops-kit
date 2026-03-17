# 跨平台兼容性分析文档

## 概述

当前项目设计为 Linux/Unix 环境下的 Docker Compose 部署方案，存在多处操作系统特定的依赖。本文档分析兼容性问题并提供修改建议。

---

## 核心兼容性问题

### 1. POSIX 特定系统调用 (Critical)

**位置**: `scripts/up.py:52-67`

```python
def update_env_ids(env_path: Path) -> None:
    uid = str(os.getuid())  # ❌ Windows 不存在
    gid = str(os.getgid())  # ❌ Windows 不存在
```

**影响**: 在 Windows 上运行会抛出 `AttributeError`

**解决方案**:

```python
import platform

def update_env_ids(env_path: Path) -> None:
    if platform.system() == "Windows":
        # Windows 不使用 UID/GID，使用默认值或跳过
        uid, gid = "1000", "1000"
    else:
        uid, gid = str(os.getuid()), str(os.getgid())
    # ... 其余代码
```

---

### 2. Docker Socket 路径 (Critical)

**位置**: `compose.yaml:51`

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock  # ❌ Windows 路径不同
```

**影响**: Windows 上 Docker Desktop 使用命名管道通信

**解决方案**:

```yaml
volumes:
  - ${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock
```

在 `.env` 中添加：
```env
# Linux/macOS
DOCKER_SOCKET=/var/run/docker.sock

# Windows (Docker Desktop)
DOCKER_SOCKET=//var/run/docker.sock
# 或使用命名管道（需要配置）
```

---

### 3. 文件权限和用户映射 (High)

**位置**: `compose.yaml:8-9`, `.env.example`

```env
NAPCAT_UID=1000  # ⚠️ Windows 容器中通常不需要
NAPCAT_GID=1000
```

**影响**: Windows 容器运行方式不同，UID/GID 概念不适用

**解决方案**:

在 `compose.yaml` 中添加条件：

```yaml
services:
  napcat:
    user: "${NAPCAT_USER:-}"  # Linux: "1000:1000", Windows: 留空
```

在 `up.py` 中根据平台设置：

```python
def update_env_ids(env_path: Path) -> None:
    if platform.system() == "Windows":
        # Windows 不需要用户映射
        return
    # Linux UID/GID 处理...
```

---

### 4. tar 命令依赖 (Medium)

**位置**: `scripts/deploy_lib.py:263, 351`

```python
require_command("tar")  # ⚠️ Windows 可能没有 tar 命令
```

**影响**: Windows 上可能找不到 tar 命令（虽然通常有 Git Bash 或 WSL 提供）

**解决方案**:

```python
def require_command(command: str) -> None:
    if platform.system() == "Windows" and command == "tar":
        # Windows 上使用 Python 内置 tarfile
        return
    if shutil.which(command):
        return
    raise DeployError(f"缺少依赖命令：{command}")
```

或者更好的方案是直接使用 Python 的 `tarfile` 模块，不依赖外部 tar 命令（当前代码已经在用 tarfile，这个检查是多余的）。

---

### 5. 终端颜色支持 (Low)

**位置**: `scripts/deploy_lib.py:62-73`

```python
return cls(
    reset="\033[0m",     # ⚠️ Windows 10 之前不支持
    title="\033[1;36m",
    # ...
)
```

**影响**: Windows 7/8 不支持 ANSI 颜色代码

**解决方案**:

```python
import platform
import colorama  # 跨平台颜色库

@classmethod
def for_stdout(cls) -> "Colors":
    if not sys.stdout.isatty():
        return cls()

    # Windows 需要 colorama
    if platform.system() == "Windows":
        colorama.init(autoreset=True)

    return cls(
        reset=colorama.Style.RESET_ALL if platform.system() == "Windows" else "\033[0m",
        # ...
    )
```

添加依赖：`pip install colorama`

---

### 6. 路径分隔符和行尾符 (Low)

**影响范围**: 文件操作、路径拼接

**当前状态**: 已使用 `pathlib.Path`，基本没有问题

**潜在问题**:

```python
# deploy_lib.py:346
"  ./scripts/down.sh\n"  # ❌ 错误信息中的硬编码路径
```

**解决方案**:

```python
import os
"  python3{sep}scripts{sep}down.py".format(sep=os.sep)
```

---

## 容器运行时差异

### Docker 行为差异

| 特性 | Linux | Windows (Docker Desktop) | macOS |
|------|-------|-------------------------|-------|
| 文件系统性能 | 原生 | WSL2 性能较好，原生较慢 | 原生 |
| 端口绑定 | 0.0.0.0 | 0.0.0.0 | 0.0.0.0 |
| 卷挂载 | 原生路径 | 需要共享驱动器配置 | 原生 |
| 信号处理 | 完整支持 | 有限支持 | 完整支持 |

---

## 修改优先级

### P0 - 必须修改（阻塞 Windows 运行）

1. **`os.getuid()`/`os.getgid()` 兼容性** - `scripts/up.py`
2. **Docker socket 路径** - `compose.yaml`

### P1 - 强烈建议（功能性问题）

3. **用户/组 ID 处理** - `scripts/up.py`, `compose.yaml`
4. **tar 命令依赖检查** - `scripts/deploy_lib.py`

### P2 - 建议修改（体验问题）

5. **终端颜色** - `scripts/deploy_lib.py`
6. **错误消息中的路径** - `scripts/deploy_lib.py`

---

## 推荐修改方案

### 方案 A: 完全跨平台支持

**优点**: 支持所有主流桌面操作系统
**缺点**: 代码复杂度增加，需要额外测试

**实施步骤**:
1. 添加 `platform` 检测
2. 实现平台特定逻辑
3. 添加 Windows 专用配置文件 (`.env.windows.example`)
4. 更新文档说明 Windows 特殊配置

### 方案 B: 官方支持 Linux/macOS

**优点**: 保持代码简洁，服务器环境主要是 Linux
**缺点**: Windows 用户需要 WSL

**实施步骤**:
1. 在 README 中明确说明只支持 Linux/macOS
2. 添加 Windows 用户使用 WSL 的指南
3. 添加平台检测，给出友好的错误提示

---

## 实施建议

基于项目的实际使用场景（QQ 机器人通常部署在 Linux 服务器），**推荐方案 B**：

1. **添加平台检测和早期失败**

```python
# scripts/deploy_lib.py 顶部添加

import platform

SUPPORTED_PLATFORMS = ("linux", "darwin")  # Linux, macOS

def check_platform() -> None:
    system = platform.system().lower()
    if system not in SUPPORTED_PLATFORMS:
        raise DeployError(
            f"当前平台 ({system}) 不支持。\n"
            "本项目仅支持 Linux 和 macOS。\n"
            "Windows 用户请使用 WSL (Windows Subsystem for Linux)。\n"
            "详见: https://docs.microsoft.com/en-us/windows/wsl/install"
        )

# 在各脚本的 main() 开始时调用
def main() -> int:
    check_platform()
    # ...
```

2. **更新 README.md** 添加平台说明

3. **添加 Windows + WSL 使用指南**

---

## 测试清单

修改后需要在以下环境测试：

- [ ] Ubuntu 20.04/22.04 LTS
- [ ] Debian 11/12
- [ ] CentOS 8/9
- [ ] macOS 12+ (Intel/Apple Silicon)
- [ ] Windows 11 + WSL2 (Ubuntu)
- [ ] Docker Desktop (各平台)

---

## 参考资料

- [Python `platform` 模块文档](https://docs.python.org/3/library/platform.html)
- [Docker Compose 环境变量](https://docs.docker.com/compose/environment-variables/)
- [WSL 安装指南](https://docs.microsoft.com/en-us/windows/wsl/install)
- [跨平台 Python 开发最佳实践](https://realpython.com/python-platform-tools/)
