#!/bin/bash
# 外骨骼计划 · 每日项目经理提醒（v3）
# 主触发：launchd local.exoskeleton-daily-pm（每日 08:00）
# 兜底：pi-subagents schedule "daily-pm"（every 1d，锚定 08:00；晚于 08:00 打开本项目 pi 会话时补发）
# 交付：① 创建一条命名会话（user-turn 用用户口吻发问，assistant 按协议出三行建议）——未读即提醒，
#        用户进入回复后该会话转常态会话（可落账）；② Bark 推送回复内容作手机端提醒。
# 失败语义：pi 无输出 → 推失败通知但不写 stamp、exit 1（当天打开项目会话时兜底层可补发）
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

log_err() { echo "[$(date '+%F %T')] $*" >>"$LOG_DIR/daily-pm.err"; }

# ---- node 解析（launchd / 无头环境 PATH 里没有 node，pi wrapper 需要 exec node）----
NODE_BIN="$(command -v node || true)"
if [ -z "$NODE_BIN" ]; then
  for c in /usr/local/bin/node /opt/homebrew/bin/node "$HOME"/.nvm/versions/node/*/bin/node; do
    [ -x "$c" ] && NODE_BIN="$c" && break
  done
fi
[ -n "$NODE_BIN" ] && export PATH="$(dirname "$NODE_BIN"):$PATH"

# ---- pi 可执行文件：优先 PATH，回退已知位置 ----
PI_BIN="$(command -v pi || true)"
if [ -z "$PI_BIN" ]; then
  for c in "$HOME/code/pi_web/node_modules/.bin/pi" "$HOME/.pi/agent/npm/node_modules/.bin/pi"; do
    [ -x "$c" ] && PI_BIN="$c" && break
  done
fi
[ -z "$PI_BIN" ] && { log_err "ERROR: pi not found"; exit 1; }

# ---- Bark key：env 优先，~/.bark_key 兜底 ----
if [ -z "${BARK_KEY:-}" ] && [ -f "$HOME/.bark_key" ]; then
  BARK_KEY="$(head -1 "$HOME/.bark_key" | tr -d '[:space:]')"
fi
[ -z "${BARK_KEY:-}" ] && { log_err "ERROR: BARK_KEY missing"; exit 1; }
export BARK_KEY

# ---- API 认证兑底：launchd/无头环境没有 shell rc 的 export，从 ~/.zshrc 等提取 pi 认证相关变量 ----
if [ -z "${GLM_CODING_PLAN_APIKEY:-}" ]; then
  eval "$(grep -hE '^export [A-Z0-9_]*(KEY|TOKEN|APIKEY)=' ~/.zshrc ~/.zprofile ~/.zshenv 2>/dev/null | sort -u)" || true
fi

mkdir -p "$STATE" "$LOG_DIR"

push_bark() { # $1=title $2=body
  python3 - "$1" "$2" <<'PY'
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
}

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

# ---- 失败守卫：pi 无输出 = 生成失败。推失败通知，不写 stamp（当天可由兜底层补发），exit 1 ----
if [ -z "$OUT" ]; then
  log_err "ERROR: pi 无输出（环境/认证问题？），本次不写 stamp"
  push_bark "$BTITLE_BASE · $TODAY" "今日提醒生成失败（pi 无输出，详见 .pi/logs/daily-pm.err）。今天内打开本项目任意 pi 会话会自动补发。" || true
  exit 1
fi

MSG="$(printf '%s\n' "$OUT" | sed '/^[[:space:]]*$/d')"
BODY="$(printf '%s' "$MSG" | head -c 300)"$'\n''（回复请进会话）'

# ---- 推送 ----
if [ "${DAILY_PM_FORCE:-0}" = "1" ]; then TITLE="[测试] $BTITLE_BASE · $TODAY"; else TITLE="$BTITLE_BASE · $TODAY"; fi
if push_bark "$TITLE" "$BODY"; then
  if [ "${DAILY_PM_FORCE:-0}" != "1" ]; then echo "$TODAY" >"$STAMP"; fi
  printf '%s\nsession: %s\nprompt: %s\n\n%s\n' "$(date '+%F %T')" "$SNAME" "$UMSG" "$MSG" >"$LAST"
  echo "[$(date '+%F %T')] OK name=$SNAME (force=${DAILY_PM_FORCE:-0})"
else
  log_err "ERROR: bark 推送失败（不写 stamp；会话「$SNAME」已创建）"
  exit 1
fi
