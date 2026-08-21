@echo off
setlocal
set "DSH_LAUNCHER_DIR=%~dp0" & set "DSH_LAUNCHER_BAT=%~f0" & powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-Content -LiteralPath '%~f0' | Select-Object -Skip 3) -join [Environment]::NewLine | Set-Content -LiteralPath $env:TEMP\dshenv-launcher-$PID.ps1 -Encoding UTF8; & $env:TEMP\dshenv-launcher-$PID.ps1; Remove-Item $env:TEMP\dshenv-launcher-$PID.ps1 -ErrorAction SilentlyContinue" & exit /b
# ============================================================
#  DeepSeek Harness (dsh web) one-click launcher - Windows
#  Single file: the first 3 lines are the batch launcher that
#  runs everything below with PowerShell. Line 3 also passes the
#  launcher path to PowerShell and uses a per-invocation temp name
#  so the script can restart itself after a self-update.
#  Behavior:
#    - Starts "dsh web" and opens http://127.0.0.1:3080
#    - Reopens the page within ~4s if the user closes it
#    - Detects the page by its live connection to the server, so a
#      background tab or a minimized window never opens a duplicate
#    - Stop with Ctrl+C or by closing this console window
# ============================================================
$ErrorActionPreference = "Continue"

$URL             = if ($env:DSH_URL) { $env:DSH_URL } else { "http://127.0.0.1:3080" }
$WatchInterval   = 2
# First run downloads hundreds of MB of dependencies; allow up to 15 minutes.
$ReadyTimeoutSec = 900

# ---------- Self-update check (pull the latest launcher from GitHub) ----------
# Repository: https://github.com/Keye3Tuido/dsh-launcher
# Runs before launch; skips entirely when already up to date, when git or the
# remote is missing, or when the network is unreachable.
$LauncherDir = if ($env:DSH_LAUNCHER_DIR) { $env:DSH_LAUNCHER_DIR.TrimEnd('\') } else { (Split-Path -Parent $PSCommandPath) }
$LauncherBat = if ($env:DSH_LAUNCHER_BAT) { $env:DSH_LAUNCHER_BAT } else { $null }

function Test-SelfUpdate {
  if ($env:DSH_UPDATE_DONE -eq "1") { return }   # just restarted after an update
  $git = Get-Command git -ErrorAction SilentlyContinue
  if (-not $git) { Write-Host "  (git not found; skipping launcher self-update)"; return }
  if (-not (Test-Path (Join-Path $LauncherDir ".git"))) { Write-Host "  (not a git repository; skipping launcher self-update)"; return }

  Push-Location $LauncherDir
  try {
    $origin = (& git remote get-url origin 2>$null)
    if (-not $origin) { Write-Host "  (no git remote 'origin'; skipping launcher self-update)"; return }

    Write-Host "Checking for launcher updates..."
    $env:GIT_TERMINAL_PROMPT      = "0"
    $env:GIT_HTTP_LOW_SPEED_LIMIT = "1000"
    $env:GIT_HTTP_LOW_SPEED_TIME  = "30"
    & git fetch --quiet origin 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host "  (cannot reach the repository; skipping update)"; return }

    $branch     = (& git rev-parse --abbrev-ref HEAD 2>$null)
    if (-not $branch) { $branch = "master" }
    $localHead  = (& git rev-parse HEAD 2>$null)
    $remoteHead = (& git rev-parse ("origin/" + $branch) 2>$null)
    if (-not $localHead -or -not $remoteHead) { Write-Host "  (cannot determine versions; skipping update)"; return }

    if ($localHead -eq $remoteHead) {
      Write-Host "[OK] Launcher is already up to date ($($localHead.Substring(0,7))), no update needed."
      return
    }

    Write-Host "Update found: local $($localHead.Substring(0,7)) -> remote $($remoteHead.Substring(0,7))"
    Write-Host "Updating..."
    & git pull --ff-only --quiet origin $branch 2>$null
    if ($LASTEXITCODE -ne 0) {
      Write-Host "[X] Auto-update failed (uncommitted local changes may block it)."
      Write-Host "    Launching with the current version. Manual fix:"
      Write-Host "      git -C `"$LauncherDir`" pull --ff-only"
      return
    }

    Write-Host "[OK] Updated. Restarting the launcher with the new version..."
    $env:DSH_UPDATE_DONE = "1"
    if ($LauncherBat) {
      try {
        & cmd /c "`"$LauncherBat`""
        exit 0
      } catch {
        Write-Host "  (restart failed; the update applies from the next launch)"
      }
    } else {
      Write-Host "  (launcher path unknown; the update applies from the next launch)"
    }
  } finally {
    Pop-Location
  }
}
Test-SelfUpdate

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

  // A minimized window still has WS_VISIBLE, so the enumeration above sees it,
  // but Chromium defers rendering its UI tree while minimized, so UI Automation
  // cannot reliably list its tabs. Expose IsIconic so the watchdog can treat a
  // minimized browser window as "cannot tell" instead of "page closed".
  [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr h);
  public static bool IsMinimized(IntPtr h) { return IsIconic(h); }

  [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static System.Collections.Generic.List<IntPtr> GetWindowsByProcess(string[] processNames) {
    var list = new System.Collections.Generic.List<IntPtr>();
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h)) return true;
      uint pid; GetWindowThreadProcessId(h, out pid);
      string pname = null;
      try { pname = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch { return true; }
      if (pname == null) return true;
      foreach (var n in processNames) {
        if (string.Equals(pname, n, StringComparison.OrdinalIgnoreCase)) { list.Add(h); return true; }
      }
      return true;
    }, IntPtr.Zero);
    return list;
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

