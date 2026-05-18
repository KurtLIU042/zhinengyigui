# Wardrowbe 智能衣柜 — VPS 一键部署包

把 [Anyesh/wardrowbe](https://github.com/Anyesh/wardrowbe) 部署到你自己的云服务器，使用本地 Ollama 跑 AI，免密登录个人使用。

## 仓库内容

```
.
├── deploy.sh             一键部署（克隆+构建+迁移+启动）
├── install-ollama.sh     在主机安装 Ollama + 拉取模型
├── configs/
│   ├── docker-compose.yml   覆盖上游 compose 的个人化配置
│   └── .env.example         环境变量模板（密钥占位）
└── scripts/
    ├── start.sh    启动
    ├── stop.sh     停止
    ├── status.sh   状态 + 健康检查
    ├── logs.sh     查看日志（可指定服务名）
    ├── update.sh   升级到上游新版本
    └── backup.sh   备份 Postgres + 上传文件
```

## 部署步骤（在你的 VPS 上）

### 1. 准备 VPS

推荐配置：
- 4 GB+ 内存（不跑本地 AI 可降到 2 GB）
- 10 GB+ 可用磁盘（含 Ollama 模型约 10-15 GB）
- Ubuntu 22.04 / Debian 12 / CentOS 9

```bash
# 安装 Docker（如未安装）
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER && newgrp docker
```

### 2. 拉取本部署包

```bash
git clone https://github.com/KurtLIU042/zhinengyigui.git
cd zhinengyigui
```

### 3. 安装 Ollama 和模型（约 10-15 分钟）

```bash
./install-ollama.sh
```

脚本会：安装 Ollama → 配置监听 `0.0.0.0:11434`（供 Docker 容器访问）→ 拉取 `llava:7b` 视觉模型 + `gemma3:latest` 文本模型。

### 4. 一键部署 Wardrowbe（约 5-15 分钟）

```bash
./deploy.sh
```

脚本会：
1. 检查 Docker / Docker Compose
2. 克隆 Wardrowbe 上游仓库（tag: `wardrowbe-v1.2.5`）到 `~/wardrowbe`
3. 复制本仓库的 `configs/docker-compose.yml` 作为 override
4. 生成强密钥写入 `.env`
5. `docker compose build && up -d`
6. 等待 Postgres 健康后 `alembic upgrade head`
7. 健康检查并输出访问 URL

### 5. 访问

- 前端：`http://<你的服务器IP>:3000`
- 后端 API：`http://<你的服务器IP>:8000`
- 默认开启 `DEBUG=true` 免密登录（仅个人使用安全）

> 云服务器需在安全组开放 3000 端口（如未配置防火墙则跳过）。

## 日常运维

```bash
./scripts/status.sh         # 看容器状态 + 健康检查
./scripts/logs.sh           # 看全部日志（Ctrl+C 退出）
./scripts/logs.sh backend   # 只看某个服务
./scripts/stop.sh           # 停止（数据保留）
./scripts/start.sh          # 启动
./scripts/update.sh         # 升级到默认 tag
./scripts/update.sh wardrowbe-v1.3.0  # 升级到指定 tag
./scripts/backup.sh         # 备份到 ~/wardrowbe-backups/<时间戳>
```

## 安全提醒

本配置面向**个人/家庭使用**：
- `DEBUG=true` 开启了免密登录入口，**不要直接暴露到公网**
- Postgres / Redis 端口不对外暴露，仅容器内部访问
- 如需对外访问，请：
  1. 关闭 `DEBUG=true`（编辑 `~/wardrowbe/docker-compose.override.yml`）
  2. 配置 OIDC 或 Forward Auth（参考上游 `.env.example` 注释）
  3. 用 Caddy/Nginx 反代加上 HTTPS

## 切换到 OpenAI 兼容 API

如不想跑本地 Ollama，编辑 `~/wardrowbe/.env`：

```bash
AI_BASE_URL=https://api.deepseek.com/v1        # 或 https://dashscope.aliyuncs.com/compatible-mode/v1
AI_API_KEY=sk-xxxxxxxxxxxx
AI_VISION_MODEL=deepseek-vl                    # 或 qwen-vl-plus
AI_TEXT_MODEL=deepseek-chat                    # 或 qwen-plus
```

然后 `./scripts/start.sh` 重启即可。

## 故障排查

| 现象 | 处理 |
|---|---|
| `deploy.sh` 卡在 build | 国内网络拉镜像慢，先配 Docker 镜像加速器 |
| 后端起不来，看日志 `Connection refused` 到 Ollama | `curl http://127.0.0.1:11434/api/tags` 检查 Ollama 是否监听 0.0.0.0 |
| AI 分析超时 | `.env` 调大 `AI_TIMEOUT`（默认 300 秒已较宽松） |
| 端口冲突 | 改 `.env` 里的 `FRONTEND_PORT` / `BACKEND_PORT` |
| 想完全重装 | `cd ~/wardrowbe && docker compose down -v && rm -rf ~/wardrowbe && 重跑 deploy.sh` |
