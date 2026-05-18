#!/usr/bin/env bash
# 查看日志：./logs.sh [service]  默认全部
source "$(dirname "$0")/_common.sh"
SVC="${1:-}"
if [[ -z "$SVC" ]]; then
  $DC logs -f --tail=100
else
  $DC logs -f --tail=200 "$SVC"
fi
