<#
.SYNOPSIS
  把 DSHMobile-unsigned.ipa 在 Windows 上重签成能装进 iPhone 的包。

.DESCRIPTION
  两条路线：
    A. 本脚本 + zsign —— 需要 .p12 证书 + .mobileprovision。
    B. Sideloadly（推荐，零证书准备）—— 装好 Sideloadly，用 Apple ID 登录直接拖 ipa 进去。

  zsign 是跨平台签名器（https://github.com/zhlynn/zsign），Windows 有现成二进制。
  没有它就去下 Sideloadly，那个自带证书申请与签名。

.EXAMPLE
  .\sign-windows.ps1 -Ipa DSHMobile-unsigned.ipa -P12 cert.p12 -P12Password 123456 -Provision profile.mobileprovision
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Ipa,
  [string]$P12 = '',
  [string]$P12Password = '',
  [string]$Provision = '',
  [string]$BundleId = 'local.dshm.mobile',
  [string]$Out = 'DSHMobile-signed.ipa',
  [string]$Zsign = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Ipa)) { throw "找不到 $Ipa" }

if (-not $Zsign) {
  foreach ($candidate in @(".\zsign.exe", ".\tools\zsign.exe", "zsign")) {
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($cmd) { $Zsign = $cmd.Source; break }
  }
}

if (-not $Zsign) {
  Write-Host ''
  Write-Host '  没有 zsign.exe。两条路：' -ForegroundColor Yellow
  Write-Host '  1) 下 zsign：https://github.com/zhlynn/zsign/releases 解出 zsign.exe 放到当前目录，再跑一次'
  Write-Host '  2) 直接用 Sideloadly：https://sideloadly.io  安装后把 ipa 拖进去，用 Apple ID 登录，'
  Write-Host '     它会自动申请免费证书并签名。免费账号签出来的 App 7 天过期，到期重签一次即可。'
  Write-Host ''
  exit 1
}

if (-not $P12 -or -not $Provision) {
  throw 'zsign 需要 -P12 与 -Provision（以及 -P12Password）。没有证书就走 Sideloadly。'
}

$zargs = @($Ipa, '-o', $Out)
$zargs += @('-k', $P12, '-p', $P12Password)
$zargs += @('-m', $Provision)
if ($BundleId) { $zargs += @('-b', $BundleId) }

& $Zsign @zargs
if ($LASTEXITCODE -ne 0) { throw "zsign 失败，退出码 $LASTEXITCODE" }

Write-Host "签好了：$Out" -ForegroundColor Green
Write-Host '装法：iPhone 连电脑 → Sideloadly 选这个 ipa → 输 Apple ID → Start；或用 AltStore / TrollStore。'
