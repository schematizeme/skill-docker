# syntax=docker/dockerfile:1
# Elixir: `mix release` compilado em Alpine e executado em Alpine mínimo (release já embute o ERTS).
# Digests verificados em 2026-10-14; renove por Renovate/Dependabot, não à mão.
# Build: docker buildx build --provenance=mode=max --sbom=true --build-arg SOURCE_DATE_EPOCH=$(git log -1 --pretty=%ct) -t app:sha-$(git rev-parse HEAD) .

FROM elixir:1.20-otp-28-alpine@sha256:54a8abc9bb4c4ee308f09b07ca27a9b5c91bb245d71c97fbc72e0c7ac60a8880 AS build
WORKDIR /app
ENV MIX_ENV=prod
RUN apk add --no-cache build-base git
RUN mix local.hex --force && mix local.rebar --force

# mix.exs + mix.lock antes do código: deps só recompilam quando o lock muda.
COPY --link mix.exs mix.lock ./
COPY --link config ./config
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.cache/rebar3 \
    mix deps.get --only prod && mix deps.compile

COPY --link lib ./lib
COPY --link priv ./priv
# Phoenix: descomente se houver assets (mix assets.deploy).
# RUN mix assets.deploy
RUN mix compile && mix release app

FROM alpine:3.23@sha256:85fe1e81d6758c208f3e1eed4338a1997e19d4be002d4dd32d3100c9a8c010a0
# Bibliotecas dinâmicas que o ERTS precisa em musl.
RUN apk add --no-cache libstdc++ openssl ncurses-libs \
    && addgroup -g 10001 -S app && adduser -u 10001 -S -G app -h /app -s /sbin/nologin app
WORKDIR /app
COPY --link --from=build --chown=10001:10001 /app/_build/prod/rel/app ./
ENV LANG=C.UTF-8 PHX_SERVER=true
USER 10001:10001
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:4000/healthz"]
ENTRYPOINT ["/app/bin/app"]
CMD ["start"]
