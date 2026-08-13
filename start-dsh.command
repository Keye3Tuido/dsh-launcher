#!/bin/bash
# ============================================================
#  DeepSeek Harness (dsh web) 一键启动 — macOS
#  用法：双击本文件（start-dsh.command）即可
#  行为：
#    - 启动 dsh web 并自动打开本地网页 http://127.0.0.1:3080
#    - 网页被手动关闭后，约 2 秒内自动重新打开
#    - 按 Ctrl+C 或直接关闭本终端窗口，即可停止程序
#  自定义地址：DSH_URL="http://127.0.0.1:8080" ./start-dsh.command
# ============================================================
set -u
cd "$(dirname "$0")"

URL="${DSH_URL:-http://127.0.0.1:3080}"
WATCH_INTERVAL=2

# ---------- 环境检查 ----------
if ! command -v node >/dev/null 2>&1; then
  echo "✗ 未检测到 Node.js，无法运行 dsh。"
  echo "  请先到 https://nodejs.org/ 安装 Node.js 后重试。"
  echo ""
  read -r -p "按回车键退出..."
  exit 1
fi

# ---------- 选择用于展示网页的浏览器（优先可监控标签页的浏览器）----------
CANDIDATES=("Google Chrome" "Microsoft Edge" "Brave Browser" "Arc" "Chromium" "Opera" "Safari")

app_installed() { [ -d "/Applications/$1.app" ] || [ -d "$HOME/Applications/$1.app" ]; }

TARGET_BROWSER="Safari"
for app in "${CANDIDATES[@]}"; do
  if app_installed "$app"; then TARGET_BROWSER="$app"; break; fi
done

# ---------- 浏览器标签检测 ----------
# 返回该 URL 的标签数量；若浏览器未运行则返回 "?"（视为正在打开/未知，避免重复开窗）
tab_count() {
  local app="$1" cnt
  cnt=$(osascript 2>/dev/null <<EOF
set prefix to "$URL"
tell application "System Events"
  if not ((name of processes) contains "$app") then return "?"
end tell
set n to 0
tell application "$app"
  repeat with w in windows
    set tabList to tabs of w
    repeat with t in tabList
      if ((URL of t) as text) starts with prefix then set n to n + 1
    end repeat
  end repeat
end tell
return n
EOF
)
  case "$cnt" in
    ''|*[!0-9]*) echo "?" ;;
    *) echo "$cnt" ;;
  esac
}

open_page() {
  if ! open -a "$TARGET_BROWSER" "$URL" 2>/dev/null; then
    open "$URL" # 兜底：用系统默认浏览器
  fi
}

# 关闭指向该 URL 的旧标签（避免残留标签指向已停止的服务）
close_page_tabs() {
  local app="$1"
  osascript >/dev/null 2>&1 <<EOF
set prefix to "$URL"
tell application "System Events"
  if not ((name of processes) contains "$app") then return
end tell
tell application "$app"
  repeat with w in windows
    set tabList to tabs of w
    repeat with t in tabList
      if ((URL of t) as text) starts with prefix then close t
    end repeat
  end repeat
end tell
EOF
}

# ---------- 启动 dsh web ----------
echo "================================================"
echo "  DeepSeek Harness 一键启动（dsh web）"
echo "================================================"
echo "正在启动 dsh web（首次运行需下载依赖，请耐心等待）..."

# 防止网络/代理挂起时 npm 永久卡住：单次请求 2 分钟超时，最多重试 3 次
export npm_config_fetch_timeout=120000
export npm_config_fetch_retries=3
export npm_config_fetch_retry_maxtimeout=60000

npx --yes @deepseek-ai/dsh web &
DSH_PID=$!

CLEANED=0
cleanup() {
  if kill -0 "$DSH_PID" 2>/dev/null; then
    kill "$DSH_PID" 2>/dev/null
    for _ in $(seq 1 10); do
      kill -0 "$DSH_PID" 2>/dev/null || break
      sleep 0.2
    done
    kill -9 "$DSH_PID" 2>/dev/null
  fi
  if [ "$CLEANED" -eq 0 ]; then
    CLEANED=1
    echo ""
    echo "dsh 已停止，网页不再自动重开。"
  fi
}
trap cleanup INT TERM HUP EXIT

# ---------- 等待服务就绪 ----------
# 首次运行需下载大量依赖，最多等 15 分钟；期间每 30 秒提示一次进度
READY=0
WAITED=0
for _ in $(seq 1 900); do
  kill -0 "$DSH_PID" 2>/dev/null || break
  if curl -s -o /dev/null --max-time 2 "$URL"; then READY=1; break; fi
  WAITED=$((WAITED + 1))
  if [ $((WAITED % 30)) -eq 0 ]; then
    echo "  ... 仍在启动中（已等待 ${WAITED}s；首次运行需下载大量依赖）"
  fi
  sleep 1
done

if [ "$READY" -ne 1 ]; then
  echo "✗ dsh 启动失败，上方为它的输出。"
  if kill -0 "$DSH_PID" 2>/dev/null; then
    echo "  npx 进程仍在运行但服务一直未就绪；若长时间无输出，可能是网络/代理导致下载挂起。"
    echo "  可先退出并手动运行以下命令查看具体错误：npx --yes @deepseek-ai/dsh web"
  fi
  wait "$DSH_PID" 2>/dev/null
  exit 1
fi

echo ""
echo "✔ dsh 已运行：${URL}（浏览器：${TARGET_BROWSER}）"
echo "  网页被手动关闭后会自动重新打开；"
echo "  按 Ctrl+C 或关闭本终端窗口即可停止程序。"
echo ""

# ---------- 首次打开网页（先清掉旧标签，避免指向已停止的服务） ----------
close_page_tabs "$TARGET_BROWSER"
echo "正在打开网页..."
open_page

# ---------- 守护循环：网页被关就重开，dsh 退出就结束 ----------
UNKNOWN_STREAK=0
while kill -0 "$DSH_PID" 2>/dev/null; do
  sleep "$WATCH_INTERVAL"
  kill -0 "$DSH_PID" 2>/dev/null || break
  CNT=$(tab_count "$TARGET_BROWSER")
  if [ "$CNT" = "0" ]; then
    echo "[$(date +%H:%M:%S)] 检测到网页已被关闭，自动重新打开..."
    open_page
    UNKNOWN_STREAK=0
  elif [ "$CNT" = "?" ]; then
    UNKNOWN_STREAK=$((UNKNOWN_STREAK + 1))
    if [ "$UNKNOWN_STREAK" -ge 10 ]; then
      echo "[$(date +%H:%M:%S)] 浏览器长时间无响应，重新打开..."
      open_page
      UNKNOWN_STREAK=0
    fi
  else
    UNKNOWN_STREAK=0
  fi
done

echo ""
echo "dsh 进程已退出，程序结束。"
