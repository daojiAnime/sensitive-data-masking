# Sensitive Data Masking

基于 PaddleNLP 的中文敏感信息识别与脱敏工具。

## 功能特性

- 🔍 **NLP 识别**: 人名、地名、组织机构、时间
- 📝 **正则匹配**: 手机号、身份证、邮箱、银行卡
- 🎭 **多种脱敏策略**: 部分脱敏、完全脱敏、占位符、哈希
- 🌐 **Web 界面**: Gradio 构建的友好交互界面

## 快速开始

### 本地运行

```bash
# 安装依赖
uv sync --group paddle

# 运行应用
python app.py
```

访问 http://localhost:7860

### Docker 部署

```bash
# 1. 配置环境变量
cp .env.example .env
# 按需编辑 .env

# 2. 构建并启动
./scripts/start.sh

# 3. 停止服务
./scripts/stop.sh
```

## 环境变量配置

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `GRADIO_PORT` | `7860` | Web 服务端口 |
| `NER_MODE` | `fast` | NER 模式: `fast` (快速) / `accurate` (精确) |
| `MODEL_DIR` | `/app/models` | 模型存储目录 |
| `USE_MKLDNN` | `1` | 启用 MKLDNN 加速 (0=禁用) |
| `OMP_NUM_THREADS` | `4` | OpenMP 线程数 |
| `MEMORY_LIMIT` | `4G` | 容器内存限制 |

### 配置示例

```bash
# 使用精确模式 + 8核心
NER_MODE=accurate OMP_NUM_THREADS=8 ./scripts/start.sh

# 指定端口
GRADIO_PORT=8080 ./scripts/start.sh
```

## 模型预下载

⚠️ **重要**: `fast` 和 `accurate` 模式使用**不同的模型**，需要分别下载。

| 模式 | 模型 | 大小 | 适用场景 |
|------|------|------|----------|
| `fast` | BiGRU-CRF | ~50MB | 实时处理、低延迟 |
| `accurate` | ERNIE | ~400MB | 高精度、批量处理 |

首次启动前预下载模型可加速启动。

### 方式一：Docker 下载（推荐）

⚠️ **Mac 用户必须使用此方式**，accurate 模式在 Mac 本地会崩溃。

```bash
# 下载所有模式（推荐）
./scripts/download_models.sh all

# 仅下载 fast 模式
./scripts/download_models.sh fast

# 仅下载 accurate 模式
./scripts/download_models.sh accurate
```

### 方式二：本地下载（仅 Linux）

```bash
# 仅下载 fast 模式模型
python scripts/download_models.py --model-dir ./models

# 仅下载 accurate 模式模型
python scripts/download_models.py --model-dir ./models --mode accurate

# 下载所有模式
python scripts/download_models.py --model-dir ./models --all
```

> 💡 按需下载：如果只使用 `fast` 模式，无需下载 `accurate` 模型。

## 项目结构

```
sensitive-data-masking/
├── app.py              # Gradio Web 应用
├── demo.py             # 核心脱敏逻辑
├── pyproject.toml      # 项目配置
├── Dockerfile          # 多阶段构建
├── docker-compose.yml  # 容器编排
├── .env.example        # 环境变量模板
├── models/             # 模型缓存目录
└── scripts/
    ├── start.sh            # 启动脚本
    ├── stop.sh             # 停止脚本
    ├── download_models.sh  # Docker 模型下载（推荐）
    └── download_models.py  # 本地模型下载
```

## 脱敏策略

| 策略 | 示例 | 说明 |
|------|------|------|
| 部分脱敏 | `张*三` | 保留首尾字符 |
| 完全脱敏 | `***` | 全部替换为 * |
| 占位符 | `[人名]` | 替换为类型标签 |
| 哈希脱敏 | `[a1b2c3]` | MD5 哈希前8位 |

## 性能优化

### MKLDNN 加速

Docker 镜像默认启用 MKLDNN (Intel oneDNN) 加速:

```yaml
environment:
  - FLAGS_use_mkldnn=1
  - OMP_NUM_THREADS=4
```

### 模式选择

- **fast**: 轻量模型，适合实时处理
- **accurate**: 精确模型，适合批量处理

## License

MIT
