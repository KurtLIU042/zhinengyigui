#!/usr/bin/env bash
# Wardrowbe 一键部署脚本
# 用法：在你的 VPS / ECS 上执行 ./deploy.sh
set -euo pipefail

# ---------- 颜色 ----------
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
log()   { echo "${BLUE}[INFO]${NC} $*"; }
warn()  { echo "${YELLOW}[WARN]${NC} $*"; }
ok()    { echo "${GREEN}[ OK ]${NC} $*"; }
fail()  { echo "${RED}[FAIL]${NC} $*" >&2; exit 1; }

# ---------- 可配置变量 ----------
WARDROBE_REPO="${WARDROBE_REPO:-https://github.com/Anyesh/wardrowbe.git}"
WARDROBE_REF="${WARDROBE_REF:-wardrowbe-v1.2.5}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/wardrowbe}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- 前置检查 ----------
need() { command -v "$1" >/dev/null 2>&1 || fail "未找到命令: $1，请先安装"; }

log "=== Wardrowbe 部署脚本 ==="
log "目标目录: ${INSTALL_DIR}"
log "上游版本: ${WARDROBE_REF}"
echo

need git
need curl
need openssl

if ! command -v docker >/dev/null 2>&1; then
  fail "未安装 Docker。请先运行：curl -fsSL https://get.docker.com | sh"
fi

if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  fail "未安装 Docker Compose v2 或 v1"
fi
ok "Docker / Compose 已就绪"

# ---------- 拉取源码 ----------
if [[ -d "${INSTALL_DIR}/.git" ]]; then
  log "检测到已存在的 Wardrowbe 仓库，更新中..."
  git -C "${INSTALL_DIR}" fetch --tags --quiet
  git -C "${INSTALL_DIR}" checkout --quiet "${WARDROBE_REF}"
else
  log "克隆 Wardrowbe 源码..."
  git clone --branch "${WARDROBE_REF}" --depth 1 "${WARDROBE_REPO}" "${INSTALL_DIR}"
fi
ok "源码已就绪：${INSTALL_DIR}"

# ---------- 应用本地定制 ----------
log "应用本地化配置（docker-compose.yml / .env）..."
cp "${SCRIPT_DIR}/configs/docker-compose.yml" "${INSTALL_DIR}/docker-compose.override.yml"

# ---------- 应用中文界面补丁 ----------
I18N_PATCH="${SCRIPT_DIR}/configs/i18n-zh-CN.patch"
I18N_MARKER="${INSTALL_DIR}/.i18n-zh-CN.applied"
if [[ -f "${I18N_PATCH}" ]]; then
  if [[ -f "${I18N_MARKER}" ]]; then
    ok "中文界面补丁已应用过，跳过"
  elif git -C "${INSTALL_DIR}" apply --check "${I18N_PATCH}" >/dev/null 2>&1; then
    log "应用中文界面补丁..."
    git -C "${INSTALL_DIR}" apply "${I18N_PATCH}"
    touch "${I18N_MARKER}"
    ok "前端已切换为中文界面"
  else
    warn "中文补丁与当前源码不兼容（可能上游已变更），跳过 — 前端将保持英文"
  fi
fi

if [[ ! -f "${INSTALL_DIR}/.env" ]]; then
  cp "${SCRIPT_DIR}/configs/.env.example" "${INSTALL_DIR}/.env"
  # 仅随机化 NEXTAUTH_SECRET 与 POSTGRES_PASSWORD。
  # SECRET_KEY 必须保持 change-me-in-production，否则免密登录失效（见 .env.example 注释）。
  NEXTAUTH_SECRET=$(openssl rand -hex 32)
  POSTGRES_PASSWORD=$(openssl rand -hex 16)
  sed -i "s|__NEXTAUTH_SECRET__|${NEXTAUTH_SECRET}|g" "${INSTALL_DIR}/.env"
  sed -i "s|__POSTGRES_PASSWORD__|${POSTGRES_PASSWORD}|g" "${INSTALL_DIR}/.env"
  ok "已生成强密钥并写入 .env（SECRET_KEY 保留默认以启用免密登录）"
else
  warn ".env 已存在，跳过密钥生成（如需重置请删除后重跑）"
fi

# ---------- Ollama 检查 ----------
if curl -fsS --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  ok "Ollama 已在本机运行"
  HAS_VISION=$(curl -fsS http://127.0.0.1:11434/api/tags | grep -c '"name":"llava' || true)
  HAS_TEXT=$(curl -fsS http://127.0.0.1:11434/api/tags | grep -c '"name":"gemma3' || true)
  [[ "$HAS_VISION" -eq 0 ]] && warn "未检测到 llava 视觉模型，建议执行: ollama pull llava:7b"
  [[ "$HAS_TEXT"   -eq 0 ]] && warn "未检测到 gemma3 文本模型，建议执行: ollama pull gemma3:latest"
else
  warn "未检测到 Ollama，请先执行 ${SCRIPT_DIR}/install-ollama.sh"
  read -rp "是否继续部署？(y/N) " ans
  [[ "${ans:-N}" =~ ^[Yy]$ ]] || exit 1
fi

# ---------- 构建并启动 ----------
cd "${INSTALL_DIR}"
log "构建镜像（首次约 5-15 分钟）..."
$DC build

log "启动服务..."
$DC up -d

log "等待 Postgres 健康..."
for i in {1..30}; do
  if $DC exec -T postgres pg_isready -U wardrobe >/dev/null 2>&1; then
    ok "Postgres 就绪"
    break
  fi
  sleep 2
  [[ $i -eq 30 ]] && fail "Postgres 启动超时，查看日志: $DC logs postgres"
done

log "执行数据库迁移..."
$DC exec -T backend alembic upgrade head

# ---------- 健康检查 ----------
log "健康检查后端 API..."
for i in {1..20}; do
  if curl -fsS http://127.0.0.1:8000/api/v1/health >/dev/null 2>&1; then
    ok "后端 API 健康"
    break
  fi
  sleep 3
  [[ $i -eq 20 ]] && warn "后端健康检查超时，查看: $DC logs backend"
done

# ---------- 完成 ----------
SERVER_IP=$(curl -fsS --max-time 3 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
echo
ok "==================================================="
ok "  Wardrowbe 部署完成 !"
ok "==================================================="
echo "  前端访问: http://${SERVER_IP}:3000"
echo "  后端 API: http://${SERVER_IP}:8000"
echo "  默认登录: 开启了 DEBUG 模式，无需密码"
echo
echo "  常用命令（在 ${SCRIPT_DIR} 下执行）:"
echo "    ./scripts/status.sh    查看状态"
echo "    ./scripts/logs.sh      查看日志"
echo "    ./scripts/stop.sh      停止服务"
echo "    ./scripts/start.sh     启动服务"
echo "    ./scripts/update.sh    更新到新版本"
echo "    ./scripts/backup.sh    备份数据"
echo
warn "安全提醒：当前 DEBUG=true 用于免密登录。"
warn "如需对外暴露，请关闭 DEBUG 并配置 OIDC + HTTPS。"
