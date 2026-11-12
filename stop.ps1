# 停止 dsh-mobile 后台进程。留一份 dsh-mobile.log 供事后查看。

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidFile = Join-Path $here 'dsh-mobile.pid'

if (-not (Test-Path $pidFile)) {
  Write-Host '没有 dsh-mobile.pid，看起来没在后台跑。' -ForegroundColor Yellow
  exit 0
}

$proxyId = (Get-Content $pidFile -Raw).Trim()
$proc = Get-Process -Id $proxyId -ErrorAction SilentlyContinue
if (-not $proc) {
  Write-Host "PID $proxyId 已经不在了，清掉 pid 文件。" -ForegroundColor DarkGray
  Remove-Item $pidFile -ErrorAction SilentlyContinue
  exit 0
}

Stop-Process -Id $proxyId -Force
Remove-Item $pidFile -ErrorAction SilentlyContinue
Write-Host "已停止 PID $proxyId。" -ForegroundColor Green
