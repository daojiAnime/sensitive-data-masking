# 强制 amd64 架构：PaddleNLP 依赖 (tool-helpers) 只提供 x86_64 wheel

# Stage 1: Builder
FROM --platform=linux/amd64 ghcr.io/astral-sh/uv:python3.10-bookworm-slim AS builder

WORKDIR /app

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project --no-dev --group paddle

# Stage 2: Runtime
FROM --platform=linux/amd64 python:3.10-slim AS runtime

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl libgomp1 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    groupadd --system --gid 999 appuser && \
    useradd --system --gid 999 --uid 999 --create-home appuser && \
    mkdir -p /app/models && \
    chown -R appuser:appuser /app

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app \
    PATH="/app/.venv/bin:$PATH" \
    MODEL_DIR=/app/models \
    PPNLP_HOME=/app/models \
    FLAGS_use_mkldnn=1 \
    FLAGS_mkldnn_cache_capacity=1 \
    OMP_NUM_THREADS=4 \
    MKL_NUM_THREADS=4 \
    NER_MODE=fast

COPY --from=builder --chown=appuser:appuser /app/.venv /app/.venv
COPY --chown=appuser:appuser demo.py app.py /app/
COPY --chown=appuser:appuser scripts/download_models.py /app/scripts/

USER appuser

EXPOSE 7860

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:7860/ || exit 1

CMD ["python", "app.py"]
