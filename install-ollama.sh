#!/usr/bin/env bash
# 在 VPS 主机上安装 Ollama 并拉取 Wardrowbe 所需模型
set -euo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
log()  { echo "${BLUE}[INFO]${NC} $*"; }
warn() { echo "${YELLOW}[WARN]${NC} $*"; }
ok()   { echo "${GREEN}[ OK ]${NC} $*"; }
fail() { echo "${RED}[FAIL]${NC} $*" >&2; exit 1; }

VISION_MODEL="${VISION_MODEL:-llava:7b}"
TEXT_MODEL="${TEXT_MODEL:-gemma3:latest}"

log "=== Ollama 安装与模型拉取 ==="

# 内存检查
MEM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
log "检测到内存: ${MEM_GB} GB"
if [[ "${MEM_GB}" -lt 8 ]]; then
  warn "内存不足 8GB，本地运行 llava:7b + gemma3 可能很慢，建议改用 OpenAI 兼容 API"
  read -rp "是否仍继续？(y/N) " ans
  [[ "${ans:-N}" =~ ^[Yy]$ ]] || exit 1
fi

# 安装 Ollama
if command -v ollama >/dev/null 2>&1; then
  ok "Ollama 已安装：$(ollama --version)"
else
  log "下载并安装 Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
  ok "Ollama 安装完成"
fi

# 监听地址：默认只听 127.0.0.1，docker 通过 host-gateway 访问需要监听 0.0.0.0
log "配置 Ollama 监听 0.0.0.0:11434（供 Docker 容器访问）..."
if [[ -d /etc/systemd/system ]] && systemctl list-unit-files | grep -q ollama.service; then
  sudo mkdir -p /etc/systemd/system/ollama.service.d
  sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF
  sudo systemctl daemon-reload
  sudo systemctl restart ollama
  ok "Ollama 已重启，监听 0.0.0.0:11434"
else
  warn "未检测到 systemd 服务，请手动以 OLLAMA_HOST=0.0.0.0:11434 启动 ollama serve"
fi

# UFW 放行：Docker 网桥 (172.16.0.0/12) 访问宿主机 11434
# 仅当 ufw 已安装且处于 active 状态时添加；公网仍被默认策略 DROP 拦截。
if command -v ufw >/dev/null 2>&1 && sudo ufw status 2>/dev/null | grep -q '^Status: active'; then
  if sudo ufw status | grep -q '172.16.0.0/12.*11434'; then
    ok "UFW 已放行 Docker → Ollama"
  else
    log "UFW 放行 Docker 网桥访问 11434..."
    sudo ufw allow from 172.16.0.0/12 to any port 11434 proto tcp comment 'Docker -> Ollama' >/dev/null
    ok "UFW 规则已添加"
  fi
fi

# 等待 Ollama 就绪
log "等待 Ollama API 就绪..."
for i in {1..20}; do
  if curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    ok "Ollama API 已就绪"
    break
  fi
  sleep 2
  [[ $i -eq 20 ]] && fail "Ollama 启动失败，检查: systemctl status ollama"
done

# 拉取模型
log "拉取视觉模型: ${VISION_MODEL}（约 4.7GB）..."
ollama pull "${VISION_MODEL}"
log "拉取文本模型: ${TEXT_MODEL}（约 4-8GB）..."
ollama pull "${TEXT_MODEL}"

ok "模型已就绪："
ollama list

echo
ok "完成。现在可以运行 ./deploy.sh 部署 Wardrowbe"
