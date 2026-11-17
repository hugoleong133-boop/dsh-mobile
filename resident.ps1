# 常驻运行器：由计划任务调用，永不主动退出。
#
# 为什么是循环而不是单次启动：
#   计划任务结束时，Windows 会关闭该任务的 Job Object，里面的子进程会被一起终止。
#   如果只启动一次代理就返回，任务立刻结束，代理马上被带走。
#
# 为什么用 Start-Process 而不是直接 & 调用：
#   直接 & 调用时，start.ps1 的 Write-Host 会一直占用一个控制台窗口，
#   而这个脚本常驻不退出，窗口就永远挂在桌面上。
#   改成 Start-Process + 输出重定向：子进程无窗口，日志落到文件里。

param(
    [int]$Port = 8765
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $here 'resident.log'
$outLog = Join-Path $here 'agent.out.log'
$errLog = Join-Path $here 'agent.err.log'

function Write-ResidentLog([string]$message) {
    try {
        $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $message
        Add-Content -Path $log -Value $line -Encoding UTF8
        $info = Get-Item $log -ErrorAction SilentlyContinue
        if ($info -and $info.Length -gt 512KB) {
            Move-Item $log (Join-Path $here 'resident.1.log') -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}

$startScript = Join-Path $here 'start.ps1'
if (-not (Test-Path $startScript)) {
    Write-ResidentLog "找不到 start.ps1，退出"
    exit 1
}

Write-ResidentLog "常驻守护启动，端口 $Port"

$round = 0
while ($true) {
    $round += 1
    if ($round -gt 1) { Write-ResidentLog "第 $round 次启动代理" }

    try {
        # 窗口隐藏 + 输出重定向：桌面上不会出现任何控制台
        $proc = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                          '-File', $startScript, '-Port', $Port `
            -WorkingDirectory $here `
            -WindowStyle Hidden `
            -RedirectStandardOutput $outLog `
            -RedirectStandardError $errLog `
            -PassThru

        # 阻塞在这里，直到代理进程结束
        $proc.WaitForExit()
        Write-ResidentLog "代理已退出（退出码 $($proc.ExitCode)），2 秒后重启"
    } catch {
        Write-ResidentLog "启动异常: $($_.Exception.Message)，2 秒后重试"
    }

    Start-Sleep -Seconds 2
}
