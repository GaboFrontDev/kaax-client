FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONPATH=/app:/app/core

WORKDIR /app

RUN pip install --no-cache-dir uv

# Client manifest and lock
COPY pyproject.toml uv.lock ./

# Client-specific files
COPY main.py client.py config.yaml ./
COPY states/ ./states/
COPY tools/ ./tools/
COPY prompts/ ./prompts/

# Core engine (git submodule — must be present at build time)
COPY core/ ./core/

RUN uv sync --frozen --no-dev --no-install-project

EXPOSE 8200

CMD ["/app/.venv/bin/uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8200"]
