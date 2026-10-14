# syntax=docker/dockerfile:1
# Python é FERRAMENTA (dados/ML, automação), não serviço de produto novo. uv resolve com lock; a venv é copiada pronta.
# Digests verificados em 2026-10-14; renove por Renovate/Dependabot, não à mão.
# Build: docker buildx build --provenance=mode=max --sbom=true --build-arg SOURCE_DATE_EPOCH=$(git log -1 --pretty=%ct) -t tool:sha-$(git rev-parse HEAD) .

FROM ghcr.io/astral-sh/uv:0.13.1@sha256:4a1f3666816dafadd20ceb71eac9a7d56d7ef30279f7d64048519ab901ada336 AS uv

FROM python:3.14-slim@sha256:a2b82f3c48559aa0a8446d9af49826b6e2b2016f4cd2afabfe6013ec53729170 AS build
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
COPY --link --from=uv /uv /usr/local/bin/uv

# pyproject + uv.lock antes do código; --frozen não reescreve o lock, --no-install-project deixa a camada de deps estável.
COPY --link pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project
COPY --link . .
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-editable

FROM python:3.14-slim@sha256:a2b82f3c48559aa0a8446d9af49826b6e2b2016f4cd2afabfe6013ec53729170
WORKDIR /app
ENV PATH="/app/.venv/bin:${PATH}" PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
COPY --link --from=build --chown=10001:10001 /app/.venv /app/.venv
COPY --link --from=build --chown=10001:10001 /app/src /app/src
USER 10001:10001
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["python", "-c", "import tool"]
ENTRYPOINT ["python", "-m", "tool"]
CMD ["--help"]
