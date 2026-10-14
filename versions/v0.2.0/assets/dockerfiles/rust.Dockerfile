# syntax=docker/dockerfile:1
# Rust com alvo musl (binário estático) em distroless static nonroot. Para crates que exigem glibc,
# troque o alvo para *-unknown-linux-gnu e o runtime para distroless/cc-debian13:nonroot@sha256:e792ab3d241a468a4fd7519ddbbebe66b49b5f365771716ea688ad40b6c6f1c2.
# Digests verificados em 2026-10-14; renove por Renovate/Dependabot, não à mão.
# Build: docker buildx build --provenance=mode=max --sbom=true --build-arg SOURCE_DATE_EPOCH=$(git log -1 --pretty=%ct) -t app:sha-$(git rev-parse HEAD) .

FROM rust:1.99-alpine@sha256:0cce0a5e0e8ba67b455257a3a02a1d99005f382748789d6464460028810f1627 AS build
WORKDIR /src
ARG SOURCE_DATE_EPOCH
# Em Alpine o alvo nativo já é musl. Para multi-arch, o buildx roda este estágio por plataforma.
ENV CARGO_TERM_COLOR=never RUSTFLAGS="-C target-feature=+crt-static"

# Alternativa para cache de dependências em CI frio: cargo-chef (cargo chef prepare/cook) em estágios
# planner/cook antes do COPY do código. Aqui o cache mount de registry/target já cobre o caso comum.

# Manifesto + lockfile antes do código.
COPY --link Cargo.toml Cargo.lock ./
COPY --link crates ./crates
COPY --link src ./src

# `target` é cache mount (não persiste na camada): o binário é copiado para fora dele no mesmo RUN.
# --locked garante que o Cargo.lock versionado é o que compila.
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/src/target \
    cargo build --release --locked --bin app \
    && install -D target/release/app /out/app

FROM gcr.io/distroless/static-debian13:nonroot@sha256:e2e927ec666bae08560abb3c55d0659eceabb657f56b6782ab500a9fc7f555e3
COPY --link --from=build /out/app /app
USER 65532:65532
EXPOSE 8080
# Sem shell: a probe é um subcomando do binário (implemente `app healthcheck`).
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 CMD ["/app", "healthcheck"]
ENTRYPOINT ["/app"]
CMD ["serve"]
