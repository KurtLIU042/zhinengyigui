#!/usr/bin/env bash
# 更新到上游新版本：./update.sh [tag]   默认 wardrowbe-v1.2.5
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/_common.sh"
REF="${1:-wardrowbe-v1.2.5}"

log "拉取上游更新到 ${REF}..."
git fetch --tags --quiet
# checkout 会与中文补丁冲突，先重置本地修改
git checkout --quiet -- . 2>/dev/null || true
git checkout --quiet "${REF}"

# 重新应用中文界面补丁
rm -f "${INSTALL_DIR}/.i18n-zh-CN.applied"
I18N_PATCH="${REPO_ROOT}/configs/i18n-zh-CN.patch"
if [[ -f "${I18N_PATCH}" ]]; then
  if git apply --check "${I18N_PATCH}" >/dev/null 2>&1; then
    log "重新应用中文界面补丁..."
    git apply "${I18N_PATCH}"
    touch "${INSTALL_DIR}/.i18n-zh-CN.applied"
    ok "中文界面已恢复"
  else
    warn "中文补丁与新版本 ${REF} 不兼容（上游 UI 变更），前端将退回英文"
  fi
fi

log "重建镜像..."
$DC build

log "重启服务..."
$DC up -d

log "执行数据库迁移..."
$DC exec -T backend alembic upgrade head

ok "更新完成"
$DC ps
