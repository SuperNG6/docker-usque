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

CAPTURE_FILE="$CAPTURE_FILE" \
USQUE_CONFIG="$CONFIG_FILE" \
USQUE_MODE="l4-socks" \
USQUE_VERSION="v2.0.0" \
USQUE_IMAGE_VARIANT="lite" \
USQUE_BIND="127.0.0.1" \
USQUE_PORT="18080" \
USQUE_USER="user" \
USQUE_PASS="pass" \
USQUE_DNS="1.1.1.1 1.0.0.1" \
USQUE_MTU="1200" \
USQUE_HTTP2="true" \
USQUE_INSECURE="true" \
  "$ENTRYPOINT_UNDER_TEST" 2> "$STDERR_FILE"

grep -Fq "docker-usque" "$STDERR_FILE"
grep -Fq "version   : v2.0.0, variant=lite" "$STDERR_FILE"
grep -Fq "mode      : l4-socks" "$STDERR_FILE"
grep -Fq "config    : $CONFIG_FILE" "$STDERR_FILE"
grep -Fq "listen    : 127.0.0.1:18080" "$STDERR_FILE"
grep -Fq "auth      : enabled" "$STDERR_FILE"
grep -Fq "dns       : 1.1.1.1 1.0.0.1" "$STDERR_FILE"
grep -Fq "transport : quic" "$STDERR_FILE"
if grep -Fq "pass" "$STDERR_FILE"; then
  exit 1
fi
if grep -Fq "user" "$STDERR_FILE"; then
  exit 1
fi

: > "$STDERR_FILE"
CAPTURE_FILE="$CAPTURE_FILE" \
USQUE_BANNER="false" \
USQUE_CONFIG="$CONFIG_FILE" \
USQUE_MODE="l4-http-proxy" \
  "$ENTRYPOINT_UNDER_TEST" 2> "$STDERR_FILE"

if grep -Fq "docker-usque" "$STDERR_FILE"; then
  exit 1
fi
