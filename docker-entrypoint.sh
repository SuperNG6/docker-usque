#!/bin/sh
set -e

# ===================== 基本设置 =====================
: "${USQUE_CONFIG:=/app/config.json}"   # 配置文件路径
: "${USQUE_MODE:=socks}"                # 默认子命令：socks | http-proxy | nativetun | portfw | enroll | register
# USQUE_MTU: 可选，MASQUE MTU（如 1200），仅在 socks/http-proxy/nativetun/portfw 下生效
mkdir -p "$(dirname "$USQUE_CONFIG")"

log() { echo "[entrypoint] $*" >&2; }

# ===================== 解析子命令 =====================
if [ "$#" -gt 0 ]; then
  case "$1" in
    -*) set -- "$USQUE_MODE" "$@";;   # 只给了标志位：补默认模式
    usque) shift; [ "$#" -eq 0 ] && set -- "$USQUE_MODE" ;;   # 支持写成 "usque socks ..."，仅传 usque 时补默认模式
  esac
else
  set -- "$USQUE_MODE"
fi

cmd="$1"; shift || true

# ===================== 注册流程 =====================
if [ "$cmd" = "register" ]; then
  log "进入注册流程（配置保存到 $USQUE_CONFIG，默认同意 ToS）"
  # 构建固定参数（顺序：--jwt → -n → -a），用户额外参数追加在最后
  reg_args=""
  [ -n "${USQUE_JWT:-}" ]         && reg_args="$reg_args --jwt $USQUE_JWT"
  [ -n "${USQUE_DEVICE_NAME:-}" ] && reg_args="$reg_args -n $USQUE_DEVICE_NAME"
  # shellcheck disable=SC2086
  exec /bin/usque -c "$USQUE_CONFIG" register -a $reg_args "$@"
fi

# 首次无配置：自动注册（有 JWT 走 Zero Trust，否则个人 WARP）
# enroll 模式无需自动注册（配置不存在时 enroll 本身会报错，保留原始错误信息更有用）
if [ ! -f "$USQUE_CONFIG" ] && [ "$cmd" != "enroll" ]; then
  log "未检测到配置文件：$USQUE_CONFIG，自动执行注册（默认同意 ToS）"
  # 构建固定参数（顺序：--jwt → -n → -a），不传入用户原始参数
  reg_args=""
  [ -n "${USQUE_JWT:-}" ]         && reg_args="$reg_args --jwt $USQUE_JWT"
  [ -n "${USQUE_DEVICE_NAME:-}" ] && reg_args="$reg_args -n $USQUE_DEVICE_NAME"
  log "执行：usque register -a$reg_args"
  # shellcheck disable=SC2086
  /bin/usque -c "$USQUE_CONFIG" register -a $reg_args || {
    log "注册失败，请检查网络或参数（USQUE_JWT/USQUE_DEVICE_NAME）。容器退出。"
    exit 2
  }
  log "注册完成，继续启动服务。"
  set --
fi

# ===================== SNI 自动判定（显式传 USQUE_SNI 则不覆盖） =====================
if [ -z "${USQUE_SNI:-}" ] && [ -r "$USQUE_CONFIG" ]; then
  # 取 license 与 ipv4 字段（尽量兼容 busybox）
  LICENSE_IN_CFG="$(sed -n 's/.*"license"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$USQUE_CONFIG" | head -n1)"
  IPV4_IN_CFG="$(sed -n 's/.*"ipv4"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$USQUE_CONFIG" | head -n1)"

  if [ -n "$LICENSE_IN_CFG" ]; then
    # A. license 非空：个人 WARP / WARP+ 走 consumer
    USQUE_SNI="consumer-masque.cloudflareclient.com"
    log "检测到 license 已配置（个人/WARP+），默认 SNI=$USQUE_SNI"
  elif [ -n "$IPV4_IN_CFG" ]; then
    OCT1="${IPV4_IN_CFG%%.*}"
    OCT2="$(printf '%s' "$IPV4_IN_CFG" | awk -F. '{print $2+0}')"

    # B. Team / Zero Trust：100.96.0.0/12（第二段 96..111）
    if [ "$OCT1" = "100" ] && [ "$OCT2" -ge 96 ] && [ "$OCT2" -le 111 ]; then
      USQUE_SNI="zt-masque.cloudflareclient.com"
      log "检测到 Team/ZT (ipv4=$IPV4_IN_CFG in 100.96/12)，默认 SNI=$USQUE_SNI"

    # C. 个人常见段：172.x.x.x → consumer
    elif [ "$OCT1" = "172" ]; then
      USQUE_SNI="consumer-masque.cloudflareclient.com"
      log "检测到个人 WARP (ipv4=$IPV4_IN_CFG)，默认 SNI=$USQUE_SNI"

    else
      log "未能从 ipv4=$IPV4_IN_CFG 判断出类型，不设置默认 SNI（可用 USQUE_SNI 覆盖）"
    fi
  fi
fi

# ===================== 按模式补参数 =====================
# 仅对会建立隧道的模式添加 SNI/MTU/HTTP2/INSECURE，避免 register/enroll 报 unknown flag
case "$cmd" in
  socks|http-proxy|nativetun|portfw)
    [ -n "${USQUE_SNI:-}" ]               && set -- -s "$USQUE_SNI" "$@"
    [ -n "${USQUE_MTU:-}" ]               && set -- -m "$USQUE_MTU" "$@"
    [ "${USQUE_HTTP2:-false}" = "true" ]    && set -- --http2 "$@"
    [ "${USQUE_HTTP2:-false}" = "true" ] && \
      [ "${USQUE_INSECURE:-false}" = "true" ] && set -- --insecure "$@"
    [ "$cmd" = "nativetun" ] && [ "${USQUE_PERSIST:-false}" = "true" ] && set -- --persist "$@"
    ;;
esac

# socks/http-proxy/portfw 的快捷参数（USQUE_DNS 可空格分隔多个）
if [ "$cmd" = "socks" ] || [ "$cmd" = "http-proxy" ] || [ "$cmd" = "portfw" ]; then
  [ -n "${USQUE_BIND:-}" ] && set -- -b "$USQUE_BIND" "$@"
  [ -n "${USQUE_PORT:-}" ] && set -- -p "$USQUE_PORT" "$@"
  [ -n "${USQUE_USER:-}" ] && set -- -u "$USQUE_USER" "$@"
  [ -n "${USQUE_PASS:-}" ] && set -- -w "$USQUE_PASS" "$@"
  if [ -n "${USQUE_DNS:-}" ]; then
    for dns in $USQUE_DNS; do
      [ -n "$dns" ] && set -- "$@" -d "$dns"  # 追加而非前插，保持用户指定的 DNS 顺序
    done
  fi
fi
# 说明：nativetun 默认不改 DNS，保持系统/路由自行处理

# nativetun 友好提示
if [ "$cmd" = "nativetun" ] && [ ! -e /dev/net/tun ]; then
  log "警告：未发现 /dev/net/tun。请以 --cap-add NET_ADMIN --device /dev/net/tun 运行容器。"
fi

# ===================== 执行 usque =====================
exec /bin/usque -c "$USQUE_CONFIG" "$cmd" "$@"
