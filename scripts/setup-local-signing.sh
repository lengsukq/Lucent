#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_NAME="Lucent Local Signer"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

CREATED_CERT=0
echo "==> 检查钥匙串中是否已存在 '$CERT_NAME' 代码签名证书..."
if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -Fq "\"$CERT_NAME\""; then
  echo "✓ 已检测到有效证书 '$CERT_NAME'，跳过创建。"
else
  # 优先使用 macOS 自带 LibreSSL (/usr/bin/openssl)：OpenSSL 3/4 默认 PKCS12 加密算法会导致 security import 报错
  OPENSSL_BIN="/usr/bin/openssl"
  if [[ ! -x "$OPENSSL_BIN" ]]; then
    OPENSSL_BIN="$(command -v openssl)"
  fi

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  cat > "$TMP_DIR/cert.cnf" <<'EOF'
[ req ]
default_bits       = 2048
distinguished_name = dn
x509_extensions    = v3_codesign
prompt             = no

[ dn ]
CN = Lucent Local Signer
O  = Lucent Local Build

[ v3_codesign ]
basicConstraints = critical,CA:FALSE
keyUsage         = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

  echo "==> 生成 10 年有效期自签名代码签名证书..."
  "$OPENSSL_BIN" req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP_DIR/lucent.key" \
    -out "$TMP_DIR/lucent.crt" \
    -days 3650 \
    -config "$TMP_DIR/cert.cnf"

  P12_PASS="lucent-local-$(date +%s)"
  "$OPENSSL_BIN" pkcs12 -export \
    -inkey "$TMP_DIR/lucent.key" \
    -in "$TMP_DIR/lucent.crt" \
    -out "$TMP_DIR/lucent.p12" \
    -name "$CERT_NAME" \
    -passout "pass:$P12_PASS"

  echo "==> 导入证书与私钥到登录钥匙串（随后系统将弹窗请您授权一次信任代码签名）..."
  security import "$TMP_DIR/lucent.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign -T /usr/bin/security
  security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP_DIR/lucent.crt"
  CREATED_CERT=1
fi

if [[ "$CREATED_CERT" == "1" ]]; then
  echo "==> 重置旧临时 Ad-hoc 残留的 TCC 记录（首次授权新证书后将尽量延续）..."
  tccutil reset Accessibility app.lucent.macos || true
  tccutil reset ScreenCapture app.lucent.macos || true
fi

echo "==> 重新打包并签名安装 Lucent.app..."
bash "$ROOT_DIR/scripts/install-macos.sh"

echo ""
echo "✓ 稳定签名配置完成！"
echo "  请运行: open /Applications/Lucent.app"
echo "  之后最后一次授权「辅助功能 / 屏幕录制」，未来任意重装或升级均不再重复弹窗。"
