<#
.SYNOPSIS
  开机/登录后自动把 DSH 和 dsh-mobile 都带起来，适合没人值守的公司电脑。

.DESCRIPTION
  任务计划里跑的就是这个脚本。顺序固定：

    1. DeepSeek Harness 没在跑 → 启动它
    2. 等它开始在回环端口上监听（最多 120 秒）
    3. 起 dsh-mobile 代理（后台）

  DSH 启动慢或弹登录框时，第 2 步会等到超时；代理仍会启动，
  只是等你把 DSH 的窗口弄好之后，下一次请求会自动发现新端口。

.EXAMPLE
  .\boot.ps1
#>
[CmdletBinding()]
param(
  [string]$DshExe = 'D:\Deepseek\DeepSeek Harness.exe',
  [int]$Port = 8765,
  [int]$WaitSeconds = 120
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $here 'boot.log'

function Write-Log([string]$msg) {
  $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Add-Content -Path $log -Value $line -Encoding utf8
  Write-Host $line
}

function Get-DshListenerPorts {
  $pids = @(Get-Process 'DeepSeek Harness' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
  if ($pids.Count -eq 0) { return @() }
  $conns = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $pids -contains $_.OwningProcess -and $_.LocalAddress -match '^(127\.|::1)' }
  return @($conns | Select-Object -ExpandProperty LocalPort -Unique)
}

Write-Log '--- boot ---'

$dshRunning = [bool](Get-Process 'DeepSeek Harness' -ErrorAction SilentlyContinue)
if (-not $dshRunning) {
  if (Test-Path $DshExe) {
    Write-Log "启动 DSH: $DshExe"
    Start-Process -FilePath $DshExe
  } else {
    Write-Log "找不到 DSH 可执行文件: $DshExe（用 -DshExe 指定正确路径）"
  }
} else {
  Write-Log 'DSH 已在运行'
}

$deadline = (Get-Date).AddSeconds($WaitSeconds)
$ports = @()
while ((Get-Date) -lt $deadline) {
  $ports = Get-DshListenerPorts
  if ($ports.Count -gt 0) { break }
  Start-Sleep -Seconds 2
}

if ($ports.Count -gt 0) {
  Write-Log ("DSH 监听端口: " + ($ports -join ', '))
} else {
  Write-Log "等待 $WaitSeconds 秒仍没看到 DSH 监听端口；代理先起，端口稍后自动跟随"
}

$pidFile = Join-Path $here 'dsh-mobile.pid'
if (Test-Path $pidFile) {
  $old = (Get-Content $pidFile -Raw).Trim()
  if (Get-Process -Id $old -ErrorAction SilentlyContinue) {
    Write-Log "dsh-mobile 已在跑（PID $old），不重复启动"
    exit 0
  }
  Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

Write-Log "启动 dsh-mobile 代理，端口 $Port"
Start-Process -FilePath 'powershell.exe' `
  -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $here 'start.ps1'), '-Background', '-Port', "$Port") `
  -WorkingDirectory $here -WindowStyle Hidden

Start-Sleep -Seconds 6
if (Test-Path $pidFile) {
  $new = (Get-Content $pidFile -Raw).Trim()
  Write-Log "dsh-mobile PID $new"
} else {
  Write-Log '代理没写出 pid 文件，检查 dsh-mobile.err.log'
}
