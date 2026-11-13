<#
.SYNOPSIS
  启动 DSH Mobile：把本机 DSH Web GUI 暴露给 iPhone，带 PIN 门禁和主屏幕 App 注入。

.DESCRIPTION
  不修改 DSH 任何文件、不重启 DSH、不动 profile。本脚本只做四件事：
    1. 找到正在跑的 DSH 监听端口和本机局域网 IP
    2. 用同一份 browser-session 密钥铸造合法 DSH cookie（由 server.mjs 完成）
    3. 起一个带 PIN 的转发进程
    4. 打印配对链接 + 二维码

.PARAMETER Port
  手机访问的端口，默认 8765。

.PARAMETER UpstreamPort
  DSH Web GUI 端口。留空自动从正在运行的 DSH 进程探测。

.PARAMETER Pin
  6 位配对 PIN。留空沿用 state.json 里已保存的，首次运行随机生成。

.PARAMETER PublicUrl
  走 Tailscale / cloudflared / Cloudflare Tunnel 时对外公布 https 地址，只影响打印和二维码。

.PARAMETER Background
  后台运行，PID 写入 dsh-mobile.pid。

.PARAMETER Qr
  生成 pairing-qr.png 并用系统看图打开，手机直接扫。

.EXAMPLE
  .\start.ps1 -Qr

.EXAMPLE
  .\start.ps1 -PublicUrl "https://dsh.example.ts.net" -Background
#>
[CmdletBinding()]
param(
  [int]$Port = 8765,
  [int]$UpstreamPort = 0,
  [string]$Pin = '',
  [string]$PublicUrl = '',
  [switch]$Background,
  [switch]$Qr,
  [string]$TlsCert = '',
  [string]$TlsKey = ''
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }

function Resolve-Node {
  $candidates = @(
    (Join-Path $dshHome 'dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe'),
    (Join-Path $env:USERPROFILE '.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe')
  )
  foreach ($c in $candidates) {
    if ($c -and (Test-Path $c)) { return $c }
  }
  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw 'node.exe 找不到：DSH 自带运行时缺失，也没有系统 node。'
}

function Resolve-UpstreamPort {
  if ($UpstreamPort -gt 0) { return $UpstreamPort }
  $pids = @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
  if ($pids.Count -gt 0) {
    $conn = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
      Where-Object { $pids -contains $_.OwningProcess -and $_.LocalAddress -match '^(127\.|::1)' } |
      Sort-Object LocalPort |
      Select-Object -First 1
    if ($conn) { return [int]$conn.LocalPort }
  }
  foreach ($p in 55514, 3000, 8080) {
    $probe = Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue
    if ($probe) { return $p }
  }
  throw '找不到 DSH Web GUI 端口。先打开 DeepSeek Harness 主界面，或显式指定 -UpstreamPort。'
}

function Resolve-LanIp {
  $addr = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
      $_.IPAddress -notlike '127.*' -and
      $_.IPAddress -notlike '169.254.*' -and
      $_.PrefixOrigin -ne 'WellKnown'
    } |
    Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet|Bluetooth|QuickFox|Tailscale' } |
    Sort-Object -Property @{ Expression = { if ($_.IPAddress -like '192.168.*') { 0 } elseif ($_.IPAddress -like '10.*') { 1 } else { 2 } } } |
    Select-Object -First 1
  if ($addr) { return $addr.IPAddress }
  return '127.0.0.1'
}

$node = Resolve-Node
$upstream = Resolve-UpstreamPort
$lanIp = Resolve-LanIp
$stateFile = Join-Path $here 'state.json'

# 传 0 表示让 server.mjs 自己跟随 DSH 的端口变化（DSH 重启后端口会变）
$upstreamArg = if ($UpstreamPort -gt 0) { $UpstreamPort } else { 0 }

if (-not (Test-Path (Join-Path $dshHome '.credentials.yaml'))) {
  throw "缺少 $dshHome\.credentials.yaml —— 先启动一次 DeepSeek Harness 生成 browser-session 密钥。"
}

# PIN 要在打印之前就确定，否则屏幕上的 PIN 和进程里的可能不是一个
$effectivePin = $Pin
if (-not $effectivePin) {
  if (Test-Path $stateFile) {
    $effectivePin = (Get-Content $stateFile -Raw | ConvertFrom-Json).pin
  } else {
    $effectivePin = -join (1..6 | ForEach-Object { Get-Random -Minimum 0 -Maximum 10 })
  }
}

# certs/ 里存在自签证书就默认启用 HTTPS ——
# iOS 只在安全上下文里暴露 navigator.mediaDevices，语音输入靠这一层。
if (-not $TlsCert -and -not $TlsKey) {
  $autoCert = Join-Path $here 'certs\server.crt'
  $autoKey = Join-Path $here 'certs\server.key'
  if ((Test-Path $autoCert) -and (Test-Path $autoKey)) {
    $TlsCert = $autoCert
    $TlsKey = $autoKey
    Write-Host '  检测到 certs/，启用 HTTPS（手机需信任 dsh-ca.cer）' -ForegroundColor DarkGray
  }
}

