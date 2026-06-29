#!/usr/bin/env bash
# -------------------------------------------------------
#  每天 9:00 报告
#  * 从 ~/.pm2/logs/AI-iot-Server-out.log 检测设备状态
#  * 从 ~/.pm2/logs/Auth.log(或你放日志的位置) 检测登录
#  * 通过 Feishu Bot 推送给微信
# -------------------------------------------------------

set -o pipefail   # any command failure stops the script
LOG_DIR="$HOME/.pm2/logs"

# ---------- 1️⃣ 配置信息 ----------
IOT_LOG="$LOG_DIR/AI-iot-Server-out.log"  # 修复：等号两边无空格
AUTH_LOG="$LOG_DIR/Auth.log"               # 若你把日志放在别处，请改这里
HOOK_URL="https://open.feishu.cn/open-apis/bot/v2/hook/686a9833-bb88-463a-8f6a-c0ac1dcfd4f2"

# 检查依赖
if ! command -v jq &> /dev/null; then
    echo "错误：未找到 jq 命令，请先安装"
    exit 1
fi

# 检查日志文件
if [ ! -f "$IOT_LOG" ]; then
    echo "错误：设备日志文件不存在: $IOT_LOG"
    exit 1
fi

if [ ! -f "$AUTH_LOG" ]; then
    echo "警告：认证日志文件不存在: $AUTH_LOG"
    AUTH_LOG="/dev/null"
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ---------- 2️⃣ 设备状态 ----------
# ① ONLINE（最近一次出现的 ON 状态设备）
ONLINE=$(awk '
    /收到MQTT状态消息/ && /内容: *ON/ {
        split($0, a, "/");
        dev=a[length(a)];
        on[dev] = 1
    }
    END {
        first=1
        for (d in on) {
            if (!first) printf ",";
            printf "%s", d
            first=0
        }
        print ""
    }' "$IOT_LOG")

# ② OFFLINE（所有"设备离线"出现的设备）
OFFLINE=$(awk -F'设备离线: ' '/设备离线:/ {print $2}' "$IOT_LOG" | sort -u | paste -sd, -)

# ③ ON/OFF 列表（按主题顺序抽取）
ON_LIST=$(awk '
    /收到MQTT状态消息/ && /内容: *ON/ {
        split($0, a, "/"); dev=a[length(a)]; print dev
    }' "$IOT_LOG" | paste -sd, -)

OFF_LIST=$(awk '
    /收到MQTT状态消息/ && /内容: *OFF/ {
        split($0, a, "/"); dev=a[length(a)]; print dev
    }' "$IOT_LOG" | paste -sd, -)

# ---------- 3️⃣ 用户认证 ----------
# 成功
OK_USERS=$(awk '
    /认证成功/ { users[$3]++ }
    END {
        first=1
        for (u in users) {
            if (!first) printf ",";
            printf "%s", u
            first=0
        }
        print ""
    }' "$AUTH_LOG")

# 失败
ERR_USERS=$(awk '
    /认证失败/ { users[$3]++ }
    END {
        first=1
        for (u in users) {
            if (!first) printf ",";
            printf "%s", u
            first=0
        }
        print ""
    }' "$AUTH_LOG")

# 统计数量
OK_COUNT=$(echo "$OK_USERS" | grep -c ',')
[ -n "$OK_USERS" ] && ((OK_COUNT++))
ERR_COUNT=$(echo "$ERR_USERS" | grep -c ',')
[ -n "$ERR_USERS" ] && ((ERR_COUNT++))

# 空值处理
ONLINE=${ONLINE:-无}
OFFLINE=${OFFLINE:-无}
ON_LIST=${ON_LIST:-无}
OFF_LIST=${OFF_LIST:-无}
OK_USERS=${OK_USERS:-无}
ERR_USERS=${ERR_USERS:-无}

# ---------- 4️⃣ 生成报告 ----------
REPORT=$(cat <<EOF
报告时间：$TIMESTAMP

1. 在线设备：$ONLINE
   离线设备：$OFFLINE

2. 设备状态为 ON 的有：$ON_LIST
   设备状态为 OFF 的有：$OFF_LIST

3. 用户认证：
   成功认证 ($OK_COUNT)：$OK_USERS
   失败认证 ($ERR_COUNT)：$ERR_USERS
EOF
)

# ---------- 5️⃣ 推送到微信（Feishu） ----------
REPORT_JSON=$(jq -n --arg r "$REPORT" '{"msg_type":"text","content":{"content":$r}}')
curl -s -X POST "$HOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$REPORT_JSON"

# ---------- 6️⃣ 结束 ----------
exit 0