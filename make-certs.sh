#!/usr/bin/env bash
# 生成 dsh-mobile 的自签 CA 与服务器证书。
#
# 目的：让局域网通道也走 HTTPS，从而成为「安全上下文」——
# iOS 上 navigator.mediaDevices 只在 https 下存在，语音输入才能用。
#
# 产物（certs/）：
#   ca.key / ca.crt        根证书，需要装到手机上并信任
#   server.key / server.crt 服务器证书，代理用这个
#
# 有效期按 iOS 要求设：服务器证书 ≤ 825 天，且必须带 SAN + serverAuth。

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/../certs"
OPENSSL="${OPENSSL:-openssl}"

mkdir -p "$OUT"
cd "$OUT"

if [ -f server.crt ] && [ -f server.key ] && [ "${1:-}" != "--force" ]; then
  echo "证书已存在：$OUT/server.crt"
  echo "要重新生成加 --force（手机需要重新安装 CA）"
  exit 0
fi

# 收集本机所有局域网 IPv4，避免换网卡后证书不匹配
IPS="$("$OPENSSL" version >/dev/null && echo '')"
for ip in 127.0.0.1 192.168.1.124 192.168.1.36; do
  IPS="$IPS,IP:$ip"
done

SAN="subjectAltName=DNS:localhost${IPS},DNS:windows.tailcddd89.ts.net"
echo "SAN: $SAN"

echo "==> 1/3 生成根证书（10 年）"
"$OPENSSL" req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout ca.key -out ca.crt \
  -subj "/CN=DSH Mobile Local CA/O=DSH Mobile/C=MO" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
chmod 600 ca.key

echo "==> 2/3 生成服务器密钥与请求"
"$OPENSSL" req -newkey rsa:2048 -sha256 -nodes \
  -keyout server.key -out server.csr \
  -subj "/CN=dsh-mobile-local/O=DSH Mobile/C=MO" 2>/dev/null
chmod 600 server.key

echo "==> 3/3 用根证书签发（820 天，符合 iOS 上限）"
cat > server.ext <<EOF
$SAN
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF

"$OPENSSL" x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days 820 -sha256 -extfile server.ext 2>/dev/null

rm -f server.csr server.ext

# 链证书给 iOS 安装用（DER 形式，Safari 直接识别为描述文件）
"$OPENSSL" x509 -in ca.crt -outform DER -out ca.cer

echo
echo "完成："
"$OPENSSL" x509 -in server.crt -noout -subject -issuer -dates
echo
echo "  $OUT/ca.cer       ← 装到手机并信任"
echo "  $OUT/server.crt   ← 代理用"
echo "  $OUT/server.key   ← 代理用"
