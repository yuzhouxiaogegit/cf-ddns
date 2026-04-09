# Cloudflare DDNS 自动更新脚本

自动检测本机公网 IP 并同步更新到 Cloudflare DNS 记录，支持 IPv4 (A) 和 IPv6 (AAAA)，兼容 Linux / macOS。

---

## 快速开始

### 1. 下载脚本

```bash
curl -Lo cf-ddns.sh https://raw.githubusercontent.com/yuzhouxiaogegit/cf-ddns/master/cf-ddns.sh && chmod +x cf-ddns.sh
```

### 2. 编辑配置

```bash
vi cf-ddns.sh
```

修改脚本顶部的配置项：

```bash
# Cloudflare API Token（推荐，权限更安全）
CF_TOKEN="your_api_token"

# 顶级域名，例如：example.com
CFZONE_NAME="example.com"

# DDNS 域名，例如：home.example.com
CFRECORD_NAME="home.example.com"

# 记录类型：A (IPv4) 或 AAAA (IPv6)
CFRECORD_TYPE="A"

# TTL，120 ~ 86400 秒
CFTTL=120

# 代理状态：true (开启橙云) | false (仅 DNS)
CFPROXIED=false
```

> API Token 生成地址：https://dash.cloudflare.com/profile/api-tokens
> 建议只授予对应 Zone 的 `DNS:Edit` 权限。

### 3. 手动测试

```bash
bash cf-ddns.sh
```

也可以通过命令行参数传入配置，无需修改脚本：

```bash
bash cf-ddns.sh -k <token> -z <zone> -h <hostname> -t A -p false
```

| 参数 | 说明                                    |
| ---- | --------------------------------------- |
| `-k` | API Token                               |
| `-z` | 顶级域名                                |
| `-h` | DDNS 域名                               |
| `-t` | 记录类型 `A` / `AAAA`                   |
| `-p` | 是否开启代理 `true` / `false`           |
| `-f` | 强制更新，忽略 IP 缓存 `true` / `false` |

---

## 设置定时任务

```bash
crontab -e
```

每 2 分钟执行一次（静默）：

```bash
*/2 * * * * /root/cf-ddns.sh >/dev/null 2>&1
```

输出到日志文件：

```bash
*/2 * * * * /root/cf-ddns.sh >> /var/log/cf-ddns.log 2>&1
```

重载 / 重启 cron：

```bash
systemctl reload crond.service
systemctl restart crond.service
```

---

## 缓存文件

脚本会在 `$HOME` 下生成两个缓存文件，避免每次都请求 Cloudflare API：

- `~/.cf-wan_ip_<域名>.txt` — 上次记录的公网 IP
- `~/.cf-id_<域名>.txt` — Zone ID 和 Record ID 缓存

---

## License

MIT
