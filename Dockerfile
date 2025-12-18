# ============================================
# Sensitive Data Masking - Multi-stage Dockerfile
# ============================================
# 注意: 强制使用 amd64 架构，因为 PaddleNLP 的依赖 (tool-helpers)
# 只提供 x86_64 wheel，不支持 ARM64
# ============================================

# ============================================
# Stage 1: Builder (强制 amd64 架构)
# ============================================
FROM --platform=linux/amd64 python:3.12-slim AS builder

WORKDIR /app

# 安装编译依赖 (cmake 用于编译 onnxoptimizer)
RUN apt-get update && \
    apt-get install -y --no-install-recommends cmake build-essential && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project --no-dev --group paddle

# ============================================
# Stage 2: Runtime (强制 amd64 架构)
# ============================================
FROM --platform=linux/amd64 python:3.12-slim AS runtime

LABEL maintainer="daoji"
LABEL description="Sensitive Data Masking - 基于 NLP 的中文敏感信息识别与脱敏工具"

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl libgomp1 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# 环境变量
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONPATH=/app
ENV PATH="/app/.venv/bin:$PATH"

# 模型配置
ENV MODEL_DIR=/app/models
ENV PPNLP_HOME=/app/models

# PaddlePaddle 优化配置
ENV FLAGS_use_mkldnn=1
ENV FLAGS_mkldnn_cache_capacity=1
ENV OMP_NUM_THREADS=4
ENV MKL_NUM_THREADS=4

# NER 模式: fast / accurate
ENV NER_MODE=fast

COPY --from=builder /app/.venv /app/.venv
COPY demo.py app.py /app/
COPY scripts/download_models.py /app/scripts/

RUN mkdir -p /app/models && \
    useradd --create-home appuser && \
    chown -R appuser:appuser /app

USER appuser

EXPOSE 7860

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:7860/ || exit 1

CMD ["python", "app.py"]
