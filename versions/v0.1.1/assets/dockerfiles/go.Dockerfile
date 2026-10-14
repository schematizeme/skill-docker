# syntax=docker/dockerfile:1
# Go estático (CGO_ENABLED=0) em distroless static nonroot: sem shell, sem gerenciador de pacote.
# Digests verificados em 2026-10-14; renove por Renovate/Dependabot, não à mão.
# Build: docker buildx build --provenance=mode=max --sbom=true --build-arg SOURCE_DATE_EPOCH=$(git log -1 --pretty=%ct) -t app:sha-$(git rev-parse HEAD) .

FROM golang:1.27-alpine@sha256:f92b6ef800e499660581efdabdf25d9d817a9d124eaf900924f0504e7e27e12d AS build
WORKDIR /src
# Data de reprodutibilidade (timestamp do commit); o buildx também a usa para normalizar mtime das camadas.
ARG SOURCE_DATE_EPOCH
ARG TARGETOS
ARG TARGETARCH
ENV CGO_ENABLED=0 GOFLAGS=-mod=readonly

# Manifesto antes do código: a camada de dependências só invalida quando go.mod/go.sum mudam.
COPY --link go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY --link . .
# -trimpath remove caminhos da máquina; -buildvcs=false evita carimbar estado do git (contexto sem .git);
# -s -w tira símbolos e DWARF. O mesmo código + mesmo SOURCE_DATE_EPOCH gera o mesmo binário.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
    go build -trimpath -buildvcs=false -ldflags "-s -w" -o /out/app ./cmd/app

FROM gcr.io/distroless/static-debian13:nonroot@sha256:e2e927ec666bae08560abb3c55d0659eceabb657f56b6782ab500a9fc7f555e3
COPY --link --from=build /out/app /app
# UID/GID numérico fixo (distroless nonroot = 65532).
USER 65532:65532
EXPOSE 8080
# Sem shell na imagem: a probe é um subcomando do próprio binário (implemente `app healthcheck`).
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 CMD ["/app", "healthcheck"]
ENTRYPOINT ["/app"]
CMD ["serve"]
