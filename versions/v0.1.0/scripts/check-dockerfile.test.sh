#!/usr/bin/env bash
# Vermelho primeiro do gate de Dockerfile. Cada fixture é um Dockerfile de mentira com UM defeito.
# Não usa o daemon Docker nem rede: o gate é estático.
#
# EXCEÇÃO DECLARADA (`schematize-shell` -> `references/piso.md` seção 1): harness de teste roda
# `set -u` sem `-e` — precisa continuar depois de um caso vermelho para reportar todos.
set -uo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
G="$AQUI/check-dockerfile.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP:?}"' EXIT INT TERM
ok=0; fail=0
D='sha256:f92b6ef800e499660581efdabdf25d9d817a9d124eaf900924f0504e7e27e12d'
DI='.git
.env
.env.*
node_modules
'

# caso <nome> <exit-esperado> <agulha> [flag-do-gate]  — o Dockerfile vem pelo stdin (heredoc).
# DI_MODE=none => sem .dockerignore · DI_MODE=semenv => .dockerignore sem .env.
caso() {
  local nome="$1" esp="$2" agulha="$3" flag="${4:-}"
  local d="$TMP/$nome"; mkdir -p "$d"
  cat > "$d/Dockerfile"
  case "${DI_MODE:-ok}" in
    none) : ;;
    semenv) printf '.git\nnode_modules\n' > "$d/.dockerignore" ;;
    *) printf '%s' "$DI" > "$d/.dockerignore" ;;
  esac
  local saida rc
  # shellcheck disable=SC2086 # $flag é no máximo uma opção simples
  saida="$(bash "$G" --no-hadolint $flag "$d" 2>&1)"; rc=$?
  if [ "$rc" != "$esp" ]; then echo "  ✖ $nome: exit $rc, esperado $esp"; sed 's/^/      /' <<<"$saida"; fail=$((fail+1)); return; fi
  if [ -n "$agulha" ] && ! grep -qF -- "$agulha" <<<"$saida"; then echo "  ✖ $nome: exit certo, saída sem \"$agulha\""; sed 's/^/      /' <<<"$saida"; fail=$((fail+1)); return; fi
  echo "  ✔ $nome"; ok=$((ok+1))
}