$nodeArgs = @(
  (Join-Path $here 'server.mjs'),
  '--port', $Port,
  '--upstream-port', $upstreamArg,
  '--state', $stateFile,
  '--pin', $effectivePin
)
if ($PublicUrl) { $nodeArgs += @('--public-url', $PublicUrl) }
if ($TlsCert -and $TlsKey) { $nodeArgs += @('--tls-cert', $TlsCert, '--tls-key', $TlsKey) }

# 端口占用预检，避免 node 抛 EADDRINUSE 后脚本像"启动了"一样安静退出
$busy = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
if ($busy) {
  throw "端口 $Port 已被进程 $($busy[0].OwningProcess) 占用，换一个 -Port。"
}

Write-Host ''
Write-Host "  node      $node" -ForegroundColor DarkGray
Write-Host "  上游      http://127.0.0.1:$upstream （自动跟随端口变化）" -ForegroundColor DarkGray
Write-Host "  局域网    $lanIp" -ForegroundColor DarkGray
Write-Host ''

if ($Background) {
  $log = Join-Path $here 'dsh-mobile.log'
  $errLog = Join-Path $here 'dsh-mobile.err.log'
  $proc = Start-Process -FilePath $node -ArgumentList $nodeArgs -WorkingDirectory $here `
    -RedirectStandardOutput $log -RedirectStandardError $errLog `
    -WindowStyle Hidden -PassThru
  Set-Content -Path (Join-Path $here 'dsh-mobile.pid') -Value $proc.Id -Encoding ascii

  # 轮询端口就绪，别用固定 sleep 赌 node 的启动速度
  $deadline = (Get-Date).AddSeconds(15)
  $ready = $false
  while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) { break }
    if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) { $ready = $true; break }
    Start-Sleep -Milliseconds 200
  }
  if (-not $ready -and -not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Get-Content $log, $errLog -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
    throw "转发进程 15 秒内没有监听 $Port。"
  }
  if ($proc.HasExited) {
    Get-Content $log, $errLog -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
    throw "转发进程启动后立即退出（exit $($proc.ExitCode)），上面是它最后的输出。"
  }
  Write-Host "  已后台运行，PID $($proc.Id)，日志 dsh-mobile.log" -ForegroundColor Green
}

$scheme = if ($TlsCert -and $TlsKey) { 'https' } else { 'http' }
$url = if ($PublicUrl) { "$PublicUrl/?k=$effectivePin" } else { "${scheme}://${lanIp}:$Port/?k=$effectivePin" }

# 同一台机器在家/公司/外面都能用的地址只有隧道给的。
# tailscale 的 MagicDNS 名是全局固定，用它配对一次，之后换网络不用再改。
$tailnetUrl = $null
$ts = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $ts) {
  foreach ($candidate in @(
      (Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'),
      (Join-Path ${env:ProgramFiles(x86)} 'Tailscale\tailscale.exe'),
      (Join-Path $here 'tools\tailscale.exe')
    )) {
    if ($candidate -and (Test-Path $candidate)) { $ts = $candidate; break }
  }
}
if ($ts) {
  try {
    $st = & $ts status --json 2>$null | ConvertFrom-Json
    if ($st.BackendState -eq 'Running') {
      $dns = $st.Self.DNSName
      $tsIp = (& $ts ip -4 2>$null | Select-Object -First 1)
      $hostPart = if ($dns) { $dns.TrimEnd('.') } else { $tsIp }
      if ($hostPart) { $tailnetUrl = "${scheme}://${hostPart}:$Port/?k=$effectivePin" }
    }
  } catch { }
}

Write-Host ''
if ($tailnetUrl) {
  Write-Host "  任何网络都能用（tailscale，推荐拿这个去配对）：" -ForegroundColor Green
  Write-Host "    $tailnetUrl" -ForegroundColor Green
  Write-Host ''
  Write-Host "  仅同一局域网（换网络就失效）：" -ForegroundColor DarkGray
  Write-Host "    $url" -ForegroundColor DarkGray
} else {
  Write-Host "  手机打开： $url" -ForegroundColor Cyan
  Write-Host ''
  Write-Host "  注意：这是局域网地址。要在家连公司电脑，装 tailscale 后这里会多给一个固定地址，" -ForegroundColor Yellow
  Write-Host "  或者用 .\tunnel.ps1 起隧道拿临时域名（每次重启会变）。" -ForegroundColor Yellow
}
Write-Host "  PIN：      $effectivePin" -ForegroundColor Cyan
Write-Host ''

if ($Qr) {
  $py = Join-Path $dshHome 'dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
  if (Test-Path $py) {
    $qrPath = Join-Path $here 'pairing-qr.png'
    & $py -c "import segno,sys; segno.make(sys.argv[1], error='m').save(sys.argv[2], scale=10, border=2)" $url $qrPath
    if (Test-Path $qrPath) {
      Write-Host "  二维码：   $qrPath" -ForegroundColor Cyan
      Start-Process $qrPath
    }
  } else {
    Write-Host '  （没有自带 python，跳过二维码）' -ForegroundColor DarkGray
  }
}

if (-not $Background) {
  Write-Host '  Ctrl+C 停止。手机端 Safari → 分享 → 添加到主屏幕。' -ForegroundColor DarkGray
  Write-Host ''
  & $node @nodeArgs
}
