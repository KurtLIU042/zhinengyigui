#!/usr/bin/env bash
# 更新到上游新版本：./update.sh [tag]   默认 wardrowbe-v1.2.5
source "$(dirname "$0")/_common.sh"
REF="${1:-wardrowbe-v1.2.5}"

log "拉取上游更新到 ${REF}..."
git fetch --tags --quiet
git checkout --quiet "${REF}"

log "重建镜像..."
$DC build

log "重启服务..."
$DC up -d

log "执行数据库迁移..."
$DC exec -T backend alembic upgrade head

ok "更新完成"
$DC ps