# ---------- Load UI Automation (reads every browser tab, incl. background) ----------
$hasUia = $false
try {
  Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
  Add-Type -AssemblyName UIAutomationTypes  -ErrorAction Stop
  $hasUia = $true
} catch {
  Write-Host "  (UI Automation unavailable, background-tab detection limited)" -ForegroundColor Yellow
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

# ---------- Detect the dsh tab even when it is not the active tab ----------
# Window titles only reflect the ACTIVE tab. To see background tabs we use
# UI Automation: Chromium browsers (Edge/Chrome/Brave/Opera/Vivaldi) expose
# every tab as a "TabItem" element whose Name is the page title, so the dsh
# tab is found no matter which tab is active. (Reading browser session files
# instead proved unreliable: stale files survive long after tabs are closed.)
# Return values: $true = tab found, $false = confirmed absent, $null = unknown
function Test-UiaBrowserTab([string[]]$needles) {
  if (-not $hasWinEnum -or -not $hasUia) { return $null }
  $chromium = @("msedge", "chrome", "brave", "opera", "vivaldi")
  $hwnds = [WinEnum]::GetWindowsByProcess($chromium)
  if (-not $hwnds -or $hwnds.Count -eq 0) {
    # No Chromium window: a dsh tab cannot exist there. If the user may be
    # browsing with something we cannot inspect (e.g. Firefox), say unknown.
    if (Get-Process -Name "firefox" -ErrorAction SilentlyContinue) { return $null }
    return $false
  }
  $inspected = $false
  $minimized = $false
  foreach ($h in $hwnds) {
    # A minimized Chromium window defers its UI tree, so FindAll can return
    # zero TabItems even though the dsh tab is still open in the background.
    # Skip minimized windows and remember they were seen; if we never find the
    # tab elsewhere, report "cannot tell" ($null) so the watchdog does not pop
    # an extra window while the browser sits in the taskbar.
    if ([WinEnum]::IsMinimized($h)) { $minimized = $true; continue }
    try {
      $root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
      if (-not $root) { continue }
      $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::TabItem)
      $tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
      $inspected = $true
      for ($i = 0; $i -lt $tabs.Count; $i++) {
        $name = $tabs.Item($i).Current.Name
        if (-not $name) { continue }
        $low = $name.ToLowerInvariant()
        foreach ($n in $needles) {
          if ($low.Contains($n.ToLowerInvariant())) { return $true }
        }
      }
    } catch {
      # Window vanished or its UIA tree is unavailable: treat as unknown.
    }
  }
  if (-not $inspected -or $minimized) { return $null } else { return $false }
}

