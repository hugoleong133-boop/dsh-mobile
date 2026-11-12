<#
.SYNOPSIS
  把 dsh-mobile 注册成登录自启的计划任务，人不在公司也能连。

.DESCRIPTION
  公司电脑不会一直有人盯着，重启或 DSH 更新之后代理就没了。
  这个脚本注册一个「登录时运行 boot.ps1」的任务，boot 会先把 DSH 拉起来，
  再起代理。

  不需要管理员（当前用户的任务）。如果希望开机即生效而不必有人登录，
  加 -AtStartup —— 那个要管理员。

.EXAMPLE
  .\install-task.ps1

.EXAMPLE
  .\install-task.ps1 -Status

.EXAMPLE
  .\install-task.ps1 -Remove
#>
[CmdletBinding()]
param(
  [switch]$Remove,
  [switch]$Status,
  [switch]$AtStartup,
  [int]$Port = 8765
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$taskName = 'dsh-mobile'
$boot = Join-Path $here 'boot.ps1'

if (-not (Test-Path $boot)) { throw "缺少 boot.ps1：$boot" }

if ($Status) {
  $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if (-not $task) { Write-Host "没有注册 $taskName" -ForegroundColor Yellow; exit 0 }
  $info = Get-ScheduledTaskInfo -TaskName $taskName
  Write-Host ''
  Write-Host "  任务    $taskName"
  Write-Host "  状态    $($task.State)"
  Write-Host "  上次    $($info.LastRunTime)  结果 $($info.LastTaskResult)"
  Write-Host "  下次    $($info.NextRunTime)"
  Write-Host ''
  $task.Actions | ForEach-Object { Write-Host "  动作    $($_.Execute) $($_.Arguments)" }
  $task.Triggers | ForEach-Object { Write-Host "  触发    $($_.CimClass.CimClassName)" }
  Write-Host ''
  exit 0
}

if ($Remove) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
  Write-Host "已删除任务 $taskName" -ForegroundColor Green
  exit 0
}

$argLine = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$boot`" -Port $Port"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argLine -WorkingDirectory $here

if ($AtStartup) {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw '-AtStartup 需要管理员权限：右键 PowerShell → 以管理员身份运行' }
  $trigger = New-ScheduledTaskTrigger -AtStartup
  $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  Write-Host '  模式：开机即启（SYSTEM），不需要有人登录' -ForegroundColor DarkGray
} else {
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  $principal = $null
  Write-Host '  模式：登录自启（当前用户）' -ForegroundColor DarkGray
}

$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -RestartCount 3 `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -StartWhenAvailable

$params = @{
  TaskName    = $taskName
  Action      = $action
  Trigger     = $trigger
  Settings    = $settings
  Description = 'dsh-mobile: 让 iPhone 通过隧道连接这台机器的 DSH 会话'
  Force       = $true
}
if ($principal) { $params.Principal = $principal }

Register-ScheduledTask @params | Out-Null
Write-Host "已注册任务 $taskName" -ForegroundColor Green
Write-Host ''
Write-Host '  立即试跑一次：'
Write-Host "    Start-ScheduledTask -TaskName $taskName"
Write-Host '  看结果：'
Write-Host "    .\install-task.ps1 -Status；日志在 $here\boot.log"
Write-Host ''
