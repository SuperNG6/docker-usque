# ---- build ----
FROM golang:1.24-alpine AS builder
RUN apk add --no-cache git
WORKDIR /src

ARG TARGETARCH
ARG TARGETVARIANT
ARG USQUE_REPO="https://github.com/Diniboy1123/usque.git"
ARG USQUE_REF="main"   # 由 CI 传入：上游最新 tag（或指定 ref）

# 直接 clone 指定 ref（tag/分支/提交都可），保留浅克隆
RUN git clone --depth=1 --branch "${USQUE_REF}" "${USQUE_REPO}" . \
 || (echo "指定的 USQUE_REF=${USQUE_REF} 不是分支/轻量 tag，尝试完整拉取后 checkout" && \
     git clone "${USQUE_REPO}" . && \
     git fetch --tags --force && \
     git checkout "${USQUE_REF}")

# 缓存 Go 模块下载（go.mod 未变时跳过重新下载）
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# 根据 TARGETVARIANT 自动判断并设置 GOAMD64，复用 build cache 加速增量编译
# amd64+v3 -> GOAMD64=v3, amd64+v2 -> GOAMD64=v2, 其他 -> 使用默认值
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    if [ "${TARGETARCH}" = "amd64" ] && { [ "${TARGETVARIANT}" = "v3" ] || [ "${TARGETVARIANT}" = "v2" ]; }; then \
        export GOAMD64="${TARGETVARIANT}"; \
    fi; \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/usque .

# ---- runtime ----
FROM alpine
ARG BUILD_VARIANT=lite
RUN if [ "$BUILD_VARIANT" = "tun" ]; then \
      apk add --no-cache ca-certificates tzdata iproute2; \
    else \
      apk add --no-cache ca-certificates; \
    fi
WORKDIR /app

COPY --from=builder /out/usque /bin/usque
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

VOLUME ["/app"]
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
