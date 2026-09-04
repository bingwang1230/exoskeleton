#!/bin/bash
# 外骨骼计划 · 每日项目经理提醒（v5：先总结后建议，决策十八；v4：周日双会话）
# 主触发：launchd local.exoskeleton-daily-pm（每日 08:00）
# 兜底：pi-subagents schedule "daily-pm"（every 1d，锚定 08:00；晚于 08:00 打开本项目 pi 会话时补发）
# 交付：每天一条「每日提醒 · 日期」命名会话（先总结昨天、再建议今天）；周日额外一条「周复盘 · 日期」（先总结本周、再起草下周）。
#        未读会话即提醒；用户进入回复后该会话转常态会话（可落账）；Bark 推送作手机端入口。
# 失败语义：每日提醒本体失败 → 不写 stamp、exit 1（当天打开项目会话时兜底层可补发）；
#           仅周复盘失败 → 写 stamp（防每日提醒重复推），exit 1，详见日志。
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

# ---- API 认证兜底：launchd/无头环境没有 shell rc 的 export，从 ~/.zshrc 等提取 pi 认证相关变量 ----
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

# ---- 单条会话：跑 LLM → 建 session → 推 Bark → 记 last.md ----
run_one() { # $1=会话名 $2=user开场白 $3=Bark标题前缀
  local sname="$1" umsg="$2" btitle="$3" out msg body title
  out="$(perl -e 'alarm 900; exec @ARGV' "$PI_BIN" --no-extensions -n "$sname" -p "$umsg" 2>>"$LOG_DIR/daily-pm.err")"
  if [ -z "$out" ]; then
    log_err "ERROR: [$sname] pi 无输出"
    return 1
  fi
  msg="$(printf '%s\n' "$out" | sed '/^[[:space:]]*$/d')"
  body="$(printf '%s' "$msg" | head -c 300)"$'\n''（回复请进会话）'
  if [ "${DAILY_PM_FORCE:-0}" = "1" ]; then title="[测试] $btitle · $TODAY"; else title="$btitle · $TODAY"; fi
  push_bark "$title" "$body" || { log_err "ERROR: [$sname] bark 推送失败（会话已创建）"; return 1; }
  printf '%s\nsession: %s\nprompt: %s\n\n%s\n' "$(date '+%F %T')" "$sname" "$umsg" "$msg" >>"$LAST"
  echo "[$(date '+%F %T')] OK name=$sname (force=${DAILY_PM_FORCE:-0})"
}

: >"$LAST"

# ---- 每日提醒（每天，含周日）----
RC=0
run_one "每日提醒 · $TODAY" "每天早上的定时提醒到了：先用一行总结昨天做了什么（昨天 git 提交 + 对照上次建议的执行情况，无提交就如实说无），再给今天适合做什么的建议。" "外骨骼今日建议" || RC=1

# ---- 周复盘（仅周日，与每日并存）----
if [ "$DOW" = "7" ]; then
  run_one "周复盘 · $TODAY" "开始本周复盘吧：先总结这一周做了什么（本周 git 提交 + 周记，对照周初计划逐项勾稽），再汇总实际人时、起草下周计划——我确认后再落账。" "外骨骼周复盘" || RC=1
fi

# ---- 结束语义 ----
if [ "$RC" = "0" ]; then
  [ "${DAILY_PM_FORCE:-0}" != "1" ] && echo "$TODAY" >"$STAMP"
  exit 0
fi
if ! grep -q "^session: 每日提醒" "$LAST" 2>/dev/null; then
  # 每日提醒本体失败：不写 stamp（当天可由兜底层补发），推失败通知
  push_bark "外骨骼今日建议 · $TODAY" "今日提醒生成失败（详见 .pi/logs/daily-pm.err）。今天内打开本项目任意 pi 会话会自动补发。" || true
  exit 1
fi
# 每日提醒成功、周复盘失败：写 stamp 防重复，失败详情在日志
[ "${DAILY_PM_FORCE:-0}" != "1" ] && echo "$TODAY" >"$STAMP"
exit 1
