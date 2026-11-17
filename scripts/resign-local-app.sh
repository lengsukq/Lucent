#!/usr/bin/env bash
set -euo pipefail

# 面向普通下载 DMG 用户的本机固定签名脚本：
# 用当前 Mac 上唯一的本地证书（或本机已有 Apple Development 证书）对 /Applications/Lumakey.app 原地重签，
# 从而在未来每次下载新版 DMG 覆盖安装后尽可能延续「辅助功能 / 屏幕录制」授权，且不依赖作者私钥或 $99 证书。

APP_PATH="/Applications/Lumakey.app"
RESET_TCC=0
NO_LAUNCH=0

for arg in "$@"; do
  case "$arg" in
    --reset-tcc) RESET_TCC=1 ;;
    --no-launch) NO_LAUNCH=1 ;;
    -h|--help)
      echo "用法: bash resign-local-app.sh [/Applications/Lumakey.app] [--reset-tcc] [--no-launch]"
      exit 0
      ;;
    *)
      APP_PATH="$arg"
      ;;
  esac
done

if [[ ! -d "$APP_PATH" ]]; then
  echo "错误：未找到 $APP_PATH。请先打开 Lumakey.dmg 并将 Lumakey.app 拖入「应用程序」文件夹。" >&2
  exit 1
fi

CERT_NAME="Lumakey Local Signer"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
SYSTEM_KEYCHAIN="/Library/Keychains/System.keychain"
CREATED_NEW_CERT=0

pick_existing_identity() {
  if [[ -n "${LUMAKEY_SIGN_IDENTITY:-}" ]]; then
    echo "$LUMAKEY_SIGN_IDENTITY"
    return 0
  fi
  local identities existing_auth pattern match count
  identities=$(security find-identity -v -p codesigning 2>/dev/null || true)

  if [[ -d "$APP_PATH" ]]; then
    local app_info
    app_info=$(codesign -dvv "$APP_PATH" 2>&1 || true)
    if ! printf '%s\n' "$app_info" | grep -q 'Signature=adhoc'; then
      existing_auth=$(printf '%s\n' "$app_info" | sed -n 's/^Authority=//p' | head -n 1 || true)
      if [[ -n "$existing_auth" ]] && printf '%s\n' "$identities" | grep -F "\"$existing_auth\"" >/dev/null 2>&1; then
        echo "$existing_auth"
        return 0
      fi
    fi
  fi

  if printf '%s\n' "$identities" | grep -F "\"$CERT_NAME\"" >/dev/null 2>&1; then
    echo "$CERT_NAME"
    return 0
  fi

  for pattern in '"Developer ID Application:[^"]*"' '"Apple Development:[^"]*"' '"Mac Developer:[^"]*"'; do
    match=$(printf '%s\n' "$identities" | grep -oE "$pattern" | tr -d '"' || true)
    count=$(printf '%s\n' "$match" | sed '/^$/d' | wc -l | tr -d ' ')
    if [[ "$count" == "1" ]]; then
      printf '%s\n' "$match" | head -n 1
      return 0
    fi
  done
  return 1
}

SIGN_ID="$(pick_existing_identity || true)"

if [[ -z "$SIGN_ID" ]]; then
  OPENSSL_BIN="/usr/bin/openssl"
  if [[ ! -x "$OPENSSL_BIN" ]]; then
    OPENSSL_BIN="$(command -v openssl)"
  fi

  TMP_CERT_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_CERT_DIR"' EXIT

  cat > "$TMP_CERT_DIR/cert.cnf" <<'EOF'
[ req ]
default_bits       = 2048
distinguished_name = dn
x509_extensions    = v3_codesign
prompt             = no

[ dn ]
CN = Lumakey Local Signer
O  = Lumakey Local Build

