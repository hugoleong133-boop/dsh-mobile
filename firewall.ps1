<#
.SYNOPSIS
  给 dsh-mobile 放行入站端口（需要在"以管理员身份运行"的 PowerShell 里执行）。

.DESCRIPTION
  普通权限改不了 Windows 防火墙，所以这一步单独拆出来。只放行当前专用/域网络，
  不对公用网络开放——咖啡厅那种 Wi-Fi 不该把整台工作站的控制权暴露出去。

.EXAMPLE
  .\firewall.ps1 -Port 8765

.EXAMPLE
  .\firewall.ps1 -Port 8765 -Remove
#>
[CmdletBinding()]
param(
  [int]$Port = 8765,
  [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$name = "DSH Mobile ($Port)"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  throw "需要管理员权限：右键 PowerShell → 以管理员身份运行，再执行 .\firewall.ps1 -Port $Port"
}

if ($Remove) {
  Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  Write-Host "已删除防火墙规则 $name" -ForegroundColor Green
  exit 0
}

Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule

New-NetFirewallRule `
  -DisplayName $name `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort $Port `
  -Profile Private, Domain `
  -Description "dsh-mobile: 让 iPhone 访问本机 DSH Web 会话" | Out-Null

Write-Host "已放行 TCP $Port（仅专用/域网络）。" -ForegroundColor Green
Write-Host "撤销：.\firewall.ps1 -Port $Port -Remove"
