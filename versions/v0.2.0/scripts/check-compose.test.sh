#!/usr/bin/env bash
# Vermelho primeiro do gate de compose. Cada fixture é um compose.yaml de mentira com UM defeito.
# Não usa o daemon Docker nem o `docker compose`: o gate é estático.
#
# EXCEÇÃO DECLARADA (`schematize-shell` -> `references/piso.md` seção 1): harness de teste roda
# `set -u` sem `-e` — precisa continuar depois de um caso vermelho para reportar todos.
set -uo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
G="$AQUI/check-compose.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP:?}"' EXIT INT TERM
ok=0; fail=0
D='sha256:77f585114c32fbca283dc835b0596f4e52b51b4c6662d7810b2f4084f60a1873'

# caso <nome> <exit-esperado> <agulha> [flag]  — o compose vem pelo stdin (heredoc).
caso() {
  local nome="$1" esp="$2" agulha="$3" flag="${4:-}"
  local d="$TMP/$nome"; mkdir -p "$d"
  cat > "$d/compose.yaml"
  local saida rc
  # shellcheck disable=SC2086 # $flag é no máximo uma opção simples
  saida="$(bash "$G" $flag "$d" 2>&1)"; rc=$?
  if [ "$rc" != "$esp" ]; then echo "  ✖ $nome: exit $rc, esperado $esp"; sed 's/^/      /' <<<"$saida"; fail=$((fail+1)); return; fi
  if [ -n "$agulha" ] && ! grep -qF -- "$agulha" <<<"$saida"; then echo "  ✖ $nome: exit certo, saída sem \"$agulha\""; sed 's/^/      /' <<<"$saida"; fail=$((fail+1)); return; fi
  echo "  ✔ $nome"; ok=$((ok+1))
}

echo "== verde de partida =="
caso verde-completo 0 "piso cumprido" --strict <<FIX
services:
  app:
    image: ghcr.io/acme/app:sha-1a2b3c4@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    user: "10001:10001"
    read_only: true
    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
    mem_limit: 256m
    pids_limit: 200
    ports:
      - "127.0.0.1:8080:8080"
    environment:
      LOG_LEVEL: info
      DB_PASSWORD_FILE: /run/secrets/db_password
      API_TOKEN: \${API_TOKEN}
    healthcheck:
      test: ["CMD", "/app", "--healthcheck"]
    depends_on:
      db:
        condition: service_healthy
  db:
    image: postgres:18-alpine@$D
    read_only: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    mem_limit: 512m
    pids_limit: 200
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
    volumes:
      - pgdata:/var/lib/postgresql/data
volumes:
  pgdata:
FIX

echo "== erros de segurança =="
caso privileged 1 "privileged: true" <<'FIX'
services:
  app:
    image: app:1
    privileged: true
FIX
caso docker-sock 1 "docker.sock" <<'FIX'
services:
  ci:
    image: app:1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
FIX
caso docker-sock-ro-tambem 1 "docker.sock" <<'FIX'
services:
  ci:
    image: app:1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
FIX
caso banco-publicado 1 "porta publicada em 0.0.0.0" <<'FIX'
services:
  db:
    image: postgres:18
    ports:
      - "5432:5432"
FIX
caso banco-porta-so-container 1 "porta publicada em 0.0.0.0" <<'FIX'
services:
  cache:
    image: redis:8
    ports:
      - 6379
FIX
caso banco-publicado-0000 1 "porta publicada em 0.0.0.0" <<'FIX'
services:
  db:
    image: mysql:9
    ports:
      - "0.0.0.0:3306:3306"
FIX
caso banco-sintaxe-longa 1 "sintaxe longa" <<'FIX'
services:
  db:
    image: postgres:18
    ports:
      - target: 5432
        published: 5432
FIX
caso banco-loopback-so-avisa 0 "loopback" <<'FIX'
services:
  db:
    image: postgres:18
    ports:
      - "127.0.0.1:15432:5432"
FIX
caso segredo-literal-mapa 1 "valor literal" <<'FIX'
services:
  app:
    image: app:1
    environment:
      API_KEY: abc123
FIX
caso segredo-literal-lista 1 "valor literal" <<'FIX'
services:
  db:
    image: postgres:18
    environment:
      - POSTGRES_PASSWORD=hunter2
FIX
caso segredo-interpolado-ok 0 "piso cumprido" <<'FIX'
services:
  app:
    image: app:1
    environment:
      API_KEY: ${API_KEY}
      DB_PASSWORD_FILE: /run/secrets/db
FIX
caso banco-trust 1 "autenticação desligada" <<'FIX'
services:
  db:
    image: postgres:18
    environment:
      - POSTGRES_HOST_AUTH_METHOD=trust
FIX
caso network-host 1 "network_mode: host" <<'FIX'
services:
  app:
    image: app:1
    network_mode: host
