#!/bin/bash
set -euo pipefail

# ============================================
# 使用 Docker 下载 PaddleNLP 模型
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

MODE="${1:-all}"
MODEL_DIR="${PROJECT_DIR}/models"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  PaddleNLP 模型下载 (Docker)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

mkdir -p "$MODEL_DIR"

if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}错误: Docker 未运行${NC}"
    exit 1
fi

echo -e "${GREEN}▸${NC} 模式: ${MODE}"
echo -e "${GREEN}▸${NC} 保存目录: ${MODEL_DIR}"
echo

download_model() {
    local ner_mode=$1
    echo -e "${YELLOW}▸ 下载 ${ner_mode} 模式模型...${NC}"

    # 使用 Python 3.10 slim 镜像 + 编译工具
    # PaddlePaddle 对 Python 3.10 支持最完善
    docker run --rm \
        -v "${MODEL_DIR}:/app/models" \
        -e PPNLP_HOME=/app/models \
        -e HF_ENDPOINT=https://hf-mirror.com \
        python:3.10-slim \
        bash -c "
            set -e
            echo '安装编译依赖...'
            apt-get update -qq && apt-get install -qq -y --no-install-recommends \
                cmake build-essential > /dev/null 2>&1

            echo '安装 PaddlePaddle 和 PaddleNLP...'
            pip install --no-cache-dir -q 'setuptools>=75.0.0' paddlepaddle 'aistudio_sdk==0.2.1' 'paddlenlp==2.8.1'

            echo '检查目录权限...'
            ls -la /app/models/
            df -h /app/models/

            python -c \"
import os
os.environ['PPNLP_HOME'] = '/app/models'
print(f'PPNLP_HOME: {os.environ.get(\\\"PPNLP_HOME\\\")}')

from paddlenlp import Taskflow
print('初始化 NER (${ner_mode})...')
ner = Taskflow('ner', mode='${ner_mode}')
result = ner('测试文本')
print(f'测试结果: {result}')
print('✓ ${ner_mode} 模型下载完成')

# 验证模型文件
import subprocess
subprocess.run(['ls', '-la', '/app/models/taskflow/'], check=False)
\"
        "
}

case "$MODE" in
    fast)
        download_model "fast"
        ;;
    accurate)
        download_model "accurate"
        ;;
    all)
        download_model "fast"
        echo
        download_model "accurate"
        ;;
    *)
        echo "用法: $0 [fast|accurate|all]"
        exit 1
        ;;
esac

echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ 模型下载完成${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo "模型目录: ${MODEL_DIR}"
du -sh "$MODEL_DIR" 2>/dev/null || true
