#!/bin/bash
# 外骨骼计划 · 每日项目经理提醒
# 主触发：launchd local.exoskeleton-daily-pm（每日 08:00）
# 兜底：pi-subagents schedule "daily-pm"（every 1d，锚定 08:00；晚于 08:00 打开本项目 pi 会话时补发）
# 幂等：stamp=今日则跳过；DAILY_PM_FORCE=1 强制跑（标题加「测试」前缀，不写 stamp）
set -uo pipefail

REPO="/Users/claw0/exoskeleton"
STATE="$REPO/.pi/daily-pm"
LOG_DIR="$REPO/.pi/logs"
STAMP="$STATE/stamp"
LAST="$STATE/last.md"
LOCK="$STATE/lock"
TODAY="$(TZ=Asia/Shanghai date +%F)"

# pi 可执行文件：优先 PATH，回退已知位置
PI_BIN="$(command -v pi || true)"
if [ -z "$PI_BIN" ]; then
  for c in "$HOME/code/pi_web/node_modules/.bin/pi" "$HOME/.pi/agent/npm/node_modules/.bin/pi"; do
    [ -x "$c" ] && PI_BIN="$c" && break
  done
fi
[ -z "$PI_BIN" ] && { echo "[$(date '+%F %T')] ERROR: pi not found" >>"$LOG_DIR/daily-pm.err"; exit 1; }

# Bark key：env 优先，~/.bark_key 兜底（launchd / 网关拉起的进程没有 shell profile）
if [ -z "${BARK_KEY:-}" ] && [ -f "$HOME/.bark_key" ]; then
  BARK_KEY="$(head -1 "$HOME/.bark_key" | tr -d '[:space:]')"
fi
[ -z "${BARK_KEY:-}" ] && { echo "[$(date '+%F %T')] ERROR: BARK_KEY missing" >>"$LOG_DIR/daily-pm.err"; exit 1; }
export BARK_KEY

mkdir -p "$STATE" "$LOG_DIR"

# ---- 幂等与并发 ----
if [ "${DAILY_PM_FORCE:-0}" != "1" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$TODAY" ]; then
  echo "[$(date '+%F %T')] 今日已推送，跳过"
  exit 0
fi
mkdir "$LOCK" 2>/dev/null || { echo "[$(date '+%F %T')] 另一实例在跑，退出"; exit 0; }
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# ---- 跑 LLM（perl alarm 给 15 分钟硬超时，防 API 卡死占住锁）----
OUT="$(perl -e 'alarm 900; exec @ARGV' "$PI_BIN" --no-extensions --no-session -p "$(cat "$REPO/scripts/daily-pm.prompt.md")" 2>>"$LOG_DIR/daily-pm.err")"

# ---- 提取正文 ----
MSG="$(printf '%s\n' "$OUT" | awk '/===DAILY_PM_BEGIN===/{f=1;next} /===DAILY_PM_END===/{f=0} f' | sed '/^[[:space:]]*$/d')"
if [ -z "$MSG" ]; then
  MSG="每日提醒跑了但输出格式异常，详见 .pi/logs/daily-pm.err"
  echo "[$(date '+%F %T')] WARN: 标记提取失败，OUT 前500字：$(printf '%s' "$OUT" | head -c 500)" >>"$LOG_DIR/daily-pm.err"
fi

# ---- 推送 Bark（python3 组 JSON，防注入）----
if [ "${DAILY_PM_FORCE:-0}" = "1" ]; then TITLE="[测试] 外骨骼计划 $TODAY"; else TITLE="外骨骼计划 $TODAY"; fi
if python3 - "$TITLE" "$MSG" <<'PY'
import json, os, sys, urllib.request
key, title, msg = os.environ["BARK_KEY"], sys.argv[1], sys.argv[2]
server = os.environ.get("BARK_SERVER", "https://api.day.app").rstrip("/")
icon = os.environ.get(
    "BARK_ICON",
    "https://82ad-static-cloud1-3gubf4ljc1ceaa10-1390345705.cos.ap-shanghai.myqcloud.com/pi/zeta-icon.png",
)
payload = json.dumps({"title": title, "body": msg, "group": "exoskeleton", "icon": icon}).encode()
req = urllib.request.Request(f"{server}/{key}", data=payload, headers={"Content-Type": "application/json"})
try:
    print("bark status:", urllib.request.urlopen(req, timeout=10).status)
except Exception as e:
    print("bark failed:", e)
    sys.exit(1)
PY
then
  if [ "${DAILY_PM_FORCE:-0}" != "1" ]; then echo "$TODAY" >"$STAMP"; fi
  printf '%s\n\n%s\n' "$(date '+%F %T')" "$MSG" >"$LAST"
  echo "[$(date '+%F %T')] OK (force=${DAILY_PM_FORCE:-0})"
else
  echo "[$(date '+%F %T')] ERROR: bark 推送失败（不写 stamp，下次触发会重试）" >>"$LOG_DIR/daily-pm.err"
  exit 1
fi
