#!/usr/bin/env bash
# 停止所有服务（保留数据卷）
source "$(dirname "$0")/_common.sh"
log "停止 Wardrowbe..."
$DC down
ok "已停止（数据卷保留）"
