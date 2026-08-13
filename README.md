# DeepSeek Harness 一键启动器（macOS / Windows）

双击对应文件即可一键启动 `dsh web`：

| 平台 | 文件 | 说明 |
|---|---|---|
| macOS | `start-dsh.command` | 双击后自动在「终端」中运行 |
| Windows | `start-dsh.bat` | 单文件：双击后在命令提示符中运行（内嵌 PowerShell 脚本，前 3 行为启动头） |

## 行为

1. 运行 `npx @deepseek-ai/dsh web`（与官方方式一致），首次运行会自动下载依赖，需联网；
2. 启动成功后自动打开本地网页 `http://127.0.0.1:3080`；
3. **网页被手动关闭后约 2 秒内会自动重新打开**；
4. 只有以下方式才能停止（停止后网页不再自动重开）：
   - 在终端中按 `Ctrl+C`；
   - 直接关闭终端窗口。

## 环境要求

- **Node.js**（官方要求）：请到 <https://nodejs.org/> 安装（建议最新 LTS 版）。
  未安装时脚本会提示并等待按键退出。
- macOS：无需额外软件；优先使用 Chrome / Edge / Brave / Arc / Safari 之一展示网页
  （按以上顺序自动选择已安装的浏览器）。
- Windows：无需额外软件；自动使用系统默认浏览器，通过窗口标题监测网页是否被关闭。

## 常见问题

**macOS 双击提示"无法打开"（Gatekeeper 拦截）**
右键文件 →「打开」，或在终端执行：
```bash
xattr -d com.apple.quarantine start-dsh.command
```
注意：`xattr` 本身就是系统命令，直接执行即可，**不要**写成
`bash xattr -d ...`（否则会报 `xattr: cannot execute binary file`）。

**macOS 首次运行弹出自助授权提示**
系统会询问是否允许「终端」控制浏览器 / System Events，请点「允许」，
否则脚本无法检测网页是否被关闭。

**想换端口 / 地址**
用环境变量覆盖（需与 dsh 的实际启动参数一致，例如先加 `--port`）：
- macOS：在脚本中把 `npx --yes @deepseek-ai/dsh web` 改为 `npx --yes @deepseek-ai/dsh web --port 8080`，并将顶部 `URL=` 改为 `http://127.0.0.1:8080`；
- Windows：同样修改 `start-dsh.bat` 中的启动参数与 `$URL`（第 4 行起的 PowerShell 部分；前 3 行启动头请勿改动）。

**网页关闭后没有自动重开？**
- macOS：确认已授权「自动化」权限（系统设置 → 隐私与安全性 → 自动化）。
- Windows：确认使用的是 Chrome / Edge / Firefox 等主流浏览器，且页面标题仍为
  "DeepSeek Harness"。
