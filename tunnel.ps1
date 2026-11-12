<#
.SYNOPSIS
  给 dsh-mobile 开一条跨网络通道：在公司电脑上跑，家里手机就能连。

.DESCRIPTION
  dsh-mobile 的代理监听 0.0.0.0，所以缺的从来不是"同一 WiFi"，
  而是一条能把流量送到公司电脑的路径。三种做法，本脚本都支持：

    tailscale   两边装客户端，走 WireGuard 打洞。不需要公网 IP、不需要 IT 开局域网端口。
                手机装 Tailscale App、登同一账号，用 100.x 地址访问。
    cloudflare  单个 exe，纯出站，立刻给一个 https://xxx.trycloudflare.com。
                不需要装服务、不需要管理员，最适合作业现场装不了软件时用。
    ssh         反向隧道：公司电脑主动 ssh -R 到你家那台机器，家里直接访问。
                适合家里有公网 IP / IPv6 / 常开 NAS 的情况，零第三方。
    ngrok       同 cloudflare，另一家。

  全部是出站连接 —— 公司防火墙拦的是入站，这些照常能出去。

.EXAMPLE
  .\tunnel.ps1 -Mode auto

.EXAMPLE
  .\tunnel.ps1 -Mode cloudflare -Download

.EXAMPLE
  .\tunnel.ps1 -Mode ssh -SshTarget me@home.example.com -SshPort 22
#>
[CmdletBinding()]
param(
  [ValidateSet('auto', 'tailscale', 'cloudflare', 'ngrok', 'ssh', 'status')]
  [string]$Mode = 'auto',
  [int]$Port = 8765,
  [string]$SshTarget = '',
  [int]$SshPort = 22,
  [switch]$Download
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$tools = Join-Path $here 'tools'
$stateFile = Join-Path $here 'state.json'

function Get-Pin {
  if (-not (Test-Path $stateFile)) {
    throw "没有 state.json —— 先跑一次 .\start.ps1，配对信息在那里生成。"
  }
  return (Get-Content $stateFile -Raw | ConvertFrom-Json).pin
}

function Test-Proxy {
  try {
    $r = curl.exe -s --max-time 4 "http://127.0.0.1:$Port/__m/status" 2>$null
    if (-not $r) { return $null }
    return ($r | ConvertFrom-Json)
  } catch { return $null }
}

function Resolve-Tool([string]$name) {
  $local = Join-Path $tools "$name.exe"
  if (Test-Path $local) { return $local }
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Save-Binary([string]$url, [string]$dest) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
  Write-Host "  下载 $url" -ForegroundColor DarkGray
  curl.exe -L --max-time 120 -o $dest $url
  if (-not (Test-Path $dest) -or (Get-Item $dest).Length -lt 100000) {
    throw "下载失败或文件过小：$dest"
  }
}

function Wait-ForPattern([string]$path, [string]$pattern, [int]$timeoutSec = 45) {
  $deadline = (Get-Date).AddSeconds($timeoutSec)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path $path) {
      $text = Get-Content $path -Raw -ErrorAction SilentlyContinue
      if ($text) {
        $m = [regex]::Match($text, $pattern)
        if ($m.Success) { return $m.Value }
      }
    }
    Start-Sleep -Milliseconds 700
  }
  return $null
}

function Show-PairUrl([string]$base, [string]$pin) {
  $sep = if ($base.Contains('?')) { '&' } else { '?' }
  Write-Host ''
  Write-Host '  ' + ('─' * 62) -ForegroundColor DarkGray
  Write-Host "  手机打开： $base$($sep)k=$pin" -ForegroundColor Cyan
  Write-Host "  PIN：      $pin" -ForegroundColor Cyan
  Write-Host '  ' + ('─' * 62) -ForegroundColor DarkGray
  Write-Host '  换过域名/地址后浏览器要重新配对一次（dshm cookie 是按域名存的）。'
  Write-Host '  隧道域名每次重启会变 → 想稳定就用 tailscale 或固定域名的 named tunnel。'
  Write-Host ''
}

