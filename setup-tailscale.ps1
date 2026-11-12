<#
.SYNOPSIS
  装 Tailscale 并把 tailnet 地址算出来，让手机在任何网络下都能连到这台机器的 DSH。

.DESCRIPTION
  一次跑完四步：装 → 登录 → 等上线 → 打印配对地址。
  需要你亲手做两件：点一次 UAC，在浏览器里授权一次。

  装好之后这台机器在 tailnet 里的地址是固定的（MagicDNS 名），
  手机装同样的 Tailscale App、登同一账号，就能在家连公司电脑。

.EXAMPLE
  .\setup-tailscale.ps1

.EXAMPLE
  # 公司电脑上没有这个文件夹里的安装包时，让它自己下
  .\setup-tailscale.ps1 -Download
#>
[CmdletBinding()]
param(
  [switch]$Download,
  [int]$Port = 8765,
  [int]$LoginTimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$tools = Join-Path $here 'tools'
$msi = Join-Path $tools 'tailscale-setup-amd64.msi'
$cli = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
$stateFile = Join-Path $here 'state.json'

function Test-Admin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TsState {
  if (-not (Test-Path $cli)) { return $null }
  try { return (& $cli status --json 2>$null | ConvertFrom-Json) } catch { return $null }
}

# ---------------------------------------------------------------- 0. 已装好就直接算地址

if (Test-Path $cli) {
  $st = Get-TsState
  if ($st -and $st.BackendState -eq 'Running') {
    Write-Host '  Tailscale 已安装且已登录。' -ForegroundColor Green
  } else {
    Write-Host "  Tailscale 已安装，但还没登录（BackendState=$(if($st){$st.BackendState}else{'unknown'})）。" -ForegroundColor Yellow
  }
} else {
  # ---------------------------------------------------------------- 1. 准备安装包
  if (-not (Test-Path $msi)) {
    if (-not $Download) {
      throw "缺少安装包 $msi。在别的机器上把它拷过来，或加 -Download 让它自己下（约 37 MB）。"
    }
    New-Item -ItemType Directory -Force -Path $tools | Out-Null
    Write-Host '  下载 Tailscale 安装包…' -ForegroundColor DarkGray
    curl.exe -L --max-time 300 -o $msi 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi'
    if (-not (Test-Path $msi)) { throw '下载失败' }
  }

  # ---------------------------------------------------------------- 2. 提权安装
  if (-not (Test-Admin)) {
    Write-Host ''
    Write-Host '  安装需要管理员权限，正在弹出 UAC —— 请点「是」。' -ForegroundColor Yellow
    Write-Host ''
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Port', "$Port",
      '-LoginTimeoutSeconds', "$LoginTimeoutSeconds")
    if ($Download) { $argList += '-Download' }
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -PassThru
    Write-Host "  已请求提权（PID $($p.Id)）。装完那个窗口会打印配对地址。" -ForegroundColor DarkGray
    exit 0
  }

  Write-Host '  静默安装 Tailscale…' -ForegroundColor DarkGray
  $msiArgs = @('/i', "`"$msi`"", '/qn', '/norestart')
  $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
  if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
    throw "msiexec 返回 $($proc.ExitCode)，安装失败"
  }
  if (-not (Test-Path $cli)) { throw "安装结束但找不到 $cli" }
  Write-Host '  安装完成。' -ForegroundColor Green
}

# ---------------------------------------------------------------- 3. 登录

$st = Get-TsState
if (-not $st -or $st.BackendState -ne 'Running') {
  Write-Host ''
  Write-Host '  需要登录 Tailscale。下面会打印一个授权链接，' -ForegroundColor Yellow
  Write-Host '  在浏览器里打开它，用你的账号确认这台机器加入 tailnet。' -ForegroundColor Yellow
  Write-Host ''

  $loginOut = & $cli login 2>&1
  $url = ($loginOut | Select-String -Pattern 'https://login\.tailscale\.com/\S+').Matches.Value | Select-Object -First 1
  if ($url) {
    Write-Host '  授权链接：' -ForegroundColor Cyan
    Write-Host "    $url" -ForegroundColor Cyan
    Write-Host ''
    Start-Process $url
  } else {
    Write-Host ($loginOut | Out-String)
  }

  Write-Host "  等待授权（最多 $LoginTimeoutSeconds 秒）…" -ForegroundColor DarkGray
  $deadline = (Get-Date).AddSeconds($LoginTimeoutSeconds)
  $running = $false
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    $st = Get-TsState
    if ($st -and $st.BackendState -eq 'Running') { $running = $true; break }
  }
  if (-not $running) {
    throw "等了 $LoginTimeoutSeconds 秒仍没上线。授权完再跑一次本脚本即可，它会接着往下走。"
  }
  Write-Host '  已上线。' -ForegroundColor Green
}

# ---------------------------------------------------------------- 4. 算地址

$st = Get-TsState
$dns = $st.Self.DNSName
$ip4 = (& $cli ip -4 2>$null | Select-Object -First 1)
$hostPart = if ($dns) { $dns.TrimEnd('.') } else { $ip4 }

$pin = ''
if (Test-Path $stateFile) { $pin = (Get-Content $stateFile -Raw | ConvertFrom-Json).pin }
$suffix = if ($pin) { "?k=$pin" } else { '' }

Write-Host ''
Write-Host '  ' + ('─' * 64) -ForegroundColor DarkGray
Write-Host "  这台机器在 tailnet 里：$($st.Self.HostName)" -ForegroundColor Green
if ($hostPart) {
  Write-Host ''
  Write-Host '  手机 App 里填这个（任何网络都能用）：' -ForegroundColor Green
  Write-Host "    http://${hostPart}:$Port/$suffix" -ForegroundColor Green
  Write-Host "  tailscale IP 直连备用：http://${ip4}:$Port/$suffix" -ForegroundColor DarkGray
} else {
  Write-Host '  拿不到 MagicDNS 名，检查 tailnet 是否开启了 MagicDNS。' -ForegroundColor Yellow
}
if (-not $pin) {
  Write-Host ''
  Write-Host '  还没生成 PIN：先跑 .\start.ps1 一次，再回头看这里。' -ForegroundColor Yellow
}
Write-Host '  ' + ('─' * 64) -ForegroundColor DarkGray
Write-Host ''
Write-Host '  手机那边：App Store 装 Tailscale，登同一账号，然后打开 DSH App 填上面的地址。'
Write-Host '  以后公司电脑重启也会自动连回 tailnet，地址不变，不用再配对。'
Write-Host ''