# ---------- Fallback detection: live TCP connection to the dsh server ----------
# A loaded dsh page keeps a WebSocket (plus HTTP keep-alive) connection open to
# the local server. This signal is independent of window minimization and
# background tabs, so it backs up UI Automation when the window cannot be read.
# It only counts ESTABLISHED sockets: a CLOSE_WAIT/FIN_WAIT socket is NOT
# treated as "closed", because that also appears when the browser merely freezes
# a background tab (Edge sleeping tabs) or on a brief reconnect — reopening the
# page then would be a false positive. Navigation away is instead caught by the
# UIA title check, which runs first.
# Return values: $true = a browser holds a live connection (page open),
#                $false = no browser connection (page closed),
#                $null = probe unavailable, cannot tell.
function Test-ServerConnection {
  $uri = $null
  try { $uri = [Uri]$URL } catch { return $null }
  if (-not $uri -or -not $uri.Port) { return $null }
  $port = $uri.Port
  $browsers = @("msedge", "chrome", "brave", "opera", "vivaldi", "firefox")

  # netstat works for normal (non-elevated) users and needs no extra module,
  # unlike Get-NetTCPConnection which can silently return nothing in some
  # restricted environments.
  $netstat = $null
  try { $netstat = @(netstat -ano 2>$null) } catch { return $null }
  if (-not $netstat -or $netstat.Count -eq 0) { return $null }

  $estOwners = @{}
  foreach ($line in $netstat) {
    # Client side of a live connection to the page: TCP <local> <remote>:<port> ESTABLISHED <pid>
    if ($line -match ('^\s*TCP\s+\S+:\d+\s+\S+:' + $port + '\s+ESTABLISHED\s+(\d+)')) {
      $estOwners[[int]$Matches[1]] = $true
    }
  }
  if ($estOwners.Count -eq 0) { return $false }   # no live connection to the page

  foreach ($owner in $estOwners.Keys) {
    try {
      $p = Get-Process -Id $owner -ErrorAction Stop
      if ($browsers -contains $p.ProcessName) { return $true }
    } catch {}
  }
  return $false   # connections exist, but none from a recognized browser
}

function Test-DshPageOpen {
  # Three states:
  #   $true  -> a dsh window/tab exists, do nothing
  #   $false -> confirmed gone, safe to (re)open
  #   $null  -> could not tell, be conservative and do NOT reopen
  #
  # UI Automation reads every tab title, so when the window is not minimized it
  # tells "open" apart from "navigated away / closed" (the tab title changes).
  # When UIA cannot read (minimized window) it returns $null; then the window
  # title (still readable while minimized) is checked, and finally the live
  # connection to the server is used as a last resort.
  $ui = Test-UiaBrowserTab $needles
  if ($ui -ne $null) { return $ui }
  if (Test-PageWindow $needles) { return $true }
  return Test-ServerConnection
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

  $needles = @("deepseek harness")

  Write-Host ""
  Write-Host "[OK] dsh is running: $URL"
  Write-Host "     The page reopens automatically if you close it."
  Write-Host "     Press Ctrl+C or close this window to stop."
  Write-Host ""

  $lastOpen = [DateTime]::MinValue
  $pageState = Test-DshPageOpen
  if ($pageState -eq $true) {
    Write-Host "The dsh page is already open in your browser."
  } else {
    # $false = confirmed closed, $null = could not tell on first launch.
    # If confirmed closed, wait one more interval: a background tab that is
    # still reconnecting (e.g. right after the server restarted) re-attaches
    # within a second or two, so a second check avoids opening a duplicate.
    if ($pageState -eq $false) {
      Start-Sleep -Seconds $WatchInterval
      if ((Test-DshPageOpen) -eq $true) {
        Write-Host "The dsh page is already open in your browser."
        $pageState = $true
      }
    }
    if ($pageState -ne $true) {
      Write-Host "Opening the web page..."
      Start-Process $URL
      $lastOpen = Get-Date
    }
  }

  # ---------- Watchdog: reopen the page whenever it is closed ----------
  # Test-DshPageOpen reports $false only when it is confident the page is gone:
  # no matching tab title (UIA or window title) and no live connection, or a
  # WebSocket tearing down (CLOSE_WAIT) after the tab navigated away. Two
  # consecutive "closed" reads (~4s) ride out a brief WebSocket reconnect.
  $closedStreak = 0
  while (-not $proc.HasExited) {
    Start-Sleep -Seconds $WatchInterval
    if (-not $proc.HasExited) {
      $pageState = Test-DshPageOpen
      if ($pageState -eq $false) { $closedStreak++ } else { $closedStreak = 0 }
      if ($closedStreak -ge 2 -and ((Get-Date) - $lastOpen).TotalSeconds -ge 5) {
        Write-Host "[$(Get-Date -Format HH:mm:ss)] Page was closed, reopening..."
        Start-Process $URL
        $lastOpen = Get-Date
        $closedStreak = 0
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