FIX
caso user-root 1 "user: root" <<'FIX'
services:
  app:
    image: app:1
    user: root
FIX
caso cap-sys-admin 1 "cap_add" <<'FIX'
services:
  app:
    image: app:1
    cap_add:
      - SYS_ADMIN
FIX
caso seccomp-unconfined 1 "unconfined" <<'FIX'
services:
  app:
    image: app:1
    security_opt:
      - seccomp:unconfined
FIX
caso image-latest 1 "sem tag fixa" <<'FIX'
services:
  app:
    image: nginx:latest
FIX
caso image-sem-tag 1 "sem tag fixa" <<'FIX'
services:
  app:
    image: nginx
FIX

echo "== dependência e saúde =="
caso depends-lista-avisa 0 "depends_on em forma de lista" <<'FIX'
services:
  app:
    image: app:1
    depends_on:
      - db
  db:
    image: postgres:18
FIX
caso depends-lista-strict 1 "depends_on em forma de lista" --strict <<'FIX'
services:
  app:
    image: app:1
    depends_on:
      - db
  db:
    image: postgres:18
FIX
caso healthy-sem-healthcheck 1 "não declara healthcheck" <<'FIX'
services:
  app:
    image: app:1
    depends_on:
      db:
        condition: service_healthy
  db:
    image: postgres:18
FIX
caso banco-service-started 0 "service_started" <<'FIX'
services:
  app:
    image: app:1
    depends_on:
      db:
        condition: service_started
  db:
    image: postgres:18
FIX

echo "== avisos de hardening / higiene =="
caso sem-hardening-avisa 0 "cap_drop" <<'FIX'
services:
  app:
    image: app:1
FIX
caso sem-hardening-strict 1 "read_only" --strict <<'FIX'
services:
  app:
    image: app:1
FIX
caso version-obsoleta 1 "obsoleta" --strict <<'FIX'
version: "3.9"
services:
  app:
    image: app:1
FIX
caso admin-sem-profile 1 "fora de 'profiles:'" --strict <<'FIX'
services:
  adminer:
    image: adminer:5
FIX
caso merge-key-avisa 0 "âncora/merge" <<'FIX'
x-base: &base
  image: app:1
services:
  app:
    <<: *base
FIX
caso waiver-por-servico 0 "piso cumprido" <<'FIX'
services:
  # docker-ok: serviço de teste efêmero, sem estado
  app:
    image: app:1
FIX

echo "== .env fora do git =="
d="$TMP/env-versionado"; mkdir -p "$d"
printf 'services:\n  app:\n    image: app:1\n' > "$d/compose.yaml"; printf 'X=1\n' > "$d/.env"
git -C "$d" init -q -b main 2>/dev/null && git -C "$d" add .env compose.yaml 2>/dev/null
saida="$(bash "$G" "$d" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -qF "VERSIONADO" <<<"$saida"; then echo "  ✔ env-versionado"; ok=$((ok+1)); else echo "  ✖ env-versionado: rc=$rc"; sed 's/^/      /' <<<"$saida"; fail=$((fail+1)); fi
d="$TMP/env-ignorado"; mkdir -p "$d"
printf 'services:\n  app:\n    image: app:1\n' > "$d/compose.yaml"; printf 'X=1\n' > "$d/.env"; printf '.env\n' > "$d/.gitignore"
git -C "$d" init -q -b main 2>/dev/null
saida="$(bash "$G" "$d" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && ! grep -qF ".env existe" <<<"$saida"; then echo "  ✔ env-ignorado"; ok=$((ok+1)); else echo "  ✖ env-ignorado: rc=$rc"; sed 's/^/      /' <<<"$saida"; fail=$((fail+1)); fi
d="$TMP/env-nao-ignorado"; mkdir -p "$d"
printf 'services:\n  app:\n    image: app:1\n' > "$d/compose.yaml"; printf 'X=1\n' > "$d/.env"
git -C "$d" init -q -b main 2>/dev/null
saida="$(bash "$G" --strict "$d" 2>&1)"; rc=$?
if [ "$rc" = 1 ] && grep -qF "NÃO está no .gitignore" <<<"$saida"; then echo "  ✔ env-nao-ignorado-strict"; ok=$((ok+1)); else echo "  ✖ env-nao-ignorado-strict: rc=$rc"; sed 's/^/      /' <<<"$saida"; fail=$((fail+1)); fi

echo "== fail-closed =="
mkdir -p "$TMP/vazio"
saida="$(bash "$G" "$TMP/vazio" 2>&1)"; rc=$?
if [ "$rc" = 2 ] && grep -q "nada para verificar" <<<"$saida"; then echo "  ✔ dir-sem-compose-sai-2"; ok=$((ok+1)); else echo "  ✖ dir-sem-compose: rc=$rc"; fail=$((fail+1)); fi

echo
echo "$ok verde(s), $fail falha(s)"
[ "$fail" -eq 0 ]
