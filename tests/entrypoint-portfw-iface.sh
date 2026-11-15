#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_USQUE="$TMP_DIR/usque"
CAPTURE_FILE="$TMP_DIR/args"
ENTRYPOINT_UNDER_TEST="$TMP_DIR/docker-entrypoint.sh"
CONFIG_FILE="$TMP_DIR/config.json"
TUN_DEVICE="$TMP_DIR/tun"
STDERR_FILE="$TMP_DIR/stderr"

cat > "$FAKE_USQUE" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$@" > "$CAPTURE_FILE"
SCRIPT
chmod +x "$FAKE_USQUE"
touch "$CONFIG_FILE" "$TUN_DEVICE"
sed -e "s#/bin/usque#$FAKE_USQUE#g" \
    -e "s#/dev/net/tun#$TUN_DEVICE#g" \
    "$ROOT_DIR/docker-entrypoint.sh" > "$ENTRYPOINT_UNDER_TEST"
chmod +x "$ENTRYPOINT_UNDER_TEST"

# portfw 没有 -b/-p/-u/-w：代理专用变量必须被忽略，DNS 与用户参数保留
CAPTURE_FILE="$CAPTURE_FILE" \
USQUE_BANNER=false \
USQUE_CONFIG="$CONFIG_FILE" \
USQUE_MODE=portfw \
USQUE_BIND=0.0.0.0 \
USQUE_PORT=1080 \
USQUE_USER=user \
USQUE_PASS=pass \
USQUE_DNS="1.1.1.1 1.0.0.1" \
USQUE_INTERFACE_NAME=warp0 \
  "$ENTRYPOINT_UNDER_TEST" -L 127.0.0.1:8080:100.96.0.2:8080 2> "$STDERR_FILE"

cat > "$TMP_DIR/expected" <<EOF_EXPECTED
-c
$CONFIG_FILE
portfw
-L
127.0.0.1:8080:100.96.0.2:8080
-d
1.1.1.1
-d
1.0.0.1
EOF_EXPECTED
diff -u "$TMP_DIR/expected" "$CAPTURE_FILE"
for var in USQUE_BIND USQUE_PORT USQUE_USER USQUE_PASS USQUE_INTERFACE_NAME; do
  grep -Fq "portfw 不支持 $var，已忽略" "$STDERR_FILE"
done

# nativetun：USQUE_INTERFACE_NAME 映射为 -n
CAPTURE_FILE="$CAPTURE_FILE" \
USQUE_BANNER=false \
USQUE_CONFIG="$CONFIG_FILE" \
USQUE_MODE=nativetun \
USQUE_INTERFACE_NAME=warp0 \
USQUE_PERSIST=true \
  "$ENTRYPOINT_UNDER_TEST" 2> "$STDERR_FILE"

cat > "$TMP_DIR/expected" <<EOF_EXPECTED
-c
$CONFIG_FILE
nativetun
-n
warp0
--persist
EOF_EXPECTED
diff -u "$TMP_DIR/expected" "$CAPTURE_FILE"

# 其他模式忽略 USQUE_INTERFACE_NAME（socks 的 -n 不存在）
CAPTURE_FILE="$CAPTURE_FILE" \
USQUE_BANNER=false \
USQUE_CONFIG="$CONFIG_FILE" \
USQUE_MODE=socks \
USQUE_INTERFACE_NAME=warp0 \
  "$ENTRYPOINT_UNDER_TEST" 2> "$STDERR_FILE"

cat > "$TMP_DIR/expected" <<EOF_EXPECTED
-c
$CONFIG_FILE
socks
EOF_EXPECTED
diff -u "$TMP_DIR/expected" "$CAPTURE_FILE"
grep -Fq "socks 不支持 USQUE_INTERFACE_NAME，已忽略" "$STDERR_FILE"
