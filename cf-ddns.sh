#!/usr/bin/env bash
#=================================================
#   System Required: CentOS/RHEL/Debian/Ubuntu/Fedora/openSUSE/Arch/macOS
#   Description: Cloudflare DDNS 自动更新脚本
#   Version: 1.0
#   Author: yuzhouxiaogegit
#   Github: https://github.com/yuzhouxiaogegit/cf-ddns
#=================================================
# 设置严格模式，确保脚本健壮性
set -o errexit
set -o nounset
set -o pipefail

# ----------------------------------------------------
# 1. 配置项 (Configuration)
# ----------------------------------------------------

# Cloudflare 的 API Token【❗推荐使用，权限更安全】
CF_TOKEN=""

# cloudflare 的顶级域名，例如：example.com
CFZONE_NAME=""

# cloudflare 的对应 ddns 域名，例如：home.example.com
CFRECORD_NAME=""

# 记录类型，A(IPv4)|AAAA(IPv6)，默认 IPv4
CFRECORD_TYPE="A"

# Cloudflare TTL (Time To Live) 记录存活时间，在 120 到 86400 秒之间
CFTTL=120

# DNS 记录的代理状态: true (橙色云朵/开启代理) | false (灰色云朵/仅DNS)
CFPROXIED=false

# 忽略本地文件，无论 IP 是否变化，强制更新 DNS
FORCE=false

# IP 获取服务站点（使用 HTTPS）
WANIPSITE_V4="https://ipv4.icanhazip.com"
WANIPSITE_V6="https://ipv6.icanhazip.com"
WANIPSITE=""

# ----------------------------------------------------
# 2. 初始化检查与参数解析 (Initialization & Argument Parsing)
# ----------------------------------------------------

# 根据记录类型确定 IP 获取站点
if [ "$CFRECORD_TYPE" = "A" ]; then
  WANIPSITE=$WANIPSITE_V4
elif [ "$CFRECORD_TYPE" = "AAAA" ]; then
  WANIPSITE=$WANIPSITE_V6
else
  echo "错误：CFRECORD_TYPE $CFRECORD_TYPE 无效，只能是 A 或 AAAA。"
  exit 2
fi

# 获取命令行参数
while getopts k:h:z:t:f:p: opts; do
  case ${opts} in
    k) CF_TOKEN=${OPTARG} ;;
    h) CFRECORD_NAME=${OPTARG} ;;
    z) CFZONE_NAME=${OPTARG} ;;
    t) CFRECORD_TYPE=${OPTARG} ;;
    f) FORCE=${OPTARG} ;;
    p) CFPROXIED=${OPTARG} ;;
    *)
      echo "用法: $0 [-k token] [-h hostname] [-z zone] [-t type] [-f true/false] [-p true/false]"
      exit 2
      ;;
  esac
done

# 检查所需配置是否齐全
if [ -z "$CF_TOKEN" ]; then
  echo "错误：缺少 API Token。请在脚本中设置 CF_TOKEN 或使用 -k 标志提供。"
  exit 2
fi
if [ -z "$CFRECORD_NAME" ] || [ -z "$CFZONE_NAME" ]; then
  echo "错误：缺少 DDNS 域名 (-h) 或顶级域名 (-z)。"
  exit 2
fi

# 如果主机名不是 FQDN (完整域名)，则自动补全
if [[ "$CFRECORD_NAME" != *"$CFZONE_NAME" ]]; then
  CFRECORD_NAME="$CFRECORD_NAME.$CFZONE_NAME"
  echo " => 域名不是 FQDN，自动补全为 $CFRECORD_NAME"
fi

# ----------------------------------------------------
# 3. 获取 IP 与检查 (Get IP & Check)
# ----------------------------------------------------

# 定义 API 授权头部
AUTH_HEADER="Authorization: Bearer $CF_TOKEN"
CONTENT_HEADER="Content-Type: application/json"

# 获取当前 WAN IP
WAN_IP=$(curl -s --max-time 10 "${WANIPSITE}" | tr -d '[:space:]')
if [ -z "$WAN_IP" ]; then
  echo "错误：无法从 ${WANIPSITE} 获取 WAN IP。"
  exit 1
fi

WAN_IP_FILE="$HOME/.cf-wan_ip_$CFRECORD_NAME.txt"
if [ -f "$WAN_IP_FILE" ]; then
  OLD_WAN_IP=$(cat "$WAN_IP_FILE")
else
  echo "首次运行或 IP 缓存文件不存在，将尝试更新。"
  OLD_WAN_IP=""
fi

# 如果 WAN IP 未更改且未设置 -f (FORCE) 标志，则退出
if [ "$WAN_IP" = "$OLD_WAN_IP" ] && [ "$FORCE" = "false" ]; then
  echo "WAN IP ($WAN_IP) 未变化，且未设置强制更新 (-f)。脚本退出。"
  exit 0
