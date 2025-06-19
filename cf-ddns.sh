#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# --- 配置项 (推荐通过环境变量设置，或在此处填写) ---
# Cloudflare 的 Global API Key
# 推荐通过环境变量 CLOUDFLARE_API_KEY 设置
CFKEY=${CLOUDFLARE_API_KEY:-}

# Cloudflare 账号邮箱
# 推荐通过环境变量 CLOUDFLARE_EMAIL 设置
CFUSER=${CLOUDFLARE_EMAIL:-}

# Cloudflare 的顶级域名 (例如: example.com)
# 推荐通过环境变量 CLOUDFLARE_ZONE_NAME 设置
CFZONE_NAME=${CLOUDFLARE_ZONE_NAME:-}

# Cloudflare 的 DDNS 域名 (例如: ddns.example.com)
# 推荐通过环境变量 CLOUDFLARE_RECORD_NAME 设置
CFRECORD_NAME=${CLOUDFLARE_RECORD_NAME:-}

# DNS 记录类型: A (IPv4) | AAAA (IPv6)，默认 IPv4
CFRECORD_TYPE=${CLOUDFLARE_RECORD_TYPE:-A}

# Cloudflare TTL (Time To Live)，120 到 86400 秒之间
CFTTL=${CLOUDFLARE_TTL:-120}

# 强制更新 IP，即使 WAN IP 未改变也会更新
FORCE=${CLOUDFLARE_FORCE_UPDATE:-false}

# --- 内部变量 (通常无需修改) ---
# 获取 WAN IP 的站点
WANIPSITE="http://ipv4.icanhazip.com"

# 记录类型检查
if [ "$CFRECORD_TYPE" = "A" ]; then
  : # 保持 IPv4 站点
elif [ "$CFRECORD_TYPE" = "AAAA" ]; then
  WANIPSITE="http://ipv6.icanhazip.com"
else
  echo "错误: CFRECORD_TYPE 指定无效，只能是 A (IPv4) 或 AAAA (IPv6)。"
  exit 2
fi

# --- 参数解析 ---
# 允许通过命令行参数覆盖默认配置或环境变量
while getopts k:u:h:z:t:f: opts; do
  case ${opts} in
    k) CFKEY=${OPTARG} ;;
    u) CFUSER=${OPTARG} ;;
    h) CFRECORD_NAME=${OPTARG} ;;
    z) CFZONE_NAME=${OPTARG} ;;
    t) CFRECORD_TYPE=${OPTARG} ;;
    f) FORCE=${OPTARG} ;;
    *) echo "用法: $0 [-k api_key] [-u email] [-h hostname] [-z zonename] [-t type] [-f force_update]" && exit 1 ;;
  esac
done

# --- 强制配置项检查 ---
if [ -z "$CFKEY" ]; then
  echo "错误: 缺少 Cloudflare API 密钥。请设置 CLOUDFLARE_API_KEY 环境变量或使用 -k 参数。"
  echo "API 密钥获取地址: https://www.cloudflare.com/a/account/my-account"
  exit 2
fi
if [ -z "$CFUSER" ]; then
  echo "错误: 缺少 Cloudflare 账号邮箱。请设置 CLOUDFLARE_EMAIL 环境变量或使用 -u 参数。"
  exit 2
fi
if [ -z "$CFZONE_NAME" ]; then
  echo "错误: 缺少 Cloudflare 顶级域名 (Zone Name)。请设置 CLOUDFLARE_ZONE_NAME 环境变量或使用 -z 参数。"
  exit 2
fi
if [ -z "$CFRECORD_NAME" ]; then
  echo "错误: 缺少 DDNS 域名 (Hostname)。请设置 CLOUDFLARE_RECORD_NAME 环境变量或使用 -h 参数。"
  exit 2
fi

# --- 主机名标准化 ---
# 如果 CFRECORD_NAME 不是 FQDN，则将其拼接为 FQDN
if [[ "$CFRECORD_NAME" != *".$CFZONE_NAME"* ]]; then
  echo "注意: 主机名 '$CFRECORD_NAME' 不是 FQDN，自动修正为 '$CFRECORD_NAME.$CFZONE_NAME'。"
  CFRECORD_NAME="$CFRECORD_NAME.$CFZONE_NAME"
fi

# --- 获取当前和旧的 WAN IP ---
echo "正在获取当前 WAN IP..."
WAN_IP=$(curl -s --max-time 10 "${WANIPSITE}") # 增加超时设置
if [ -z "$WAN_IP" ]; then
  echo "错误: 无法获取 WAN IP。请检查网络连接或 WANIPSITE (${WANIPSITE}) 是否可用。"
  exit 1
fi
echo "当前 WAN IP: $WAN_IP"

# 处理文件名中的特殊字符，确保其合法性
WAN_IP_FILE="$HOME/.cf-wan_ip_${CFRECORD_NAME//[^a-zA-Z0-9._-]/_}.txt"
OLD_WAN_IP=""
if [ -f "$WAN_IP_FILE" ]; then
  OLD_WAN_IP=$(cat "$WAN_IP_FILE")
  echo "上次记录的 WAN IP: $OLD_WAN_IP"
