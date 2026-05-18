# 运维脚本公用函数
# shellcheck shell=bash
set -euo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
log()  { echo "${BLUE}[INFO]${NC} $*"; }
warn() { echo "${YELLOW}[WARN]${NC} $*"; }
ok()   { echo "${GREEN}[ OK ]${NC} $*"; }
fail() { echo "${RED}[FAIL]${NC} $*" >&2; exit 1; }

INSTALL_DIR="${INSTALL_DIR:-$HOME/wardrowbe}"
[[ -d "${INSTALL_DIR}" ]] || fail "未找到 Wardrowbe 安装目录: ${INSTALL_DIR}（请先运行 deploy.sh）"

if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  fail "未安装 Docker Compose"
fi

cd "${INSTALL_DIR}"
