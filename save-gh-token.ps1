# 安全地保存新的 GitHub PAT（令牌不进入聊天记录、不进入仓库）
#
# 为什么不设成用户环境变量 GH_TOKEN：
#   gh CLI 会优先读取 GH_TOKEN，一旦设置，gh 就从不过期的 OAuth（gho_）
#   切换到 PAT —— 反而让 365 天后 gh 也跟着失效。
#   所以这里单独存一个文件，只有明确需要用的时候才临时读它。
#
# 存储位置：%USERPROFILE%\.dsh\secrets\github-pat.txt
# 权限：只授予当前用户，其他账户和 SYSTEM 之外全部移除。

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '  把新生成的 token 粘贴到这里（输入不会回显），然后回车：' -ForegroundColor Cyan
$secure = Read-Host -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Host '  没有输入，退出。' -ForegroundColor Yellow
    exit 1
}
if ($token -notmatch '^gh[pousr]_[A-Za-z0-9]{20,}$') {
    Write-Host '  格式不像 GitHub token（应以 ghp_ / github_pat_ 开头），仍继续但请自行确认。' -ForegroundColor Yellow
}

# ---- 先验证能不能用 ----
Write-Host ''
Write-Host '  正在验证 token ...' -ForegroundColor Cyan
try {
    $resp = Invoke-WebRequest -Uri 'https://api.github.com/user' -Headers @{
        Authorization          = "Bearer $token"
        Accept                 = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    } -UseBasicParsing -TimeoutSec 20
    $user = $resp.Content | ConvertFrom-Json
    $scopes = $resp.Headers['X-OAuth-Scopes']
    $expires = $resp.Headers['github-authentication-token-expiration']
    Write-Host "  账号     : $($user.login)" -ForegroundColor Green
    Write-Host "  权限范围 : $scopes" -ForegroundColor Green
    if ($expires) { Write-Host "  到期时间 : $expires" -ForegroundColor Green }
    else { Write-Host '  到期时间 : 无（不会自动过期）' -ForegroundColor Green }
} catch {
    Write-Host "  验证失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host '  未保存。请确认 token 是否正确、是否有 repo 权限。' -ForegroundColor Red
    exit 1
}

# ---- 保存到受保护的文件 ----
$dir = Join-Path $env:USERPROFILE '.dsh\secrets'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$file = Join-Path $dir 'github-pat.txt'
Set-Content -Path $file -Value $token -NoNewline -Encoding ascii

# 锁 ACL：只留当前用户
try {
    icacls $file /inheritance:r /grant:r "$($env:USERNAME):(R,W)" 2>&1 | Out-Null
} catch {
    Write-Host '  提示：ACL 收紧失败，文件仍已保存。' -ForegroundColor Yellow
}

Write-Host ''
Write-Host "  已保存到：$file" -ForegroundColor Green
Write-Host '  权限：仅当前用户可读写' -ForegroundColor Green
Write-Host ''
Write-Host '  以后需要用到时，临时读入即可（不影响 gh CLI 的 OAuth 登录）：' -ForegroundColor DarkGray
Write-Host '    $env:GH_TOKEN = Get-Content "$env:USERPROFILE\.dsh\secrets\github-pat.txt" -Raw' -ForegroundColor DarkGray
Write-Host ''