echo "== verde de partida =="
caso verde-go 0 "piso cumprido" --strict <<FIX
# syntax=docker/dockerfile:1
ARG GO=golang:1.27-alpine@$D
FROM \${GO} AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -o /out/app ./cmd/app
FROM gcr.io/distroless/static-debian13:nonroot@$D
COPY --from=build /out/app /app
USER 65532:65532
HEALTHCHECK NONE
ENTRYPOINT ["/app"]
FIX
caso verde-scratch-e-stage 0 "piso cumprido" --strict <<FIX
# syntax=docker/dockerfile:1
FROM alpine:3.23@$D AS certs
RUN apk add --no-cache ca-certificates=20250911-r0
FROM certs AS final
FROM scratch
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
USER 10001:10001
HEALTHCHECK NONE
ENTRYPOINT ["/app"]
FIX
caso verde-heredoc-apt 0 "piso cumprido" --strict <<FIX
# syntax=docker/dockerfile:1
FROM debian:trixie-slim@$D
RUN <<EOT
set -eu
apt-get update
apt-get install -y --no-install-recommends ca-certificates=20250419
rm -rf /var/lib/apt/lists/*
EOT
USER 10001:10001
HEALTHCHECK CMD ["/app","--healthcheck"]
ENTRYPOINT ["/app"]
FIX

echo "== FROM =="
caso from-sem-digest 1 "sem digest" <<'FIX'
FROM alpine:3.23
USER 10001
FIX
caso from-latest 1 "'latest'" <<'FIX'
FROM alpine:latest
USER 10001
FIX
caso from-sem-tag 1 "sem tag" <<'FIX'
FROM alpine
USER 10001
FIX
caso from-arg-sem-default 1 "não resolvível" <<'FIX'
ARG BASE
FROM ${BASE}
USER 10001
FIX
caso from-arg-sem-digest 1 "sem digest" <<'FIX'
ARG BASE=alpine:3.23
FROM ${BASE}
USER 10001
FIX

echo "== USER =="
caso sem-user 1 "sem USER" <<FIX
FROM alpine:3.23@$D
FIX
caso user-root 1 "USER root" <<FIX
FROM alpine:3.23@$D
USER root
FIX
caso user-zero-grupo 1 "USER 0:0" <<FIX
FROM alpine:3.23@$D
USER 0:0
FIX
caso user-so-no-primeiro-estagio 1 "estágio final sem USER" <<FIX
FROM alpine:3.23@$D AS build
USER 10001
FROM alpine:3.23@$D
FIX
caso user-por-nome-avisa 0 "por nome" <<FIX
FROM alpine:3.23@$D
USER app
FIX
caso user-por-nome-strict 1 "por nome" --strict <<FIX
FROM alpine:3.23@$D
USER app
FIX

echo "== segredo =="
caso arg-segredo 1 "ARG API_TOKEN" <<FIX
FROM alpine:3.23@$D
ARG API_TOKEN
USER 10001
FIX
caso env-segredo-forma-nova 1 "ENV DB_PASSWORD" <<FIX
FROM alpine:3.23@$D
ENV LOG=1 DB_PASSWORD=x
USER 10001
FIX
caso env-segredo-forma-antiga 1 "ENV AWS_SECRET_ACCESS_KEY" <<FIX
FROM alpine:3.23@$D
ENV AWS_SECRET_ACCESS_KEY abc
USER 10001
FIX
caso env-arquivo-de-segredo-ok 0 "piso cumprido" <<FIX
FROM alpine:3.23@$D
ENV DB_PASSWORD_FILE=/run/secrets/db
USER 10001
FIX
caso copy-env 1 "COPY de arquivo de segredo" <<FIX
FROM alpine:3.23@$D
COPY .env /app/.env
USER 10001
FIX
caso copy-chave 1 "COPY de arquivo de segredo" <<FIX
FROM alpine:3.23@$D
COPY certs/server.key /etc/ssl/
USER 10001
FIX

echo "== instruções perigosas =="
caso add-remoto 1 "ADD de origem remota" <<FIX
FROM alpine:3.23@$D
ADD https://example.org/x.tar.gz /x
USER 10001
FIX
caso curl-pipe-sh 1 "curl|sh" <<FIX
FROM alpine:3.23@$D
RUN curl -fsSL https://example.org/i.sh | sh
USER 10001
FIX
caso wget-pipe-bash 1 "curl|sh" <<FIX
FROM alpine:3.23@$D
RUN wget -qO- https://example.org/i.sh | bash
USER 10001
FIX
caso curl-pipe-no-heredoc 1 "curl|sh" <<FIX
FROM alpine:3.23@$D
RUN <<EOT
curl -fsSL https://example.org/i.sh | sh
EOT
USER 10001
FIX
caso chmod-777 1 "chmod 777" <<FIX
FROM alpine:3.23@$D
RUN chmod -R 777 /app
USER 10001
FIX

echo "== pacotes =="
caso apt-sem-limpeza 1 "sem limpar /var/lib/apt/lists" <<FIX
FROM debian:trixie-slim@$D
RUN apt-get update && apt-get install -y --no-install-recommends curl=8.0
USER 10001
FIX
caso apt-sem-pin-strict 1 "sem pin de versão" --strict <<FIX
# syntax=docker/dockerfile:1
FROM debian:trixie-slim@$D
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
USER 10001
HEALTHCHECK NONE
ENTRYPOINT ["/x"]
FIX
caso apt-sem-recommends-strict 1 "--no-install-recommends" --strict <<FIX
FROM debian:trixie-slim@$D
RUN apt-get update && apt-get install -y curl=8.0 && rm -rf /var/lib/apt/lists/*
USER 10001
FIX
caso apk-sem-no-cache 1 "apk add sem --no-cache" <<FIX
FROM alpine:3.23@$D
RUN apk add curl
USER 10001
FIX

echo "== .dockerignore =="
DI_MODE=none caso sem-dockerignore 1 "sem .dockerignore" <<FIX
FROM alpine:3.23@$D
USER 10001
FIX
DI_MODE=semenv caso dockerignore-sem-env 1 "não exclui .env" <<FIX
FROM alpine:3.23@$D
USER 10001
FIX

echo "== avisos e strict =="
caso cmd-shell-form-avisa 0 "forma shell" <<FIX
FROM alpine:3.23@$D
USER 10001
CMD node app.js
FIX
caso cmd-shell-form-strict 1 "forma shell" --strict <<FIX
FROM alpine:3.23@$D
USER 10001
CMD node app.js
FIX
caso sem-healthcheck-strict 1 "sem HEALTHCHECK" --strict <<FIX
# syntax=docker/dockerfile:1
FROM alpine:3.23@$D
USER 10001
FIX
caso copy-amplo-antes-do-build 0 "cache de camada" <<FIX
FROM golang:1.27-alpine@$D
COPY . .
RUN go build ./...
USER 10001
FIX

echo "== waiver rastreável =="
caso waiver-com-motivo 0 "piso cumprido" <<FIX
# docker-ok: imagem de CI descartável, nunca publicada
FROM alpine:latest
USER 10001
FIX
caso waiver-sem-motivo-nao-vale 1 "sem digest" <<FIX
# docker-ok:
FROM alpine:3.23
USER 10001
FIX

echo "== fail-closed =="
mkdir -p "$TMP/vazio"
saida="$(bash "$G" --no-hadolint "$TMP/vazio" 2>&1)"; rc=$?
if [ "$rc" = 2 ] && grep -q "nada para verificar" <<<"$saida"; then echo "  ✔ dir-sem-dockerfile-sai-2"; ok=$((ok+1)); else echo "  ✖ dir-sem-dockerfile: rc=$rc"; fail=$((fail+1)); fi

echo
echo "$ok verde(s), $fail falha(s)"
[ "$fail" -eq 0 ]
