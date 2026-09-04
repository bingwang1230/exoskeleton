#!/bin/bash
# exoskeleton volume → 外接盘(ext2) 自动同步（2026-09-02 决策十四：周日→每日；文件名沿用 sync-weekly.sh）
# launchd local.exoskeleton-volume-sync 每日 03:40（pebble volume_sync 03:15 之后错峰）。
# 两阶段协议说明：本脚本是用户明确授权的「常设确认」——自动执行时不再逐次等人工看
# 报告，但仍严格走 volume_sync 自身两阶段（plan 只读 → apply 前复验源未变），
# 不绕过、不直调 rsync。异常以非零码退出并留日志、Bark 推送失败告警。设计详见同目录 README.md。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET="/Volumes/ext2"
LOG_DIR="$REPO/volume/logs"
LOG_FILE="$LOG_DIR/volume-sync.log"
LOCK_DIR="/tmp/exoskeleton-volume-sync.lock"

log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }

mkdir -p "$LOG_DIR"

# ---- 失败 Bark 推送（2026-09-02 补：失败必达，成功不打扰；key 沿用 ~/.bark_key，同 daily-pm）----
BARK_KEY="${BARK_KEY:-$(head -1 "$HOME/.bark_key" 2>/dev/null | tr -d '[:space:]')}"
notify_fail() { # $1=退出码
  [ -n "$BARK_KEY" ] || return 0
  python3 - "$1" >>"$LOG_FILE" 2>&1 <<'PY' || true
import json, os, sys, urllib.request
code = sys.argv[1]
key = os.environ["BARK_KEY"]
server = os.environ.get("BARK_SERVER", "https://api.day.app").rstrip("/")
payload = json.dumps({
    "title": "exo volume 同步失败",
    "body": f"exit {code}——盘未挂载或 plan/apply 出错，日志 volume/logs/volume-sync.log",
    "group": "exoskeleton",
}).encode()
req = urllib.request.Request(f"{server}/{key}", data=payload, headers={"Content-Type": "application/json"})
try:
    urllib.request.urlopen(req, timeout=10)
except Exception as e:
    print("bark failed:", e)
PY
}

# 防并发（手动触发与定时撞车），mkdir 原子锁；异常残留超过 6 小时视为 stale 清掉
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  if [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +360 2>/dev/null)" ]; then
    log "WARN: 清理疑似残留的旧锁 ($LOCK_DIR)"
    rmdir "$LOCK_DIR" && mkdir "$LOCK_DIR" || { log "ERROR: 无法获取锁"; exit 7; }
  else
    log "WARN: 已有同步在运行，本次跳过"; exit 0
  fi
fi
trap 'rc=$?; rmdir "$LOCK_DIR" 2>/dev/null; [ "$rc" -ne 0 ] && notify_fail "$rc" || true' EXIT

log "==== exoskeleton volume 每日同步开始 ===="

if [ ! -d "$TARGET" ]; then
  log "ERROR: $TARGET 未挂载，今日跳过（请插盘后手动执行 plan/apply）"
  exit 4
fi

log "--- plan ---"
"$SCRIPT_DIR/volume_sync" plan "$TARGET" >>"$LOG_FILE" 2>&1 || {
  log "ERROR: plan 失败 (exit $?)"; exit 5;
}

log "--- apply ---"
"$SCRIPT_DIR/volume_sync" apply "$TARGET" >>"$LOG_FILE" 2>&1 || {
  log "ERROR: apply 失败 (exit $?)"; exit 6;
}

log "==== 完成 ===="
