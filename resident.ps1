# 常驻运行器：由计划任务调用，前台阻塞直到代理退出。
#
# 为什么要这样：代理（supervisor → server）会随 DSH 重启、网络重置等原因被静默杀掉。
# 之前用「每 5 分钟轮询」来救，缺点很明显——
#   1. 最坏要等 5 分钟
#   2. 每次轮询都闪一个控制台窗口
# 改成「任务常驻 + 失败自动重启」：
#   - 本脚本调 start.ps1 前台运行，一直不退出，所以计划任务始终处于"运行中"
#   - 代理一死，start.ps1 退出，任务结束并记为失败
#   - 任务计划的 RestartOnFailure 在 1 分钟后重新拉起它
# 这样既不需要轮询，也不会反复弹窗。

param(
    [int]$Port = 8765
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $here 'resident.log'

function Write-ResidentLog([string]$message) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $message
    Add-Content -Path $log -Value $line -Encoding UTF8
    $info = Get-Item $log -ErrorAction SilentlyContinue
    if ($info -and $info.Length -gt 512KB) {
        Move-Item $log (Join-Path $here 'resident.1.log') -Force -ErrorAction SilentlyContinue
    }
}

Write-ResidentLog "常驻运行器启动，端口 $Port"

$startScript = Join-Path $here 'start.ps1'
if (-not (Test-Path $startScript)) {
    Write-ResidentLog "找不到 start.ps1，退出"
    exit 1
}

# 前台运行：start.ps1 内部会 & node，一直阻塞到代理进程结束
try {
    & $startScript -Port $Port
    $code = $LASTEXITCODE
    Write-ResidentLog "start.ps1 已返回，退出码 $code"
    exit $code
} catch {
    Write-ResidentLog "启动异常: $($_.Exception.Message)"
    exit 1
}
