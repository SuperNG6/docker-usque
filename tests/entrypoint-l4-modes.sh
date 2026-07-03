#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_USQUE="$TMP_DIR/usque"
CAPTURE_FILE="$TMP_DIR/args"
ENTRYPOINT_UNDER_TEST="$TMP_DIR/docker-entrypoint.sh"
CONFIG_FILE="$TMP_DIR/config.json"

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

assert_l4_proxy_args() {
  mode="$1"
  expected="$TMP_DIR/expected-$mode"

  CAPTURE_FILE="$CAPTURE_FILE" \
  USQUE_BANNER="false" \
  USQUE_CONFIG="$CONFIG_FILE" \
  USQUE_MODE="$mode" \
  USQUE_BIND="127.0.0.1" \
  USQUE_PORT="18080" \
  USQUE_USER="user" \
  USQUE_PASS="pass" \
  USQUE_DNS="1.1.1.1 1.0.0.1" \
  USQUE_MTU="1200" \
  USQUE_HTTP2="true" \
  USQUE_INSECURE="true" \
    "$ENTRYPOINT_UNDER_TEST"

  cat > "$expected" <<EOF_EXPECTED
-c
$CONFIG_FILE
$mode
-w
pass
-u
user
-p
18080
-b
127.0.0.1
-d
1.1.1.1
-d
1.0.0.1
EOF_EXPECTED

  diff -u "$expected" "$CAPTURE_FILE"
  if grep -Fxq -- "-s" "$CAPTURE_FILE" ||
     grep -Fxq -- "-m" "$CAPTURE_FILE" ||
     grep -Fxq -- "--http2" "$CAPTURE_FILE"; then
    exit 1
  fi
}

assert_l4_proxy_args l4-socks
assert_l4_proxy_args l4-http-proxy
