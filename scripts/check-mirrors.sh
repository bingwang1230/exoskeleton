#!/bin/sh
# 双远端镜像一致性自检:gitee 与 github 的 main 都必须等于本地 main。
# 用法:bash scripts/check-mirrors.sh(需网络;任一远端不可达或不一致 → exit 1)
set -e
LOCAL=$(git rev-parse main)
BAD=0
for URL in git@gitee.com:bingwang1230/exoskeleton.git git@github.com:bingwang1230/exoskeleton.git; do
  NAME=${URL#*git@}; NAME=${NAME%%:*}
  REMOTE=$(git ls-remote "$URL" refs/heads/main 2>/dev/null | cut -f1)
  if [ -z "$REMOTE" ]; then
    echo "✗ $NAME:main 不可达或分支不存在——检查网络/密钥/仓库"; BAD=1
  elif [ "$REMOTE" != "$LOCAL" ]; then
    echo "✗ $NAME:main ($REMOTE) ≠ 本地 ($LOCAL)——有分叉或未推送"; BAD=1
  else
    echo "✓ $NAME:main 一致 ${LOCAL}0+${LOCAL#+}" | sed 's/0\+$//'
  fi
done
[ "$BAD" = 0 ] && echo "镜像一致 ✓" || echo "镜像不一致,见上"
exit $BAD
