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

check_memory() {
    # 检查可用内存（需要至少 4G）
    local available_mb
    available_mb=$(free -m | awk '/^Mem:/{print $7}')

    if [ "$available_mb" -lt 4096 ]; then
        echo -e "${YELLOW}⚠ 警告: 可用内存 ${available_mb}MB < 4096MB${NC}"
        echo -e "${YELLOW}  PaddlePaddle 模型转换需要较大内存，可能会失败${NC}"
        echo -e "${YELLOW}  建议: 添加 swap 空间 (sudo fallocate -l 4G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile)${NC}"
        echo
    fi
}

download_model() {
    local ner_mode=$1
    echo -e "${YELLOW}▸ 下载 ${ner_mode} 模式模型...${NC}"

    docker run --rm \
        --memory=4g \
        --memory-swap=8g \
        -v "${MODEL_DIR}:/app/models" \
        -e PPNLP_HOME=/app/models \
        python:3.10-slim \
        bash -c "
            set -e

            # 检查模型是否已存在
            if [ -f /app/models/taskflow/lac/static/inference.pdmodel ]; then
                echo '✓ 模型已存在，跳过下载'
                exit 0
            fi

            apt-get update -qq && apt-get install -qq -y --no-install-recommends cmake build-essential > /dev/null 2>&1
            pip install --no-cache-dir -q 'setuptools>=75.0.0' paddlepaddle 'aistudio_sdk==0.2.1' 'paddlenlp==2.8.1'

            # 清理不完整的缓存
            rm -rf /app/models/taskflow/lac /app/models/taskflow/wordtag

            python -c \"
import os
import subprocess
os.environ['PPNLP_HOME'] = '/app/models'

print('PPNLP_HOME:', os.environ['PPNLP_HOME'])
print('初始化 NER (${ner_mode})...')

from paddlenlp import Taskflow
ner = Taskflow('ner', mode='${ner_mode}')
print(ner('测试文本'))
print('✓ ${ner_mode} 模型下载完成')
\"
            # 强制同步文件系统
            sync

            echo '验证模型文件:'
            ls -la /app/models/taskflow/lac/static/ 2>/dev/null || echo '模型目录不存在!'
        "
}

check_memory

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
