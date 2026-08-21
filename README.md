# DeepSeek Harness 一键启动器

双击启动 `dsh web`，无需命令行。

| 平台 | 文件 | 用法 |
|---|---|---|
| macOS | `start-dsh.command` | 双击运行 |
| Windows | `start-dsh.bat` | 双击运行 |

## macOS 快速开始

首次在终端执行一次（修复权限并启动）：

```bash
cd /path/to/dsh-launcher   # 输入 cd 加空格后，把 dsh-launcher 文件夹拖进终端自动填路径
xattr -d com.apple.quarantine start-dsh.command 2>/dev/null
chmod +x start-dsh.command && ./start-dsh.command
```

之后双击 `start-dsh.command` 即可。

## 说明

- 运行 `npx @deepseek-ai/dsh@<标签> web`（默认 `next`），首次需联网下载依赖；
- 自动打开 `http://127.0.0.1:3080`，网页被关闭约 4 秒后自动重开；
- Windows 版通过检测浏览器到本地服务的连接判断页面是否打开，网页在后台标签页或窗口最小化时都不会误开重复页面（支持 Chrome/Edge/Firefox 等）；
- 停止：终端中按 `Ctrl+C`，或直接关闭终端窗口；
- 依赖 Node.js（<https://nodejs.org/>），未安装时脚本会提示；
- 启动前自动检查两处更新：① 启动器自身（从 <https://github.com/Keye3Tuido/dsh-launcher> 拉取）② dsh 本体（npm 包，默认跟踪 `next` 标签的最新发布版）；均已是最新时直接启动，有更新时自动更新；
- 启动器自更新依赖 git（macOS 需安装 Xcode 命令行工具，Windows 需安装 Git for Windows）；未安装 git 或网络不可用时自动跳过自更新，不影响正常启动；
- dsh 版本默认跟踪 `next`（最新发布版，含 rc 预发布）；如需跟随稳定版 `latest`，启动前设置环境变量 `DSH_VERSION=latest`（macOS：`DSH_VERSION=latest ./start-dsh.command`；Windows：先 `set DSH_VERSION=latest` 再运行）。已安装版本记录在启动器目录的 `.dsh-version` 文件中。

## 常见问题

| 症状 | 解决 |
|---|---|
| macOS 双击提示"无法打开" | `xattr -d com.apple.quarantine start-dsh.command` |
| macOS 双击提示"没有权限" | `chmod +x start-dsh.command` |
| macOS 首次弹授权提示 | 点「允许」，否则无法检测网页是否被关闭 |
| 网页关闭后不自动重开 | macOS：检查「系统设置 → 隐私与安全性 → 自动化」授权 |
| Windows 网页关闭后不自动重开 | 确认浏览器确实打开了 `http://127.0.0.1:3080`；若自定义了端口，请同步修改脚本顶部 `URL=` |
| 想换端口 | 改脚本中 `dsh web` 启动参数与顶部 `URL=` 为对应端口 |
