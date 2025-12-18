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

            echo '清理不完整的模型缓存...'
            rm -rf /app/models/taskflow/lac
            rm -rf /app/models/taskflow/wordtag

            echo '检查目录状态...'
            ls -la /app/models/
            df -h /app/models/

            python << PYEOF
import os
import sys

os.environ['PPNLP_HOME'] = '/app/models'
print(f'PPNLP_HOME: {os.environ["PPNLP_HOME"]}')

# 先下载模型，不加载推理引擎
from paddlenlp.taskflow.lexical_analysis import LacTask

print('下载 LAC 模型...')
task = LacTask(task='ner', model='lac', mode='${ner_mode}', lazy_load=True)

# 检查文件
model_dir = '/app/models/taskflow/lac/static'
print(f'\\n检查模型目录: {model_dir}')
if os.path.exists(model_dir):
    for f in os.listdir(model_dir):
        fpath = os.path.join(model_dir, f)
        size = os.path.getsize(fpath) if os.path.isfile(fpath) else 0
        print(f'  {f}: {size} bytes')
else:
    print('  目录不存在!')
    sys.exit(1)

# 验证关键文件
pdmodel = os.path.join(model_dir, 'inference.pdmodel')
pdiparams = os.path.join(model_dir, 'inference.pdiparams')

if not os.path.exists(pdmodel):
    print(f'\\n错误: {pdmodel} 不存在!')
    sys.exit(1)
if not os.path.exists(pdiparams):
    print(f'\\n错误: {pdiparams} 不存在!')
    sys.exit(1)

print('\\n✓ 模型文件验证通过')

# 现在测试推理
print('\\n测试推理...')
from paddlenlp import Taskflow
ner = Taskflow('ner', mode='${ner_mode}')
result = ner('测试文本')
print(f'测试结果: {result}')
print('✓ ${ner_mode} 模型下载完成')
PYEOF
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