fi

echo "新的 WAN IP 为 $WAN_IP，旧 IP 为 $OLD_WAN_IP。开始处理 DNS..."

# ----------------------------------------------------
# 4. 获取 Zone ID 和 Record ID
# ----------------------------------------------------

ID_FILE="$HOME/.cf-id_$CFRECORD_NAME.txt"

# --- 4.1 尝试从缓存加载 ID ---
ID_LINE_COUNT=0
if [ -f "$ID_FILE" ]; then
  ID_LINE_COUNT=$(wc -l < "$ID_FILE" | tr -d ' ')
fi

if [ "$ID_LINE_COUNT" -eq 4 ] \
  && [ "$(sed -n '3p' "$ID_FILE")" = "$CFZONE_NAME" ] \
  && [ "$(sed -n '4p' "$ID_FILE")" = "$CFRECORD_NAME" ]; then
  CFZONE_ID=$(sed -n '1p' "$ID_FILE")
  CFRECORD_ID=$(sed -n '2p' "$ID_FILE")
  echo "ID 从本地缓存加载成功。"
else
  echo "ID 缓存失效或不存在，开始从 Cloudflare 获取 Zone ID 和 Record ID..."

  # 获取 Zone ID (区域 ID)
  ZONE_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CFZONE_NAME" \
    -H "$AUTH_HEADER" -H "$CONTENT_HEADER")
  CFZONE_ID=$(echo "$ZONE_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | sed 's/"id":"//')

  if [ -z "$CFZONE_ID" ]; then
    echo "致命错误：无法获取 Zone ID ($CFZONE_NAME)。请检查顶级域名和 API Token 权限。"
    echo "响应: $ZONE_RESPONSE"
    exit 1
  fi

  # 获取 Record ID (记录 ID)
  RECORD_RESPONSE=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME&type=$CFRECORD_TYPE" \
    -H "$AUTH_HEADER" -H "$CONTENT_HEADER")
  CFRECORD_ID=$(echo "$RECORD_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | sed 's/"id":"//')

  # 写入缓存
  printf '%s\n%s\n%s\n%s\n' "$CFZONE_ID" "$CFRECORD_ID" "$CFZONE_NAME" "$CFRECORD_NAME" > "$ID_FILE"
fi

# ----------------------------------------------------
# 5. 检查和更新/创建 DNS 记录
# ----------------------------------------------------

# --- 5.1 如果 Record ID 为空，则创建新记录 (POST) ---
if [ -z "$CFRECORD_ID" ]; then
  echo "=> Record ID 为空，记录 $CFRECORD_NAME 不存在，执行创建 (POST) 操作。"

  CREATE_RESPONSE=$(curl -s -X POST \
    "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records" \
    -H "$AUTH_HEADER" \
    -H "$CONTENT_HEADER" \
    --data "{\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$WAN_IP\",\"ttl\":$CFTTL,\"proxied\":$CFPROXIED}")

  if echo "$CREATE_RESPONSE" | grep -q '"success":true'; then
    echo "✅ 记录创建成功！正在更新缓存 ID。"

    CFRECORD_ID=$(echo "$CREATE_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | sed 's/"id":"//')
    # 兼容 macOS 和 Linux 的 sed -i
    if sed --version 2>/dev/null | grep -q GNU; then
      sed -i "2s/.*/$CFRECORD_ID/" "$ID_FILE"
    else
      sed -i '' "2s/.*/$CFRECORD_ID/" "$ID_FILE"
    fi

    echo "✅ 域名 $CFRECORD_NAME 的 IP 已创建为 $WAN_IP。"
    echo "$WAN_IP" > "$WAN_IP_FILE"
    exit 0
  else
    echo '❌ 记录创建失败！'
    echo "响应: $CREATE_RESPONSE"
    exit 1
  fi

# --- 5.2 如果 Record ID 存在，则更新记录 (PUT) ---
else
  echo "=> Record ID $CFRECORD_ID 存在，执行更新 (PUT) 操作。"

  UPDATE_RESPONSE=$(curl -s -X PUT \
    "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
    -H "$AUTH_HEADER" \
    -H "$CONTENT_HEADER" \
    --data "{\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$WAN_IP\",\"ttl\":$CFTTL,\"proxied\":$CFPROXIED}")

  if echo "$UPDATE_RESPONSE" | grep -q '"success":true'; then
    echo "✅ 更新成功！域名 $CFRECORD_NAME 的 IP 已更新为 $WAN_IP。"
    echo "$WAN_IP" > "$WAN_IP_FILE"
    exit 0
  else
    echo '❌ 更新失败！'
    echo "响应: $UPDATE_RESPONSE"
    exit 1
  fi
fi
