<#
.SYNOPSIS
  判定这台机器的网络形态：公网直连 / NAT 后 / CGNAT 后，并给出跨网络访问该走哪条路。

.DESCRIPTION
  "公司给我静态 IP" 有两种完全不同的意思，处理方式相反：

    A. 固定内网 IP（192.168.x.x 之类）
       → 对公司以外不可路由。端口映射也救不了，除非在路由器上做 NAT 转发。
    B. 固定公网 IP（企业专线，IP 直接落在路由器 WAN 口或本机网卡）
       → 才可能让别人从公网直接连。

  本脚本只做判定，不改任何配置。输出直接告诉你属于哪一种、出站能不能走隧道。

.EXAMPLE
  .\probe-network.ps1

.EXAMPLE
  .\probe-network.ps1 -Json
#>
[CmdletBinding()]
param(
  [switch]$Json,
  [int]$Port = 8765
)

$ErrorActionPreference = 'Continue'

function Test-Private([string]$ip) {
  if ($ip -match '^10\.') { return $true }
  if ($ip -match '^192\.168\.') { return $true }
  if ($ip -match '^172\.(1[6-9]|2[0-9]|3[01])\.') { return $true }
  if ($ip -match '^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.') { return 'cgnat' }
  if ($ip -match '^169\.254\.') { return 'linklocal' }
  return $false
}

function Get-PublicIp {
  $sources = @(
    'https://api.ipify.org',
    'https://ifconfig.me/ip',
    'https://ipinfo.io/ip'
  )
  foreach ($s in $sources) {
    try {
      $r = curl.exe -s --max-time 8 $s 2>$null
      if ($r -and $r.Trim() -match '^\d{1,3}(\.\d{1,3}){3}$') { return $r.Trim() }
    } catch {}
  }
  return $null
}

function Test-Tcp([string]$target, [int]$port, [int]$timeoutMs = 4000) {
  try {
    $client = New-Object System.Net.Sockets.TcpClient
    $iar = $client.BeginConnect($target, $port, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne($timeoutMs, $false)
    if (-not $ok) { $client.Close(); return $false }
    $client.EndConnect($iar)
    $client.Close()
    return $true
  } catch { return $false }
}

$interfaces = @()
foreach ($addr in Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue) {
  if ($addr.IPAddress -like '127.*') { continue }
  $kind = Test-Private $addr.IPAddress
  $interfaces += [pscustomobject]@{
    Alias  = $addr.InterfaceAlias
    Ip     = $addr.IPAddress
    Prefix = $addr.PrefixLength
    Origin = $addr.PrefixOrigin
    Kind   = switch ($kind) {
      $true     { 'private' }
      'cgnat'   { 'cgnat' }
      'linklocal' { 'linklocal' }
      default   { 'public' }
    }
  }
}

$egress = Get-PublicIp
$egressKind = if ($egress) { Test-Private $egress } else { $null }

$geo = $null
if ($egress) {
  try {
    $raw = curl.exe -s --max-time 8 "http://ip-api.com/json/$egress?fields=status,country,regionName,city,isp,org,as" 2>$null
    if ($raw) { $g = $raw | ConvertFrom-Json; if ($g.status -eq 'success') { $geo = $g } }
  } catch {}
}

$outTcp443 = Test-Tcp '1.1.1.1' 443
$outDns = Test-Tcp '8.8.8.8' 53

$publicOnNic = @($interfaces | Where-Object { $_.Kind -eq 'public' })
$verdict = if ($egressKind -eq 'cgnat') { 'cgnat' }
  elseif ($publicOnNic.Count -gt 0 -and $egress -and ($publicOnNic.Ip -contains $egress)) { 'public-direct' }
  elseif ($egress) { 'nat' }
  else { 'unknown' }

$advice = switch ($verdict) {
  'public-direct' {
    '公网 IP 直接在本机网卡上。理论上可以让别人直连 —— 但 dsh-mobile 是明文 HTTP + 6 位 PIN，' +
    '裸露在公网等于把整台工作站的 agent 权限挂在互联网上。仍然建议用隧道，或至少只允许你的固定家宽 IP 访问。'
  }
  'nat' {
    '在 NAT 后面：出口有公网 IP，但入口在公司路由器/防火墙上。两条路 —— ' +
    '(1) 让 IT 把 TCP ' + $Port + ' 映射到这台机器的内网 IP（需要对方配合，且暴露面变大）；' +
    '(2) 装 tailscale 或跑 cloudflared 建立出站隧道（不需要 IT 开任何入站端口，推荐）。'
  }
  'cgnat' {
    '在运营商级 NAT 后面：出口 IP 不是你独占的，端口映射做了也没用。只能走出站隧道（tailscale / cloudflared）。'
  }
  default {
    '拿不到出口公网 IP（可能被公司网络拦了外部探测）。这不影响隧道方案 —— 隧道本来就是纯出站。'
  }
}

$result = [pscustomobject]@{
  interfaces   = $interfaces
  egressIp     = $egress
  egressGeo    = $geo
  verdict      = $verdict
  outbound443  = $outTcp443
  outboundDns  = $outDns
  advice       = $advice
}

if ($Json) {
  $result | ConvertTo-Json -Depth 5
  exit 0
}

Write-Host ''
Write-Host '  本机 IPv4' -ForegroundColor Cyan
$interfaces | Format-Table Alias, Ip, Prefix, Origin, Kind -AutoSize | Out-String | Write-Host

Write-Host '  出口' -ForegroundColor Cyan
if ($egress) {
  Write-Host ("    公网 IP   {0}" -f $egress)
  if ($geo) { Write-Host ("    归属      {0} {1}·{2} / {3}" -f $geo.country, $geo.regionName, $geo.city, $geo.isp) }
} else {
  Write-Host '    公网 IP   取不到（公司网络可能拦了外探）' -ForegroundColor Yellow
}
Write-Host ("    443 出站  {0}" -f $(if ($outTcp443) { '通' } else { '不通' }))
Write-Host ("    DNS 出站  {0}" -f $(if ($outDns) { '通' } else { '不通' }))
Write-Host ''

$label = switch ($verdict) {
  'public-direct' { '公网直连（公网 IP 在本机）' }
  'nat'           { 'NAT 后（出口有公网 IP，入口在路由器）' }
  'cgnat'         { 'CGNAT 后（出口 IP 不独占）' }
  default         { '未知' }
}

$color = switch ($verdict) {
  'public-direct' { 'Yellow' }
  'nat'           { 'Yellow' }
  'cgnat'         { 'Yellow' }
  default         { 'DarkGray' }
}

Write-Host ("  判定：{0}" -f $label) -ForegroundColor $color
Write-Host ''
Write-Host '  建议' -ForegroundColor Cyan
Write-Host ("    {0}" -f $advice)
Write-Host ''
Write-Host '  下一步' -ForegroundColor Cyan
Write-Host '    隧道方案一条命令就够：.\tunnel.ps1 -Mode auto'
Write-Host ''
