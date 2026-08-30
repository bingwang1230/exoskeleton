#!/bin/bash
# 外骨骼计划 · 每日项目经理提醒（v2：未读会话即提醒）
# 主触发：launchd local.exoskeleton-daily-pm（每日 08:00）
# 兜底：pi-subagents schedule "daily-pm"（every 1d，锚定 08:00；晚于 08:00 打开本项目 pi 会话时补发）
# 交付：① 创建一条命名会话（user-turn 用用户口吻发问，assistant 按协议出三行建议）——未读即提醒，
#        用户进入回复后该会话转常态会话（可落账）；② Bark 推送回复内容作手机端提醒。
# 幂等：stamp=今日则跳过；DAILY_PM_FORCE=1 强制跑（标题加「测试」前缀，不写 stamp）
set -uo pipefail

REPO="/Users/claw0/exoskeleton"
STATE="$REPO/.pi/daily-pm"
LOG_DIR="$REPO/.pi/logs"
STAMP="$STATE/stamp"
LAST="$STATE/last.md"
LOCK="$STATE/lock"
TODAY="$(TZ=Asia/Shanghai date +%F)"
DOW="$(TZ=Asia/Shanghai date +%u)"   # 1=周一 … 7=周日

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

# ---- 组装会话首条 user-turn（用户口吻）与会话名 ----
if [ "$DOW" = "7" ]; then
  SNAME="周复盘 · $TODAY"
  UMSG="开始本周复盘吧：对照本周计划与实际进展（git log 和周记），汇总实际人时，起草下周计划——我确认后再落账。"
  BTITLE_BASE="外骨骼周复盘"
else
  SNAME="每日提醒 · $TODAY"
  UMSG="每天早上的定时提醒到了：今天适合做什么？"
  BTITLE_BASE="外骨骼今日建议"
fi

# ---- 跑 LLM：创建命名会话（--no-extensions 防止 settle 推送与我们的 Bark 重复）----
cd "$REPO"
OUT="$(perl -e 'alarm 900; exec @ARGV' "$PI_BIN" --no-extensions -n "$SNAME" -p "$UMSG" 2>>"$LOG_DIR/daily-pm.err")"

# ---- 会话回复 = 提醒正文（协议保证 ≤3 行；超长截断，完整内容在会话里）----
MSG="$(printf '%s\n' "$OUT" | sed '/^[[:space:]]*$/d')"
if [ -z "$MSG" ]; then
  MSG="每日会话已创建但输出为空，请直接打开会话「$SNAME」查看，日志见 .pi/logs/daily-pm.err"
fi
BODY="$(printf '%s' "$MSG" | head -c 300)"$'\n''（回复请进会话）'

# ---- 推送 Bark（python3 组 JSON，防注入）----
if [ "${DAILY_PM_FORCE:-0}" = "1" ]; then TITLE="[测试] $BTITLE_BASE · $TODAY"; else TITLE="$BTITLE_BASE · $TODAY"; fi
if python3 - "$TITLE" "$BODY" <<'PY'
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
  printf '%s\nsession: %s\nprompt: %s\n\n%s\n' "$(date '+%F %T')" "$SNAME" "$UMSG" "$MSG" >"$LAST"
  echo "[$(date '+%F %T')] OK name=$SNAME (force=${DAILY_PM_FORCE:-0})"
else
  echo "[$(date '+%F %T')] ERROR: bark 推送失败（不写 stamp，下次触发会重试；会话「$SNAME」已创建）" >>"$LOG_DIR/daily-pm.err"
  exit 1
fi
