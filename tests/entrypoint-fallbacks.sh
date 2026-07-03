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

cat > "$FAKE_USQUE" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$@" > "$CAPTURE_FILE"
SCRIPT
chmod +x "$FAKE_USQUE"

sed "s#/bin/usque#$FAKE_USQUE#g" "$ROOT_DIR/docker-entrypoint.sh" > "$ENTRYPOINT_UNDER_TEST"
chmod +x "$ENTRYPOINT_UNDER_TEST"

cat > "$CONFIG_FILE" <<'JSON'
{"license":"personal","ipv4":"172.16.0.2"}
JSON

assert_bad_config_falls_back_to_socks() {
  expected="$TMP_DIR/expected-bad-config"

  CAPTURE_FILE="$CAPTURE_FILE" \
  USQUE_CONFIG="$CONFIG_FILE" \
  USQUE_MODE="bad-mode" \
  USQUE_PORT="abc" \
  USQUE_HTTP2="maybe maybe" \
  USQUE_INSECURE="nope" \
  USQUE_BANNER="wat" \
  USQUE_USER="user-only" \
    "$ENTRYPOINT_UNDER_TEST" 2> "$STDERR_FILE"

  cat > "$expected" <<EOF_EXPECTED
-c
$CONFIG_FILE
socks
-p
1080
-s
consumer-masque.cloudflareclient.com
EOF_EXPECTED

  diff -u "$expected" "$CAPTURE_FILE"
  grep -Fq "USQUE_MODE=bad-mode 无效，已回退为 socks" "$STDERR_FILE"
  grep -Fq "USQUE_PORT=abc 无效，已回退为 1080" "$STDERR_FILE"
  grep -Fq "USQUE_HTTP2=maybe maybe 无效，已回退为 false" "$STDERR_FILE"
  grep -Fq "USQUE_INSECURE=nope 无效，已回退为 false" "$STDERR_FILE"
  grep -Fq "USQUE_BANNER=wat 无效，已回退为 true" "$STDERR_FILE"
  grep -Fq "认证配置不完整，已禁用代理认证" "$STDERR_FILE"
  grep -Fq "docker-usque" "$STDERR_FILE"
}

assert_l4_ignores_unsupported_env_and_falls_back_port() {
  expected="$TMP_DIR/expected-l4"
  : > "$STDERR_FILE"

  CAPTURE_FILE="$CAPTURE_FILE" \
  USQUE_BANNER="false" \
  USQUE_CONFIG="$CONFIG_FILE" \
  USQUE_MODE="l4-socks" \
  USQUE_PORT="99999" \
  USQUE_SNI="zt-masque.cloudflareclient.com" \
  USQUE_MTU="1200" \
  USQUE_HTTP2="true" \
  USQUE_DNS="1.1.1.1" \
    "$ENTRYPOINT_UNDER_TEST" 2> "$STDERR_FILE"

  cat > "$expected" <<EOF_EXPECTED
-c
$CONFIG_FILE
l4-socks
-p
1080
-d
1.1.1.1
EOF_EXPECTED

  diff -u "$expected" "$CAPTURE_FILE"
  grep -Fq "USQUE_PORT=99999 无效，已回退为 1080" "$STDERR_FILE"
  grep -Fq "l4-socks 不支持 USQUE_SNI，已忽略" "$STDERR_FILE"
  grep -Fq "l4-socks 不支持 USQUE_MTU，已忽略" "$STDERR_FILE"
  grep -Fq "l4-socks 不支持 USQUE_HTTP2，已忽略" "$STDERR_FILE"
}

assert_bad_config_falls_back_to_socks
assert_l4_ignores_unsupported_env_and_falls_back_port