# ---------------------------------------------------------------- 前置检查

$proxy = Test-Proxy
if (-not $proxy) {
  Write-Host "  127.0.0.1:$Port 上没有 dsh-mobile 代理在跑。" -ForegroundColor Yellow
  Write-Host '  先开另一个窗口跑：.\start.ps1 -Background' -ForegroundColor Yellow
  exit 1
}

$pin = Get-Pin
Write-Host ''
Write-Host "  代理  http://127.0.0.1:$Port  →  上游 $($proxy.upstream.authority)  自动=$($proxy.upstream.auto)"

if ($Mode -eq 'status') {
  $proxy | ConvertTo-Json -Depth 5
  exit 0
}

# ---------------------------------------------------------------- 选路

if ($Mode -eq 'auto') {
  if (Resolve-Tool 'tailscale') { $Mode = 'tailscale' }
  elseif (Resolve-Tool 'cloudflared') { $Mode = 'cloudflare' }
  elseif (Resolve-Tool 'ngrok') { $Mode = 'ngrok' }
  else {
    Write-Host ''
    Write-Host '  三种隧道工具都没装。推荐顺序：' -ForegroundColor Yellow
    Write-Host '    1) tailscale  https://tailscale.com/download  两边都装，手机也装，登同一账号'
    Write-Host '    2) cloudflared 单文件，适合装不了软件的公司电脑：'
    Write-Host '         .\tunnel.ps1 -Mode cloudflare -Download'
    Write-Host '    3) 家里有公网 IP / IPv6 / 常开 NAS → ssh 反向隧道：'
    Write-Host '         .\tunnel.ps1 -Mode ssh -SshTarget me@home.example.com'
    Write-Host ''
    exit 1
  }
  Write-Host "  auto 选中：$Mode"
}

