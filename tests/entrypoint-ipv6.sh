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

for mode in socks http-proxy l4-socks l4-http-proxy nativetun portfw; do
  CAPTURE_FILE="$CAPTURE_FILE" \
  USQUE_BANNER=false \
  USQUE_CONFIG="$CONFIG_FILE" \
  USQUE_MODE="$mode" \
  USQUE_IPV6=true \
    "$ENTRYPOINT_UNDER_TEST"

  cat > "$TMP_DIR/expected" <<EOF_EXPECTED
-c
$CONFIG_FILE
$mode
--ipv6
EOF_EXPECTED
  diff -u "$TMP_DIR/expected" "$CAPTURE_FILE"
done

for value in false invalid; do
  CAPTURE_FILE="$CAPTURE_FILE" \
  USQUE_BANNER=false \
  USQUE_CONFIG="$CONFIG_FILE" \
  USQUE_MODE=socks \
  USQUE_IPV6="$value" \
    "$ENTRYPOINT_UNDER_TEST" 2> "$TMP_DIR/stderr"

  cat > "$TMP_DIR/expected" <<EOF_EXPECTED
-c
$CONFIG_FILE
socks
EOF_EXPECTED
  diff -u "$TMP_DIR/expected" "$CAPTURE_FILE"
done
grep -Fq 'USQUE_IPV6=invalid 无效，已回退为 false' "$TMP_DIR/stderr"

CAPTURE_FILE="$CAPTURE_FILE" \
USQUE_BANNER=false \
USQUE_CONFIG="$CONFIG_FILE" \
USQUE_MODE=register \
USQUE_IPV6=true \
  "$ENTRYPOINT_UNDER_TEST" 2> "$TMP_DIR/stderr"

if grep -Fxq -- '--ipv6' "$CAPTURE_FILE"; then
  echo 'register received unsupported --ipv6 flag' >&2
  exit 1
fi
