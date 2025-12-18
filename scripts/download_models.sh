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
os.environ['PPNLP_HOME'] = '/app/models'

print('PPNLP_HOME:', os.environ['PPNLP_HOME'])
print('下载模型文件...')

# 只下载，不加载推理
from paddlenlp.taskflow.lexical_analysis import LacTask
task = LacTask(task='ner', model='lac', mode='${ner_mode}', lazy_load=True)

# 强制同步
import subprocess
subprocess.run(['sync'])

# 检查文件
model_path = '/app/models/taskflow/lac/static/inference.pdmodel'
if os.path.exists(model_path):
    size = os.path.getsize(model_path)
    print(f'✓ 模型文件已创建: {size} bytes')
else:
    print('✗ 模型文件不存在!')
    # 列出目录内容
    static_dir = '/app/models/taskflow/lac/static'
    if os.path.exists(static_dir):
        print(f'static 目录内容: {os.listdir(static_dir)}')
    else:
        print('static 目录不存在')
    exit(1)

print('测试推理...')
from paddlenlp import Taskflow
ner = Taskflow('ner', mode='${ner_mode}')
print(ner('测试文本'))
print('✓ ${ner_mode} 模型下载完成')
\"
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
