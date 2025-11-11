
# docker-usque

基于 [usque](https://github.com/Diniboy1123/usque) 的 Docker 镜像，用来在容器中运行 Cloudflare WARP / ZeroTrust MASQUE 代理。

- Docker Hub：`superng6/usque`
- 支持：`socks`（SOCKS5）、`http-proxy`（HTTP CONNECT）、`nativetun`、`portfw`、`register`、`enroll`

---
```
GitHub：https://github.com/SuperNG6/docker-usque

Docker Hub：https://hub.docker.com/r/superng6/usque
```

## 镜像信息

```bash
# 拉取镜像
docker pull superng6/usque:latest
或
docker pull ghcr.io/superng6/usque:latest
````

---

## docker-compose 示例（参考格式）

复制保存为 `docker-compose.yml`：

```yaml
services:
  # SOCKS5 代理（默认 0.0.0.0:1080）
  usque-socks:
    image: superng6/usque:latest
    container_name: usque-socks
    restart: unless-stopped
    environment:
      - USQUE_MODE=socks           # 运行模式：socks / http-proxy / nativetun / portfw / enroll / register
      - USQUE_CONFIG=/app/config.json
      - USQUE_BIND=0.0.0.0
      - USQUE_PORT=1080
      - USQUE_USER=
      - USQUE_PASS=
      - USQUE_SNI=
      - USQUE_JWT=
      - USQUE_DEVICE_NAME=
      - USQUE_DNS=1.1.1.1 1.0.0.1  # 可选：多个 DNS 用空格分隔（仅 socks/http-proxy/portfw 有效）
    volumes:
      - ./usque_data:/app
    ports:
      - 1080:1080

  # HTTP CONNECT 代理（默认 0.0.0.0:8000）
  usque-http:
    image: superng6/usque:latest
    container_name: usque-http
    restart: unless-stopped
    environment:
      - USQUE_MODE=http-proxy
      - USQUE_CONFIG=/app/config.json
      - USQUE_BIND=0.0.0.0
      - USQUE_PORT=8000
      - USQUE_USER=
      - USQUE_PASS=
      - USQUE_SNI=
      - USQUE_DNS=1.1.1.1 1.0.0.1
    volumes:
      - ./usque_data:/app
    ports:
      - 8000:8000

  # TUN 模式（高级用法，需要 /dev/net/tun 和 NET_ADMIN）
  usque-tun:
    image: superng6/usque:latest
    container_name: usque-tun
    restart: "no"
    environment:
      - USQUE_MODE=nativetun
      - USQUE_CONFIG=/app/config.json
    volumes:
      - ./usque_data:/app
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
```

> 说明：默认模式为 `socks`，无需额外设置；`/app/config.json` 不存在时会自动 `register -a`（默认同意 ToS）并保存配置。

---

## 首次启动（推荐流程）
复制最小化配置到compose中，不启动
```
  usque:
    image: superng6/usque
    restart: unless-stopped
    environment:
      - USQUE_PORT=1080            # 对外监听端口（socks 默认 1080）
      - USQUE_DEVICE_NAME=yourvps   # 设备名（可选）
    volumes:
      - ./usque_data:/app # 配置文件一定要挂载到本地
```
### 1）先用个人 WARP 起服务（自动注册）
```bash
docker compose run --rm usque-socks register -a
```

首次启动会自动完成注册并写入 `./usque_data/config.json`，随后直接以 SOCKS5 模式运行（监听 `0.0.0.0:1080`）。

### 2）需要 Zero Trust 时再“升级”

准备好 Zero Trust 的 **team token** 后执行（尽量在拿到 token 后立即使用）：
token申请地址，你得有自己的team，如果看不懂可以网上搜教程，这块我不多赘述，复杂，只推荐本身就有team账户的人使用，上一步申请的个人账号就足够用了。

https://web--public--warp-team-api--coia-mfs4.code.run

```bash
docker compose run --rm -e USQUE_JWT='<team-token>' usque-socks register -a
```
成功后会更新 `config.json`，随后容器继续按原模式使用 Zero Trust 配置。


---

## 启动与使用

### 启动 SOCKS5 代理

```bash
docker compose up -d usque-socks
```

默认：

* 监听：`0.0.0.0:1080`
* 若设置了 `USQUE_USER` / `USQUE_PASS`，连接地址类似：`socks5://user:pass@127.0.0.1:1080`

测试：

```bash
# 无认证
curl -x socks5://127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace

# 有认证
curl -x socks5://user:pass@127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace
```

### 启动 HTTP 代理

```bash
docker compose up -d usque-http
```

默认：

* 监听：`0.0.0.0:8000`

测试：

```bash
curl -x http://127.0.0.1:8000 https://cloudflare.com/cdn-cgi/trace
# 有认证
curl -x http://user:pass@127.0.0.1:8000 https://cloudflare.com/cdn-cgi/trace
```

### 启动 TUN 模式（可选）

```bash
docker compose run --rm --service-ports usque-tun
```

* 需要宿主机支持 `/dev/net/tun` 并且允许 `NET_ADMIN`
* 路由/防火墙如何配置参考上游 usque 文档

---

## 刷新 IP / 更新配置（enroll）

ZeroTrust 下如果 IPv4/IPv6 变更，可用 `enroll` 更新现有 `config.json`：

```bash
docker compose run --rm -it usque-socks enroll
```

然后重启代理：

```bash
docker compose up -d usque-socks usque-http
```

---

## 环境变量一览

| 变量名                 | 说明                                                                           | 默认值                |
| ------------------- | ---------------------------------------------------------------------------- | ------------------ |
| `USQUE_MODE`        | 运行模式：`socks` / `http-proxy` / `nativetun` / `portfw` / `enroll` / `register` | `socks`            |
| `USQUE_CONFIG`      | 配置文件路径                                                                       | `/app/config.json` |
| `USQUE_JWT`         | ZeroTrust team token（首次无配置时自动走 `register -a --jwt`）                          | 空                  |
| `USQUE_DEVICE_NAME` | 注册时设备名称（`register -n`）                                                       | 空                  |
| `USQUE_SNI`         | 自定义 SNI（仅隧道模式生效：`socks/http-proxy/nativetun/portfw`）                         | 空                  |
| `USQUE_BIND`        | 代理绑定地址（socks/http-proxy）                                                     | `0.0.0.0`          |
| `USQUE_PORT`        | 代理端口（socks 默认 1080，http-proxy 默认 8000）                                       | 视模式而定              |
| `USQUE_USER`        | 代理用户名（仅支持一个 user:pass）                                                       | 空                  |
| `USQUE_PASS`        | 代理密码                                                                         | 空                  |
| `USQUE_DNS`         | 代理使用的 DNS，**空格分隔多个**（仅 `socks/http-proxy/portfw` 有效，例如 `1.1.1.1 1.0.0.1`）    | 空                  |

---

## 注意事项

* 本地到代理的 SOCKS/HTTP 链路**不加密**，不要在公网裸奔暴露端口，建议：

  * 只在内网使用，或
  * 启用 `USQUE_USER` / `USQUE_PASS`，并配合防火墙限制来源
* 删除 `usque_data` 文件夹会丢失注册信息，需要重新 `register`
* usque 自身的用法、参数细节请参考上游仓库文档