else
  echo "未找到上次记录的 WAN IP 文件 '$WAN_IP_FILE'，将进行更新。"
fi

# 如果 WAN IP 未更改且未设置 -f 标志，则在此处退出
if [ "$WAN_IP" = "$OLD_WAN_IP" ] && [ "$FORCE" = false ]; then
  echo "WAN IP 未改变 ($WAN_IP)。若要强制更新，请使用 -f true 标志。"
  exit 0
fi

# --- 获取 zone_identifier 和 record_identifier ---
# 处理文件名中的特殊字符，确保其合法性
ID_FILE="$HOME/.cf-id_${CFRECORD_NAME//[^a-zA-Z0-9._-]/_}.txt"
CFZONE_ID=""
CFRECORD_ID=""
UPDATE_IDS=true

if [ -f "$ID_FILE" ] && [ "$(wc -l < "$ID_FILE")" -ge 4 ]; then
  CACHED_ZONE_ID=$(sed -n '1p' "$ID_FILE")
  CACHED_RECORD_ID=$(sed -n '2p' "$ID_FILE")
  CACHED_ZONE_NAME=$(sed -n '3p' "$ID_FILE")
  CACHED_RECORD_NAME=$(sed -n '4p' "$ID_FILE")

  if [ "$CACHED_ZONE_NAME" = "$CFZONE_NAME" ] && [ "$CACHED_RECORD_NAME" = "$CFRECORD_NAME" ]; then
    CFZONE_ID="$CACHED_ZONE_ID"
    CFRECORD_ID="$CACHED_RECORD_ID"
    UPDATE_IDS=false
    echo "从缓存文件加载了 Zone ID 和 Record ID。"
  else
    echo "缓存文件内容与当前配置不匹配，将重新获取 Zone ID 和 Record ID。"
  fi
fi

if [ "$UPDATE_IDS" = true ]; then
  echo "正在更新 Zone ID 和 Record ID..."

  ZONE_RESPONSE=$(curl -s --max-time 10 -X GET "https://api.cloudflare.com/client/v4/zones?name=$CFZONE_NAME" \
    -H "X-Auth-Email: $CFUSER" \
    -H "X-Auth-Key: $CFKEY" \
    -H "Content-Type: application/json")

  if [ -z "$ZONE_RESPONSE" ]; then
    echo "错误: 获取 Zone ID 时 API 响应为空。请检查网络或 Cloudflare API 状态。"
    exit 1
  fi

  # 使用 grep -Po 从响应中提取 Zone ID
  CFZONE_ID=$(echo "$ZONE_RESPONSE" | grep -Po '(?<="id":")[^"]*' | head -1)

  if [ -z "$CFZONE_ID" ]; then
    echo "错误: 无法获取 Zone ID。请检查 CFZONE_NAME ($CFZONE_NAME) 是否正确或 API 密钥是否有权限。"
    echo "API 响应: $ZONE_RESPONSE"
    exit 1
  fi

  RECORD_RESPONSE=$(curl -s --max-time 10 -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME" \
    -H "X-Auth-Email: $CFUSER" \
    -H "X-Auth-Key: $CFKEY" \
    -H "Content-Type: application/json")

  if [ -z "$RECORD_RESPONSE" ]; then
    echo "错误: 获取 Record ID 时 API 响应为空。请检查网络或 Cloudflare API 状态。"
    exit 1
  fi

  # 使用 grep -Po 从响应中提取 Record ID
  CFRECORD_ID=$(echo "$RECORD_RESPONSE" | grep -Po '(?<="id":")[^"]*' | head -1)

  if [ -z "$CFRECORD_ID" ]; then
    echo "错误: 无法获取 Record ID。请检查 CFRECORD_NAME ($CFRECORD_NAME) 是否正确或 API 密钥是否有权限。"
    echo "API 响应: $RECORD_RESPONSE"
    exit 1
  fi

  # 保存新的 ID 到缓存文件
  echo "$CFZONE_ID" > "$ID_FILE"
  echo "$CFRECORD_ID" >> "$ID_FILE"
  echo "$CFZONE_NAME" >> "$ID_FILE"
  echo "$CFRECORD_NAME" >> "$ID_FILE"
fi

# --- 更新 Cloudflare DNS 记录 ---
echo "正在将 DNS 记录 '$CFRECORD_NAME' 更新为 IP '$WAN_IP'..."

UPDATE_RESPONSE=$(curl -s --max-time 10 -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
  -H "X-Auth-Email: $CFUSER" \
  -H "X-Auth-Key: $CFKEY" \
  -H "Content-Type: application/json" \
  --data "{\"id\":\"$CFRECORD_ID\",\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$WAN_IP\", \"ttl\":$CFTTL}")

# 检查 Cloudflare API 响应中的 "success":true
if echo "$UPDATE_RESPONSE" | grep -q '"success":true'; then
  echo "DNS 更新成功！记录 '$CFRECORD_NAME' 已更新为 '$WAN_IP'。"
  echo "$WAN_IP" > "$WAN_IP_FILE" # 更新本地 WAN IP 文件
  exit 0
else
  echo "错误: DNS 更新失败！"
  echo "Cloudflare API 响应: $UPDATE_RESPONSE"
  exit 1
fi
