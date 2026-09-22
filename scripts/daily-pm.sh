#!/bin/bash
# 外骨骼计划 · 每日项目经理提醒（v5.2：会话创建后布防 pi-web follow up 黄灯；v5.1：last.md 追加制+周日清空，决策二十四；v5：先总结后建议，决策十八；v4：周日双会话）
# 主触发：launchd local.exoskeleton-daily-pm（每日 08:00）—— 唯一触发源（2026-09-07 第十九决策移除 pi-subagents 兜底 schedule）
# 交付：每天一条「每日提醒 · 日期」命名会话（先总结昨天、再建议今天）；周日额外一条「周复盘 · 日期」（先总结本周、再起草下周）。
#        未读会话即提醒；用户进入回复后该会话转常态会话（可落账）；Bark 推送作手机端入口。
#        v5.2（2026-09-22）：每次建会话后向 pi-web 网关 PUT followup（「待读」黄灯，对齐 pi-web 2026-09-21
#        follow up 设计）——未读即提醒从 Bark 单通道升级为会话黄灯常亮；用户进会话验收后手动清空。
#        网关缺席/失败只记日志不阻断提醒本体。
# 失败语义：每日提醒本体失败 → 不写 stamp、exit 1（当天可手动 bash scripts/daily-pm.sh 补发；launchd 对睡眠错过的时点唤醒时补跑）；
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
cd "$REPO" # 会话目录按 cwd 锚定（~/.pi/agent/sessions/<cwd 转义>--），固定在仓库根，与 launchd WorkingDirectory 一致

# ---- pi-web follow up 布防（v5.2）----
PIWEB_URL="${PIWEB_URL:-http://localhost:8787}"
# 会话目录编码同 pi session-manager：--<cwd 去首斜杠、/→->--
_enc="${REPO#/}"; _enc="${_enc//\//-}"
SESSIONS_DIR="$HOME/.pi/agent/sessions/--${_enc}--"

arm_followup() { # $1=会话名 $2=标记文件（pi 跑前 touch，取比它新的最新 jsonl）
  local f sid text
  f="$(find "$SESSIONS_DIR" -name '*.jsonl' -newer "$2" 2>/dev/null | sort | tail -1)"
  if [ -z "$f" ]; then log_err "WARN: followup 布防未找到新会话文件（会话已创建，仅黄灯缺失）"; return 0; fi
  if ! grep -qF "\"name\":\"$1\"" "$f" 2>/dev/null; then log_err "WARN: followup 布防会话名不匹配，跳过（$f）"; return 0; fi
  sid="${f##*_}"; sid="${sid%.jsonl}"
  text="【待读】$1 已送达——进会话查看今日建议/复盘，处理完清空此灯"
  curl -sf -X PUT "$PIWEB_URL/api/sessions/$sid/followup" \
    -H 'Content-Type: application/json' \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1]}))' "$text")" \
    --max-time 10 >/dev/null \
    || log_err "WARN: followup 布防失败 sid=$sid（pi-web 网关未起？会话本体已交付，不阻断）"
  return 0
}

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

# ---- 单条会话：跑 LLM → 建 session → 推 Bark → 追记 last.md（v5.1：追加制，文件尾=上次建议）----
DAILY_OK=0
run_one() { # $1=会话名 $2=user开场白 $3=Bark标题前缀
  local sname="$1" umsg="$2" btitle="$3" out msg body title mark
  mark="$(mktemp)"; touch "$mark"
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
  arm_followup "$sname" "$mark"; rm -f "$mark"
  echo "[$(date '+%F %T')] OK name=$sname (force=${DAILY_PM_FORCE:-0})"
}

# ---- 每日提醒（每天，含周日）----
RC=0
run_one "每日提醒 · $TODAY" "每天早上的定时提醒到了：先用一行总结昨天做了什么（昨天 git 提交 + 对照上次建议的执行情况，无提交就如实说无），再给今天适合做什么的建议。" "外骨骼今日建议" && DAILY_OK=1 || RC=1

# ---- 周复盘（仅周日，与每日并存）----
if [ "$DOW" = "7" ]; then
  run_one "周复盘 · $TODAY" "开始本周复盘吧：先总结这一周做了什么（本周 git 提交 + 周记，对照周初计划逐项勾稽），再汇总实际人时、起草下周计划——我确认后再落账。" "外骨骼周复盘" || RC=1
fi

# ---- 周清 last.md（v5.1，决策二十四）：追加制下每周日跑完清空迎新周（周日起算）；测试运行不清 ----
if [ "$DOW" = "7" ] && [ "${DAILY_PM_FORCE:-0}" != "1" ]; then
  : >"$LAST"
  echo "[$(date '+%F %T')] 周清 last.md 完成"
fi

# ---- 结束语义 ----
if [ "$RC" = "0" ]; then
  [ "${DAILY_PM_FORCE:-0}" != "1" ] && echo "$TODAY" >"$STAMP"
  exit 0
fi
# 每日本体失败（DAILY_OK=0）：不写 stamp（当天可手动补发），推失败通知
if [ "$DAILY_OK" != "1" ]; then
  push_bark "外骨骼今日建议 · $TODAY" "今日提醒生成失败（详见 .pi/logs/daily-pm.err）。可手动补发：bash scripts/daily-pm.sh" || true
  exit 1
fi
# 每日提醒成功、周复盘失败：写 stamp 防重复，失败详情在日志
[ "${DAILY_PM_FORCE:-0}" != "1" ] && echo "$TODAY" >"$STAMP"
exit 1