switch ($Mode) {

  'tailscale' {
    $ts = Resolve-Tool 'tailscale'
    if (-not $ts) {
      Write-Host '  没找到 tailscale。装完登录后重跑：https://tailscale.com/download' -ForegroundColor Yellow
      exit 1
    }
    $state = & $ts status --json 2>$null | ConvertFrom-Json
    if ($state.BackendState -ne 'Running') {
      Write-Host "  tailscale 未登录（BackendState=$($state.BackendState)）。先跑：tailscale up" -ForegroundColor Yellow
      exit 1
    }
    $ip4 = (& $ts ip -4 2>$null | Select-Object -First 1)
    if (-not $ip4) { throw 'tailscale 没有分配 IPv4' }

    $dns = $state.Self.DNSName
    $hostPart = if ($dns) { $dns.TrimEnd('.') } else { $ip4 }
    Write-Host "  tailnet       $($state.Self.HostName)"
    Write-Host "  tailscale IP  $ip4"
    Write-Host ''
    Write-Host '  手机需要装 Tailscale 并登同一账号；之后在任何网络下都能访问：'
    Show-PairUrl "http://${hostPart}:$Port" $pin
    Write-Host "  备用直连地址：http://${ip4}:$Port/?k=$pin" -ForegroundColor DarkGray
    Write-Host ''
  }

  'cloudflare' {
    $cf = Resolve-Tool 'cloudflared'
    if (-not $cf -and $Download) {
      $cf = Join-Path $tools 'cloudflared.exe'
      Save-Binary 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' $cf
    }
    if (-not $cf) {
      Write-Host '  没找到 cloudflared。加 -Download 自动取单文件：' -ForegroundColor Yellow
      Write-Host '    .\tunnel.ps1 -Mode cloudflare -Download'
      exit 1
    }
    $log = Join-Path $here 'cloudflared.log'
    Remove-Item $log -Force -ErrorAction SilentlyContinue
    $proc = Start-Process -FilePath $cf `
      -ArgumentList @('tunnel', '--url', "http://127.0.0.1:$Port", '--no-autoupdate') `
      -RedirectStandardError $log -RedirectStandardOutput (Join-Path $here 'cloudflared.out.log') `
      -WindowStyle Hidden -PassThru

    Write-Host '  建立 Cloudflare quick tunnel…' -ForegroundColor DarkGray
    $url = Wait-ForPattern $log 'https://[a-z0-9-]+\.trycloudflare\.com'
    if (-not $url) {
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
      Write-Host '  没拿到隧道地址。cloudflared 输出：' -ForegroundColor Yellow
      Get-Content $log -Tail 20 -ErrorAction SilentlyContinue
      exit 1
    }
    Show-PairUrl $url $pin
    Write-Host "  cloudflared PID $($proc.Id)，日志 $log" -ForegroundColor DarkGray
    Write-Host '  Ctrl+C 结束隧道。' -ForegroundColor DarkGray
    try {
      while (-not $proc.HasExited) { Start-Sleep -Seconds 2 }
    } finally {
      if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    }
  }

  'ngrok' {
    $ng = Resolve-Tool 'ngrok'
    if (-not $ng -and $Download) {
      $zip = Join-Path $tools 'ngrok.zip'
      Save-Binary 'https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip' $zip
      Expand-Archive -Path $zip -DestinationPath $tools -Force
      $ng = Join-Path $tools 'ngrok.exe'
    }
    if (-not $ng) {
      Write-Host '  没找到 ngrok。加 -Download，或先去 ngrok.com 拿 authtoken。' -ForegroundColor Yellow
      exit 1
    }
    $log = Join-Path $here 'ngrok.log'
    Remove-Item $log -Force -ErrorAction SilentlyContinue
    $proc = Start-Process -FilePath $ng `
      -ArgumentList @('http', "$Port", '--log', 'stdout', '--log-format', 'logfmt') `
      -RedirectStandardError $log -RedirectStandardOutput (Join-Path $here 'ngrok.out.log') `
      -WindowStyle Hidden -PassThru

    Write-Host '  建立 ngrok 隧道…' -ForegroundColor DarkGray
    $url = Wait-ForPattern $log 'https://[a-z0-9-]+\.ngrok-free\.app'
    if (-not $url) { $url = Wait-ForPattern $log 'https://[a-z0-9-]+\.ngrok\.io' }
    if (-not $url) {
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
      Write-Host '  没拿到隧道地址（ngrok 需要先 ngrok config add-authtoken）。输出：' -ForegroundColor Yellow
      Get-Content $log -Tail 20 -ErrorAction SilentlyContinue
      exit 1
    }
    Show-PairUrl $url $pin
    Write-Host '  Ctrl+C 结束隧道。' -ForegroundColor DarkGray
    try {
      while (-not $proc.HasExited) { Start-Sleep -Seconds 2 }
    } finally {
      if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    }
  }

  'ssh' {
    if (-not $SshTarget) {
      throw 'ssh 模式需要 -SshTarget user@host（你家那台有公网 IP / IPv6 的机器）'
    }
    $ssh = Resolve-Tool 'ssh'
    if (-not $ssh) { throw 'Windows 没带 OpenSSH 客户端：设置 → 可选功能 → OpenSSH 客户端' }

    Write-Host ''
    Write-Host "  反向隧道  $SshTarget`:$Port  →  本机 127.0.0.1:$Port" -ForegroundColor DarkGray
    Write-Host '  前提：对端 sshd 的 GatewayPorts 允许绑定 0.0.0.0（否则只能对端本机访问）。' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '  在家那台机器上访问：' -ForegroundColor Cyan
    Show-PairUrl "http://<对端地址>:$Port" $pin
    Write-Host '  Ctrl+C 断开。' -ForegroundColor DarkGray
    & $ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 `
      -p $SshPort -R "0.0.0.0:${Port}:127.0.0.1:${Port}" $SshTarget
  }
}