[ v3_codesign ]
basicConstraints = critical,CA:FALSE
keyUsage         = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

  echo "==> 首次初始化：正在本机生成 10 年期固定代码签名证书 '$CERT_NAME'..."
  "$OPENSSL_BIN" req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP_CERT_DIR/lumakey.key" \
    -out "$TMP_CERT_DIR/lumakey.crt" \
    -days 3650 \
    -config "$TMP_CERT_DIR/cert.cnf" >/dev/null 2>&1

  P12_PASS="lumakey-local-$(date +%s)"
  "$OPENSSL_BIN" pkcs12 -export \
    -inkey "$TMP_CERT_DIR/lumakey.key" \
    -in "$TMP_CERT_DIR/lumakey.crt" \
    -out "$TMP_CERT_DIR/lumakey.p12" \
    -name "$CERT_NAME" \
    -passout "pass:$P12_PASS"

  echo "==> 导入私钥到登录钥匙串（后续系统将请求一次信任代码签名授权）..."
  security import "$TMP_CERT_DIR/lumakey.p12" -k "$LOGIN_KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign -T /usr/bin/security >/dev/null

  echo "==> 将公钥证书设为系统级代码签名信任（输入本机开机密码后，系统权限服务 tccd 即可稳定识别）..."
  if sudo -n true 2>/dev/null || [[ -t 0 ]]; then
    if ! sudo security add-trusted-cert -d -r trustRoot -p codeSign -k "$SYSTEM_KEYCHAIN" "$TMP_CERT_DIR/lumakey.crt" 2>/dev/null; then
      security add-trusted-cert -d -r trustRoot -p codeSign -k "$LOGIN_KEYCHAIN" "$TMP_CERT_DIR/lumakey.crt" || true
    fi
  else
    security add-trusted-cert -d -r trustRoot -p codeSign -k "$LOGIN_KEYCHAIN" "$TMP_CERT_DIR/lumakey.crt" || true
  fi

  SIGN_ID="$CERT_NAME"
  CREATED_NEW_CERT=1
else
  echo "==> 检测到本机已有稳定签名身份：$SIGN_ID"
fi

if [[ "$CREATED_NEW_CERT" == "1" || "$RESET_TCC" == "1" ]]; then
  echo "==> 清理旧 Ad-hoc 残留的 TCC 授权缓存（仅首次切换证书时执行一次）..."
  tccutil reset Accessibility app.lumakey.macos 2>/dev/null || true
  tccutil reset ScreenCapture app.lumakey.macos 2>/dev/null || true
fi

WAS_RUNNING=0
if pgrep -x Lumakey >/dev/null 2>&1; then
  WAS_RUNNING=1
  echo "==> 正在暂停运行中的 Lumakey 以便重签..."
  pkill -TERM -x Lumakey || true
  for _ in $(seq 1 20); do
    if ! pgrep -x Lumakey >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  pkill -KILL -x Lumakey >/dev/null 2>&1 || true
fi

echo "==> 清理隔离标记并提取现有 Entitlements..."
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

WORK_TMP="$(mktemp -d)"
cleanup_all() {
  rm -rf "$WORK_TMP"
  if [[ -n "${TMP_CERT_DIR:-}" ]]; then
    rm -rf "$TMP_CERT_DIR"
  fi
}
trap cleanup_all EXIT

ENT_FILE="$WORK_TMP/Lumakey.entitlements"
if ! codesign -d --entitlements - --xml "$APP_PATH" > "$ENT_FILE" 2>/dev/null || ! grep -q "<plist" "$ENT_FILE"; then
  cat > "$ENT_FILE" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
EOF
fi

echo "==> 正在使用 '$SIGN_ID' 对 $APP_PATH 执行本机原地重签..."
if [[ -x "$APP_PATH/Contents/Helpers/macos-rdp-daemon" ]]; then
  codesign --force --sign "$SIGN_ID" --identifier "app.lumakey.macos.rdp" "$APP_PATH/Contents/Helpers/macos-rdp-daemon"
fi
if [[ -x "$APP_PATH/Contents/MacOS/lumakey-mcp" ]]; then
  codesign --force --sign "$SIGN_ID" --identifier "app.lumakey.macos.mcp" "$APP_PATH/Contents/MacOS/lumakey-mcp"
fi
codesign --force --entitlements "$ENT_FILE" --sign "$SIGN_ID" --identifier "app.lumakey.macos" "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_PATH" || true
fi

echo ""
echo "✓ 已完成本机固定重签：$APP_PATH（签名：$SIGN_ID）"
if [[ "$CREATED_NEW_CERT" == "1" ]]; then
  echo "  接下来最后一次授出「辅助功能 / 屏幕录制」权限；"
  echo "  以后每次下载新版 DMG 拖入「应用程序」后，再跑一遍本命令即可尽量保留既有授权。"
else
  echo "  已保留你原有的系统授权记录（如仍偶发失效，可加 --reset-tcc 参数重置一次）。"
fi

if [[ "$NO_LAUNCH" == "0" && ( "$WAS_RUNNING" == "1" || "$CREATED_NEW_CERT" == "1" ) ]]; then
  open "$APP_PATH"
fi
