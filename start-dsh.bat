@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-Content -LiteralPath '%~f0' | Select-Object -Skip 3) -join [Environment]::NewLine | Set-Content -LiteralPath $env:TEMP\dshenv-launcher.ps1 -Encoding UTF8; & $env:TEMP\dshenv-launcher.ps1; Remove-Item $env:TEMP\dshenv-launcher.ps1 -ErrorAction SilentlyContinue" & exit /b
# ============================================================
#  DeepSeek Harness (dsh web) one-click launcher - Windows
#  Single file: the first 3 lines are the batch launcher that
#  runs everything below with PowerShell. Keep them unchanged.
#  Behavior:
#    - Starts "dsh web" and opens http://127.0.0.1:3080
#    - Reopens the page within ~2s if the user closes it
#    - Stop with Ctrl+C or by closing this console window
# ============================================================
$ErrorActionPreference = "Continue"

$URL             = if ($env:DSH_URL) { $env:DSH_URL } else { "http://127.0.0.1:3080" }
$WatchInterval   = 2
# First run downloads hundreds of MB of dependencies; allow up to 15 minutes.
$ReadyTimeoutSec = 900

# ---------- Enumerate visible window titles (skip console windows) ----------
# A tiny C# helper is the most reliable way. On some machines a broken
# LIB/INCLUDE environment makes Add-Type fail, so clear them temporarily
# and fall back to a process-title scan if compilation still fails.
$savedLib     = $env:LIB
$savedInclude = $env:INCLUDE
$env:LIB      = ""
$env:INCLUDE  = ""
$hasWinEnum   = $false
try {
  Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class WinEnum {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] private static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr h);

  public static bool HasMatching(string[] needles) {
    bool found = false;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h)) return true;
      var cls = new StringBuilder(64);
      GetClassName(h, cls, 64);
      var c = cls.ToString();
      if (c == "ConsoleWindowClass" || c == "CASCADIA_HOSTING_WINDOW_CLASS") return true;
      var sb = new StringBuilder(512);
      GetWindowText(h, sb, 512);
      var t = sb.ToString().ToLowerInvariant();
      foreach (var n in needles) {
        if (n.Length > 0 && t.Contains(n.ToLowerInvariant())) { found = true; return false; }
      }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
"@ -IgnoreWarnings -ErrorAction Stop
  $hasWinEnum = $true
} catch {
  Write-Host "  (window-title helper could not be compiled, using fallback detection)" -ForegroundColor Yellow
} finally {
  $env:LIB     = $savedLib
  $env:INCLUDE = $savedInclude
}

function Test-PageWindow([string[]]$needles) {
  if ($hasWinEnum) { return [WinEnum]::HasMatching($needles) }
  # Fallback: scan main window titles of running processes
  $skip = @("cmd", "powershell", "pwsh", "conhost", "WindowsTerminal", "explorer")
  foreach ($p in Get-Process) {
    try {
      if ($skip -contains $p.ProcessName) { continue }
      $t = $p.MainWindowTitle
      if (-not $t) { continue }
      $low = $t.ToLowerInvariant()
      foreach ($n in $needles) {
        if ($low.Contains($n.ToLowerInvariant())) { return $true }
      }
    } catch {}
  }
  return $false
}

# ---------- Environment check ----------
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Host "[X] Node.js not found. Install it first: https://nodejs.org/" -ForegroundColor Red
  Write-Host ""
  Read-Host "Press Enter to exit"
  exit 1
}

Write-Host "================================================"
Write-Host "  DeepSeek Harness one-click launcher (dsh web)"
Write-Host "================================================"
Write-Host "Starting dsh web (first run downloads packages, please wait)..."

# Keep npm from hanging forever on a stalled proxy/download:
# time out each fetch after 2 minutes and retry up to 3 times.
$env:npm_config_fetch_timeout         = "120000"
$env:npm_config_fetch_retries         = "3"
$env:npm_config_fetch_retry_maxtimeout = "60000"

$proc = Start-Process -FilePath "npx.cmd" -ArgumentList @("--yes", "@deepseek-ai/dsh", "web") -PassThru -NoNewWindow

try {
  # ---------- Wait until the server is ready ----------
  # dsh is ready when the local URL answers. While the npx process is still
  # alive, downloading/installing may take several minutes on first run, so
  # keep waiting (with progress hints) instead of giving up early.
  $ready    = $false
  $started  = Get-Date
  $deadline = $started.AddSeconds($ReadyTimeoutSec)
  $nextHint = $started.AddSeconds(30)
  while (-not $proc.HasExited -and (Get-Date) -lt $deadline) {
    try {
      Invoke-WebRequest -Uri $URL -UseBasicParsing -TimeoutSec 3 | Out-Null
      $ready = $true
      break
    } catch {}
    if ((Get-Date) -ge $nextHint) {
      $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds)
      Write-Host "  ... still starting (waited ${elapsed}s; first run downloads many packages)" -ForegroundColor Yellow
      $nextHint = (Get-Date).AddSeconds(30)
    }
    Start-Sleep -Seconds 1
  }

  if (-not $ready) {
    Write-Host ""
    Write-Host "[X] dsh failed to start (see output above)." -ForegroundColor Red
    if ($proc.HasExited) {
      Write-Host "    The npx process exited by itself - check the error above." -ForegroundColor Yellow
    } else {
      Write-Host "    npx is still running but the server never answered." -ForegroundColor Yellow
    }
    $activeProxy = if ($env:HTTPS_PROXY) { $env:HTTPS_PROXY } else { $env:HTTP_PROXY }
    if ($activeProxy) {
      Write-Host "    A proxy is active ($activeProxy). If downloads hang, disable it" -ForegroundColor Yellow
      Write-Host "    or run this command by hand to see the error:" -ForegroundColor Yellow
      Write-Host "      npx --yes @deepseek-ai/dsh web" -ForegroundColor Yellow
    }
    Read-Host "Press Enter to exit"
    exit 1
  }

  $needles = @("deepseek harness", "127.0.0.1")

  Write-Host ""
  Write-Host "[OK] dsh is running: $URL"
  Write-Host "     The page reopens automatically if you close it."
  Write-Host "     Press Ctrl+C or close this window to stop."
  Write-Host ""

  $lastOpen = [DateTime]::MinValue
  if (-not (Test-PageWindow $needles)) {
    Write-Host "Opening the web page..."
    Start-Process $URL
    $lastOpen = Get-Date
  }

  # ---------- Watchdog: reopen the page whenever it is closed ----------
  while (-not $proc.HasExited) {
    Start-Sleep -Seconds $WatchInterval
    if (-not $proc.HasExited) {
      if (-not (Test-PageWindow $needles) -and ((Get-Date) - $lastOpen).TotalSeconds -ge 5) {
        Write-Host "[$(Get-Date -Format HH:mm:ss)] Page was closed, reopening..."
        Start-Process $URL
        $lastOpen = Get-Date
      }
    }
  }

  Write-Host ""
  Write-Host "dsh has exited. Bye."
}
finally {
  if ($proc -and -not $proc.HasExited) {
    & taskkill /PID $proc.Id /T /F 2>$null | Out-Null
  }
}

