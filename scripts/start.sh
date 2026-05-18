#!/usr/bin/env bash
# 启动 Wardrowbe 所有服务
source "$(dirname "$0")/_common.sh"
log "启动 Wardrowbe..."
$DC up -d
ok "已启动"
$DC ps
