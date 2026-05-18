#!/usr/bin/env bash
# 查看服务状态与健康检查
source "$(dirname "$0")/_common.sh"

echo "=== 容器状态 ==="
$DC ps

echo
echo "=== 后端健康 ==="
if curl -fsS http://127.0.0.1:8000/api/v1/health 2>/dev/null; then
  echo
  ok "后端 OK"
else
  fail "后端无响应"
fi

echo
echo "=== Ollama ==="
if curl -fsS http://127.0.0.1:11434/api/tags 2>/dev/null | head -c 200; then
  echo
  ok "Ollama OK"
else
  warn "Ollama 无响应（如使用云端 API 可忽略）"
fi

echo
echo "=== 磁盘占用 ==="
docker system df
