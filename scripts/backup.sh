#!/usr/bin/env bash
# 备份 Postgres + 上传文件到 ./backups/<timestamp>
source "$(dirname "$0")/_common.sh"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/wardrowbe-backups}"
TS=$(date +%Y%m%d-%H%M%S)
DEST="${BACKUP_ROOT}/${TS}"
mkdir -p "${DEST}"

log "备份目录: ${DEST}"

log "导出 Postgres..."
$DC exec -T postgres pg_dump -U wardrobe wardrobe | gzip > "${DEST}/postgres.sql.gz"

log "打包上传文件..."
$DC run --rm -v "${DEST}:/backup" backend tar czf /backup/uploads.tar.gz -C /data wardrobe 2>/dev/null \
  || warn "未找到上传数据卷，跳过（首次使用是正常的）"

log "复制 .env..."
cp .env "${DEST}/.env"

SIZE=$(du -sh "${DEST}" | cut -f1)
ok "备份完成: ${DEST}（${SIZE}）"

# 保留最近 7 份
log "清理 7 份之前的旧备份..."
ls -1dt "${BACKUP_ROOT}"/*/ 2>/dev/null | tail -n +8 | xargs -r rm -rf
ok "完成"
