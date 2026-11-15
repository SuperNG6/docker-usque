#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_USQUE="$TMP_DIR/usque"
CAPTURE_FILE="$TMP_DIR/args"
ENTRYPOINT_UNDER_TEST="$TMP_DIR/docker-entrypoint.sh"
CONFIG_FILE="$TMP_DIR/config.json"
STDERR_FILE="$TMP_DIR/stderr"

# 每次调用追加一行，便于发现意外的 register 调用
cat > "$FAKE_USQUE" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" >> "$CAPTURE_FILE"
SCRIPT
chmod +x "$FAKE_USQUE"
sed "s#/bin/usque#$FAKE_USQUE#g" "$ROOT_DIR/docker-entrypoint.sh" > "$ENTRYPOINT_UNDER_TEST"
chmod +x "$ENTRYPOINT_UNDER_TEST"

# account 子命令原样透传：无配置时不自动注册，也不回退为 socks，代理变量不注入
: > "$CAPTURE_FILE"
CAPTURE_FILE="$CAPTURE_FILE" \
USQUE_CONFIG="$CONFIG_FILE" \
USQUE_PORT=1080 \
USQUE_SNI=example.com \
  "$ENTRYPOINT_UNDER_TEST" account set LICENSE-KEY 2> "$STDERR_FILE"

printf '%s\n' "-c $CONFIG_FILE account set LICENSE-KEY" > "$TMP_DIR/expected"
diff -u "$TMP_DIR/expected" "$CAPTURE_FILE"
if grep -Fq "已回退为 socks" "$STDERR_FILE"; then
  echo 'account was treated as an invalid mode' >&2
  exit 1
fi

# 非数字 MTU 被忽略；合法 MTU 正常传递
touch "$CONFIG_FILE"
: > "$CAPTURE_FILE"
CAPTURE_FILE="$CAPTURE_FILE" \
USQUE_BANNER=false \
USQUE_CONFIG="$CONFIG_FILE" \
USQUE_MODE=socks \
USQUE_MTU=abc \
  "$ENTRYPOINT_UNDER_TEST" 2> "$STDERR_FILE"

printf '%s\n' "-c $CONFIG_FILE socks" > "$TMP_DIR/expected"
diff -u "$TMP_DIR/expected" "$CAPTURE_FILE"
grep -Fq "USQUE_MTU=abc 无效，已忽略" "$STDERR_FILE"

: > "$CAPTURE_FILE"
CAPTURE_FILE="$CAPTURE_FILE" \
USQUE_BANNER=false \
USQUE_CONFIG="$CONFIG_FILE" \
USQUE_MODE=socks \
USQUE_MTU=1200 \
  "$ENTRYPOINT_UNDER_TEST" 2> "$STDERR_FILE"

printf '%s\n' "-c $CONFIG_FILE socks -m 1200" > "$TMP_DIR/expected"
diff -u "$TMP_DIR/expected" "$CAPTURE_FILE"
