# dsh-mobile 看门狗
#
# 背景：代理是普通的 node 进程，电脑睡眠/唤醒、系统更新、DSH 重启都可能
# 把它静默杀掉，且没有任何报错。手机端表现就是三条通道全部超时（-1001）。
#
# 这个脚本只做一件事：端口没在监听就把它拉起来。
# 由计划任务每 2 分钟调用一次，本身跑几毫秒就退出。

param(
    [int]$Port = 8765
)

$ErrorActionPreference = 'SilentlyContinue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $here 'watchdog.log'

function Write-WatchdogLog([string]$message) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $message
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    # 日志超过 200 KB 就轮转，避免长期跑满磁盘
    $info = Get-Item $logFile
    if ($info -and $info.Length -gt 200KB) {
        Move-Item $logFile (Join-Path $here 'watchdog.1.log') -Force
    }
}

function Test-ProxyPort([int]$port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync('127.0.0.1', $port)
        if (-not $task.Wait(3000)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

if (Test-ProxyPort $Port) {
    exit 0
}

Write-WatchdogLog "端口 $Port 无响应，重新拉起"

# boot.ps1 会先确认 DSH 在跑，再启动代理；两者都活着时它什么都不做
$boot = Join-Path $here 'boot.ps1'
if (-not (Test-Path $boot)) {
    Write-WatchdogLog "找不到 boot.ps1，放弃"
    exit 1
}

Start-Process -FilePath 'powershell.exe' `
    -ArgumentList '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
                  '-File', $boot, '-Port', $Port `
    -WorkingDirectory $here

# 给代理 15 秒起来
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 1
    if (Test-ProxyPort $Port) {
        Write-WatchdogLog "已恢复，端口 $Port 开始监听"
        exit 0
    }
}

Write-WatchdogLog "拉起失败，端口 $Port 仍然无响应"
exit 1
