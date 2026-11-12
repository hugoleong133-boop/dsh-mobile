#!/usr/bin/env bash
# dsh-mobile 服务器中转 · 一键配置（在你有公网 IP 的那台服务器上跑）
#
#   sudo ./setup-relay.sh dsh.example.com
#
# 做四件事：
#   1. 装 nginx + certbot
#   2. 签发 Let's Encrypt 证书（需要域名已解析到本机）
#   3. 落 nginx 反代配置（含 WebSocket / 长超时 / 不缓冲）
#   4. 建一个只有端口转发权限的隧道用户
#
# 之后在公司电脑上跑：
#   .\tunnel.ps1 -Mode ssh -SshTarget dsh-relay@服务器IP -PublicUrl https://dsh.example.com

set -euo pipefail

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  echo "用法: sudo $0 <域名>" >&2
  echo "例:   sudo $0 dsh.example.com" >&2
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "需要 root：sudo $0 $DOMAIN" >&2
  exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELAY_USER="dsh-relay"
RELAY_PORT="8765"

echo "==> 1/4 安装 nginx 与 certbot"
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx certbot python3-certbot-nginx >/dev/null
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y -q nginx certbot python3-certbot-nginx >/dev/null
else
  echo "不认识的包管理器，请手动装 nginx 与 certbot" >&2
  exit 1
fi

echo "==> 2/4 建隧道用户 $RELAY_USER（只给端口转发，不给 shell 登录权限）"
if ! id "$RELAY_USER" >/dev/null 2>&1; then
  useradd -m -s /usr/sbin/nologin "$RELAY_USER" 2>/dev/null || useradd -m -s /sbin/nologin "$RELAY_USER"
fi
install -d -m 700 -o "$RELAY_USER" -g "$RELAY_USER" "/home/$RELAY_USER/.ssh"
touch "/home/$RELAY_USER/.ssh/authorized_keys"
chown "$RELAY_USER:$RELAY_USER" "/home/$RELAY_USER/.ssh/authorized_keys"
chmod 600 "/home/$RELAY_USER/.ssh/authorized_keys"

echo "    把公司电脑的公钥追加进 /home/$RELAY_USER/.ssh/authorized_keys"
echo "    （公司电脑上：type \$env:USERPROFILE\\.ssh\\id_ed25519.pub）"

echo "==> 3/4 配置 sshd：允许端口转发，但不给 shell"
SSHD_SNIPPET="/etc/ssh/sshd_config.d/90-dsh-relay.conf"
mkdir -p /etc/ssh/sshd_config.d
cat > "$SSHD_SNIPPET" <<'EOF'
# dsh-mobile 反向隧道
# 绑 127.0.0.1 就够：外面走 nginx 反代，不需要 GatewayPorts
Match User dsh-relay
    AllowTcpForwarding remote
    GatewayPorts no
    X11Forwarding no
    PermitTTY no
    ForceCommand /usr/sbin/nologin
    AllowAgentForwarding no
    PermitOpen none
EOF
sshd -t && systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

echo "==> 4/4 落 nginx 配置"
CONF_SRC="$HERE/nginx-dsh.conf"
CONF_DST="/etc/nginx/conf.d/dsh.conf"
if [ ! -f "$CONF_SRC" ]; then
  echo "缺少 $CONF_SRC" >&2
  exit 1
fi
sed "s/dsh\.example\.com/$DOMAIN/g" "$CONF_SRC" > "$CONF_DST"

mkdir -p /var/www/html
nginx -t

echo "==> 申请证书（需要 $DOMAIN 已解析到本机）"
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  systemctl stop nginx 2>/dev/null || true
  certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos \
    --register-unsafely-without-email || {
      echo "!! 证书申请失败。域名没解析好，或者 80 端口被占用。" >&2
      echo "   先用 nginx 的 80 配置跑起来，再 certbot --nginx -d $DOMAIN" >&2
    }
  systemctl start nginx 2>/dev/null || true
fi

nginx -t
systemctl enable --now nginx
systemctl reload nginx

cat <<EOF

完成。

  手机访问   https://$DOMAIN/?k=<PIN>
  状态自检   https://$DOMAIN/__m/status

在公司电脑上执行（管理员 PowerShell）：

  ssh-keygen -t ed25519 -N '""' -f \$env:USERPROFILE\\.ssh\\id_ed25519   # 没有密钥才需要
  type \$env:USERPROFILE\\.ssh\\id_ed25519.pub                            # 贴进服务器 authorized_keys

  .\\tunnel.ps1 -Mode ssh -SshTarget $RELAY_USER@<服务器IP> -PublicUrl https://$DOMAIN

验证隧道起来没有：

  ss -ltnp | grep $RELAY_PORT        # 服务器上应看到 127.0.0.1:$RELAY_PORT
  curl -s https://$DOMAIN/__m/status # 应回 {"ok":true,...}

EOF
