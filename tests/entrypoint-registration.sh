#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_USQUE="$TMP_DIR/usque"
ENTRYPOINT_UNDER_TEST="$TMP_DIR/docker-entrypoint.sh"
CALLS_FILE="$TMP_DIR/calls"

cat > "$FAKE_USQUE" <<'SCRIPT'
#!/bin/sh
{
  printf 'CALL\n'
  printf '%s\n' "$@"
} >> "$CALLS_FILE"

case " $* " in
  *" register "*)
    i=1
    config_file=""
    while [ "$i" -le "$#" ]; do
      eval "arg=\${$i}"
      if [ "$arg" = "-c" ]; then
        i=$((i + 1))
        eval "config_file=\${$i}"
        break
      fi
      i=$((i + 1))
    done
    [ -n "$config_file" ] && printf '{"license":"personal","ipv4":"172.16.0.2"}\n' > "$config_file"
    ;;
esac
SCRIPT
chmod +x "$FAKE_USQUE"

sed "s#/bin/usque#$FAKE_USQUE#g" "$ROOT_DIR/docker-entrypoint.sh" > "$ENTRYPOINT_UNDER_TEST"
chmod +x "$ENTRYPOINT_UNDER_TEST"

assert_preserves_args_after_auto_register() {
  config_file="$TMP_DIR/auto-register.json"
  expected="$TMP_DIR/expected-auto-register"
  : > "$CALLS_FILE"

  CALLS_FILE="$CALLS_FILE" \
  USQUE_BANNER="false" \
  USQUE_CONFIG="$config_file" \
    "$ENTRYPOINT_UNDER_TEST" socks -p 18080 --on-connect "/hooks/up script"

  cat > "$expected" <<EOF_EXPECTED
CALL
-c
$config_file
register
-a
CALL
-c
$config_file
socks
-s
consumer-masque.cloudflareclient.com
-p
18080
--on-connect
/hooks/up script
EOF_EXPECTED

  diff -u "$expected" "$CALLS_FILE"
}

assert_info_commands_do_not_register() {
  for cmd in version help --help; do
    config_file="$TMP_DIR/no-register-$cmd.json"
    expected="$TMP_DIR/expected-no-register-$cmd"
    : > "$CALLS_FILE"

    CALLS_FILE="$CALLS_FILE" \
    USQUE_BANNER="false" \
    USQUE_CONFIG="$config_file" \
      "$ENTRYPOINT_UNDER_TEST" "$cmd"

    cat > "$expected" <<EOF_EXPECTED
CALL
-c
$config_file
$cmd
EOF_EXPECTED

    diff -u "$expected" "$CALLS_FILE"
  done
}

assert_help_flag_for_mode_does_not_register() {
  config_file="$TMP_DIR/mode-help.json"
  expected="$TMP_DIR/expected-mode-help"
  : > "$CALLS_FILE"

  CALLS_FILE="$CALLS_FILE" \
  USQUE_BANNER="false" \
  USQUE_CONFIG="$config_file" \
  USQUE_PORT="18080" \
    "$ENTRYPOINT_UNDER_TEST" socks --help

  cat > "$expected" <<EOF_EXPECTED
CALL
-c
$config_file
socks
--help
EOF_EXPECTED

  diff -u "$expected" "$CALLS_FILE"
}

assert_register_masks_jwt_and_keeps_device_name() {
  config_file="$TMP_DIR/register.json"
  stderr_file="$TMP_DIR/register.stderr"
  expected="$TMP_DIR/expected-register"
  : > "$CALLS_FILE"

  CALLS_FILE="$CALLS_FILE" \
  USQUE_BANNER="false" \
  USQUE_CONFIG="$config_file" \
  USQUE_JWT="secret-token" \
  USQUE_DEVICE_NAME="my vps" \
    "$ENTRYPOINT_UNDER_TEST" register --extra 2> "$stderr_file"

  cat > "$expected" <<EOF_EXPECTED
CALL
-c
$config_file
register
--jwt
secret-token
-n
my vps
-a
--extra
EOF_EXPECTED

  diff -u "$expected" "$CALLS_FILE"
  if grep -Fq "secret-token" "$stderr_file"; then
    exit 1
  fi
}

assert_preserves_args_after_auto_register
assert_info_commands_do_not_register
assert_help_flag_for_mode_does_not_register
assert_register_masks_jwt_and_keeps_device_name
