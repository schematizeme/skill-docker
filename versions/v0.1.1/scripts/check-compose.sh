#!/usr/bin/env bash
# schematize-docker — gate estático de compose (references/compose.md, runtime.md).
#
# Lê o compose.yaml VERSIONADO e cobra o piso do runtime de dev/hml: nada de --privileged nem
# docker.sock, banco nunca publicado fora do loopback, segredo fora de `environment`, dependência
# com healthcheck de verdade, `.env` fora do git. Não precisa do daemon nem do `docker compose`.
# Limite honesto: lê a FORMA LITERAL do YAML. Âncora/merge (`<<: *x`) e interpolação não são
# resolvidas — o script avisa; valide a forma final com `docker compose config`.
#
# EXCEÇÃO DECLARADA de strict mode (`schematize-shell` -> `references/piso.md` seção 1): COLETOR —
# soma os achados em vez de abortar no primeiro. Por isso `set -uo pipefail` sem `-e`.
#
# uso: check-compose.sh [--strict] [dir-ou-arquivo]
#   0 = passa · 1 = REPROVA · 2 = nenhum compose para verificar
#   --strict promove avisos a erros.
# Waiver rastreável por serviço: comentário `# docker-ok: <motivo>` na linha do nome do serviço
# ou na de cima isenta o AVISO de hardening daquele serviço (nunca erro de segurança).
set -uo pipefail

strict=0; alvo=""
for a in "$@"; do
  case "$a" in
    --strict) strict=1 ;;
    -*) echo "uso: check-compose.sh [--strict] [dir-ou-arquivo]" >&2; exit 2 ;;
    *) alvo="$a" ;;
  esac
done
alvo="${alvo:-.}"
erros=(); avisos=()
err()  { erros+=("$1"); }
warn() { avisos+=("$1"); }

arquivos=()
if [ -f "$alvo" ]; then
  arquivos+=("$alvo")
else
  while IFS= read -r -d '' f; do arquivos+=("$f"); done < <(
    find "$alvo" -type f \( -name 'compose.y*ml' -o -name 'compose.*.y*ml' -o -name 'docker-compose*.y*ml' \) \
      -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/versions/*' -not -path '*/target/*' -print0 2>/dev/null
  )
fi
if [ "${#arquivos[@]}" -eq 0 ]; then
  echo "✖ nenhum compose.yaml em $alvo — nada para verificar (ausência de artefato não é conformidade)." >&2
  exit 2
fi

# achatar — YAML (subconjunto de compose) -> linhas "caminho<TAB>valor". Mapas viram a.b.c; listas
# viram a.b[0]; item de lista com mapa vira a.b[0].k. Marca `#W` quando a linha (ou a de cima)
# carrega `docker-ok:`. Âncoras/merge: emite a linha "!merge" para o aviso.
achatar() {
  awk '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function unq(s) { s = trim(s); if (s ~ /^".*"$/ || s ~ /^'"'"'.*'"'"'$/) s = substr(s, 2, length(s) - 2); return s }
    function semcom(s,   i, c, q, out) {
      q = ""; out = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q == "" && (c == "\"" || c == "'"'"'")) q = c
        else if (q != "" && c == q) q = ""
        else if (q == "" && c == "#" && (i == 1 || substr(s, i-1, 1) ~ /[[:space:]]/)) break
        out = out c
      }
      return trim(out)
    }
    function caminho(n,   i, p) {
      p = ""
      for (i = 1; i <= n; i++) p = p ((i > 1 && nome[i] !~ /^\[/) ? "." : "") nome[i]
      return p
    }
    function emite(p, v) { printf "%s\t%s\n", p, v }
    # conteudo(col, txt): txt é "k: v", "k:" ou um escalar de item de lista; col = coluna do texto.
    function conteudo(col, txt,   k, v, pos, n, j, it) {
      if (txt ~ /^[A-Za-z0-9_.\/<-]+:([[:space:]]|$)/) {
        pos = index(txt, ":")
        k = unq(substr(txt, 1, pos - 1)); v = trim(substr(txt, pos + 1))
        while (depth > 0 && ia[depth] >= col) depth--
        depth++; ia[depth] = col; nome[depth] = k; cnt[depth] = 0
        if (k == "<<") { emite("!merge", v); emite(caminho(depth), v); depth--; return }
        if (v == "") return
        if (v ~ /^\[.*\]$/) {
          v = substr(v, 2, length(v) - 2); n = split(v, it, ",")
          for (j = 1; j <= n; j++) if (trim(it[j]) != "") emite(caminho(depth) "[" (j-1) "]", unq(it[j]))
        } else if (v ~ /^\*/) { emite(caminho(depth), v); emite("!merge", v) }
        else if (v ~ /^&/ || v ~ /^[|>]/) { emite(caminho(depth), "<bloco>") }
        else emite(caminho(depth), unq(v))
      } else {
        emite(caminho(depth), unq(txt))
      }
    }
    { raw[NR] = $0 }
    END {
      depth = 0
      for (i = 1; i <= NR; i++) {
        l = raw[i]
        if (l ~ /^[[:space:]]*(#|$)/ || l ~ /^(---|\.\.\.)/) continue
        s = semcom(l); if (s == "") continue
        match(l, /^[[:space:]]*/); I = RLENGTH
        w = ((l ~ /#[[:space:]]*docker-ok:[[:space:]]*[^[:space:]]+/) || (i > 1 && raw[i-1] ~ /#[[:space:]]*docker-ok:[[:space:]]*[^[:space:]]+/))
        if (s ~ /^-([[:space:]]|$)/) {
          while (depth > 0 && (ia[depth] > I || (ia[depth] == I && nome[depth] ~ /^\[/))) depth--
          if (depth == 0) continue
          idx = cnt[depth]++
          rest = s; sub(/^-[[:space:]]*/, "", rest)
          off = length(l) - length(l); match(l, /^[[:space:]]*-[[:space:]]*/); off = RLENGTH
          depth++; ia[depth] = I; nome[depth] = "[" idx "]"; cnt[depth] = 0
          if (rest == "") continue
          if (rest ~ /^[A-Za-z0-9_.\/<-]+:([[:space:]]|$)/) conteudo(off, rest)
          else { emite(caminho(depth), unq(rest)); depth-- }
          continue
        }
        conteudo(I, s)
        if (w && depth == 2 && nome[1] == "services") emite("!waiver:" nome[2], "1")
      }
    }' "$1"
}

secret_re='(PASSWORD|PASSWD|SECRET|TOKEN|API_?KEY|PRIVATE_?KEY|CREDENTIAL|ACCESS_?KEY|AUTH_?KEY)'
db_img_re='(^|/)(postgres|postgis|mysql|mariadb|mongo|redis|valkey|memcached|cassandra|clickhouse|cockroach|elasticsearch|opensearch|rabbitmq|nats|kafka|etcd|influxdb|timescale)'
db_port_re='^(5432|3306|6379|27017|1433|9042|11211|5984|2379|9200|9300|26257|8086|5672|4222|9092)$'

checar() {
  local f="$1" nome="$2"
  local flat; flat="$(achatar "$f")"
  [ -n "$flat" ] || { err "$nome: arquivo vazio ou ilegível"; return; }

  local -A tem=() val=()
  local k v
  while IFS=$'\t' read -r k v; do
    tem["$k"]=1
    val["$k"]="${val[$k]:-}${val[$k]:+|}$v"
    # lista escalar também responde pelo nome sem índice (healthcheck.test[0] => healthcheck.test)
    if [[ "$k" =~ ^(.*)\[[0-9]+\]$ ]]; then tem["${BASH_REMATCH[1]}"]=1; fi
  done <<< "$flat"

  if [ -n "${tem[!merge]:-}" ]; then
    warn "$nome: usa âncora/merge (<<: *x) — o gate lê a forma literal; valide o resultado com 'docker compose config'"
  fi
  [ -n "${tem[version]:-}" ] && warn "$nome: chave 'version:' é obsoleta no Compose v2+ — remova"

  # serviços
  local -a servicos=()
  while IFS= read -r s; do servicos+=("$s"); done < <(printf '%s\n' "$flat" | awk -F'\t' '$1 ~ /^services\.[^.\[]+/ { split($1, a, "."); sub(/\[.*/, "", a[2]); print a[2] }' | sort -u)
  if [ "${#servicos[@]}" -eq 0 ]; then err "$nome: nenhum serviço encontrado em 'services:'"; return; fi

  local s
  for s in "${servicos[@]}"; do
    local pre="services.$s" loc="${nome}[${s}]"
    local imagem="${val[$pre.image]:-}"
    local waiver="${tem[!waiver:$s]:-}"
    # linhas do serviço, sem cercar com regex em cada teste
    local sub; sub="$(printf '%s\n' "$flat" | awk -F'\t' -v p="$pre." 'index($1, p) == 1')"

    # ---- erros de segurança (waiver não vale)
    [[ "${val[$pre.privileged]:-}" =~ ^(true|yes|1)$ ]] && err "$loc: privileged: true — dá ao container o host inteiro; remova (capability específica, se for o caso)"
    if printf '%s\n' "$sub" | awk -F'\t' '$1 ~ /\.volumes\[/ && $2 ~ /docker\.sock|podman\.sock/ {f=1} END{exit !f}'; then
      err "$loc: monta o docker.sock — equivale a root no host; use socket proxy somente leitura ou builder remoto"
    fi
    if printf '%s\n' "$sub" | awk -F'\t' '$1 ~ /\.volumes\[/ && $2 ~ /^(\/|\/etc|\/proc|\/sys|\/root|\/boot|\/dev)(:|$)/ {f=1} END{exit !f}'; then
      err "$loc: bind-mount de diretório crítico do host (/, /etc, /proc, /sys, /dev...)"
    fi
    [[ "${val[$pre.network_mode]:-}" == host ]] && err "$loc: network_mode: host — derruba o isolamento de rede"
    [[ "${val[$pre.pid]:-}" == host ]] && err "$loc: pid: host — enxerga e sinaliza processos do host"
    [[ "${val[$pre.ipc]:-}" == host ]] && err "$loc: ipc: host — memória compartilhada do host"
    if printf '%s\n' "$sub" | awk -F'\t' '$1 ~ /\.cap_add\[/ && toupper($2) ~ /^(ALL|SYS_ADMIN|SYS_PTRACE|NET_ADMIN|SYS_MODULE|DAC_READ_SEARCH)$/ {f=1} END{exit !f}'; then
      err "$loc: cap_add de capability perigosa (ALL/SYS_ADMIN/SYS_PTRACE/NET_ADMIN/SYS_MODULE/DAC_READ_SEARCH)"
    fi
    if printf '%s\n' "$sub" | awk -F'\t' '$1 ~ /\.security_opt\[/ && $2 ~ /unconfined/ {f=1} END{exit !f}'; then
      err "$loc: security_opt com 'unconfined' — desliga seccomp/AppArmor"
    fi
    if printf '%s\n' "$sub" | awk -F'\t' '$1 ~ /\.devices\[/ {f=1} END{exit !f}'; then warn "$loc: expõe device do host (devices:) — confirme que é indispensável"; fi
    local u="${val[$pre.user]:-}"
    [[ "$u" =~ ^(root|0)(:|$) ]] && err "$loc: user: $u — container não-root é o piso"

    # imagem: tag móvel
    if [ -n "$imagem" ] && [[ "$imagem" != *'$'* ]]; then
      local sd="${imagem%%@*}" tg=""
      [[ "${sd##*/}" == *:* ]] && tg="${sd##*:}"
      if [ "$tg" = latest ] || { [ -z "$tg" ] && [[ "$imagem" != *@sha256:* ]]; }; then
        err "$loc: image $imagem sem tag fixa (latest) — versão muda sem ninguém decidir"
      elif [[ "$imagem" != *@sha256:* ]]; then
        warn "$loc: image $imagem sem digest (@sha256:...) — pine por digest em hml"
      fi
    fi

    # banco / porta publicada
    local eh_db=0
    [[ "$imagem" =~ $db_img_re ]] && eh_db=1
    [[ "$s" =~ ^(db|database|postgres|postgresql|mysql|mariadb|mongo|redis|cache|valkey)$ ]] && eh_db=1
    local linhas_porta; linhas_porta="$(printf '%s\n' "$sub" | awk -F'\t' '$1 ~ /\.ports\[[0-9]+\]$/ {print $2}')"
    local pt
    while IFS= read -r pt; do
      [ -n "$pt" ] || continue
      pt="${pt%/tcp}"; pt="${pt%/udp}"
      local ip="" cont=""
      IFS=':' read -r -a partes <<< "$pt"
      case "${#partes[@]}" in
        1) cont="${partes[0]}" ;;
        2) cont="${partes[1]}" ;;
        *) ip="${partes[0]}"; cont="${partes[$((${#partes[@]}-1))]}" ;;
      esac
      cont="${cont%%-*}"
      if [[ "$ip" == "["* ]]; then ip="${pt%%]*}]"; fi
      local loop=0; [[ "$ip" =~ ^(127\.0\.0\.1|localhost|\[::1\])$ ]] && loop=1
      if [ "$eh_db" = 1 ] || [[ "$cont" =~ $db_port_re ]]; then
        if [ "$loop" = 1 ]; then warn "$loc: banco/cache publicado em loopback ($pt) — aceitável só em dev local (profile debug); hml/prd não publica dado"
        else err "$loc: banco/cache com porta publicada em 0.0.0.0 ($pt) — dado exposto na rede; remova 'ports:' (use 'docker compose exec') ou prenda a 127.0.0.1"; fi
      elif [ "$loop" = 0 ]; then
        warn "$loc: porta $pt publicada em todas as interfaces — em dev prenda a 127.0.0.1:$pt"
      fi
    done <<< "$linhas_porta"
    # sintaxe longa: published/host_ip
    if printf '%s\n' "$sub" | awk -F'\t' '$1 ~ /\.ports\[[0-9]+\]\.published$/ {f=1} END{exit !f}'; then
      if [ "$eh_db" = 1 ] && ! printf '%s\n' "$sub" | awk -F'\t' '$1 ~ /\.ports\[[0-9]+\]\.host_ip$/ && $2 ~ /^(127\.0\.0\.1|::1)$/ {f=1} END{exit !f}'; then
        err "$loc: banco/cache publicado (sintaxe longa) sem host_ip de loopback — dado exposto na rede"
      fi
    fi

    # segredo literal em environment
    local envl; envl="$(printf '%s\n' "$sub" | awk -F'\t' '$1 ~ /\.environment/ {print $1 "\t" $2}')"
    local ek ev ch
    while IFS=$'\t' read -r ek ev; do
      [ -n "$ek" ] || continue
      if [[ "$ek" == *"].environment["* || "$ek" =~ \.environment\[[0-9]+\]$ ]]; then ch="${ev%%=*}"; ev="${ev#*=}"; [[ "$ev" == "${ch}" ]] && ev=""
      else ch="${ek##*.environment.}"; fi
      if [[ "$ch" =~ $secret_re ]] && [[ ! "$ch" =~ _FILE$ ]]; then
        if [ -n "$ev" ] && [[ "$ev" != *'${'* ]] && [[ "$ev" != '$'* ]]; then
          err "$loc: environment.$ch com valor literal — segredo no compose vai pro git; use 'secrets:' (file) ou \${VAR} vindo do .env fora do git"
        fi
      fi
    done <<< "$envl"
    # POSTGRES_PASSWORD etc. cobertos acima; trust auth é pior
    if printf '%s\n' "$sub" | awk -F'\t' '$2 ~ /POSTGRES_HOST_AUTH_METHOD=trust|^trust$|ALLOW_EMPTY_PASSWORD=yes|MYSQL_ALLOW_EMPTY_PASSWORD/ {f=1} END{exit !f}'; then
      err "$loc: banco com autenticação desligada (trust/ALLOW_EMPTY_PASSWORD)"
    fi

    # depends_on
    local dep_lista; dep_lista="$(printf '%s\n' "$sub" | awk -F'\t' '$1 ~ /\.depends_on\[[0-9]+\]$/ {print $2}')"
    local d
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      warn "$loc: depends_on em forma de lista ($d) — só espera o container ARRANCAR; use 'condition: service_healthy' com healthcheck"
    done <<< "$dep_lista"
    local dep_map; dep_map="$(printf '%s\n' "$sub" | awk -F'\t' '$1 ~ /\.depends_on\.[^.]+\.condition$/ {n=$1; sub(/^.*depends_on\./, "", n); sub(/\.condition$/, "", n); print n "\t" $2}')"
    local dn dc
    while IFS=$'\t' read -r dn dc; do
      [ -n "$dn" ] || continue
      if [ "$dc" = service_healthy ] && [ -z "${tem[services.$dn.healthcheck.test]:-}" ]; then
        err "$loc: depends_on $dn com service_healthy, mas '$dn' não declara healthcheck — o compose nunca considera saudável"
      elif [ "$dc" = service_started ]; then
        local dimg="${val[services.$dn.image]:-}"
        if [[ "$dimg" =~ $db_img_re ]] || [[ "$dn" =~ ^(db|database|postgres|mysql|mariadb|mongo|redis|cache)$ ]]; then
          warn "$loc: depends_on $dn (banco) com service_started — a app sobe antes do banco aceitar conexão; use service_healthy"
        fi
      fi
    done <<< "$dep_map"

    # ---- hardening e operação (avisos; waiver por serviço vale)
    if [ -z "$waiver" ]; then
      [ -n "${tem[$pre.healthcheck.test]:-}" ] || [ "${val[$pre.healthcheck.disable]:-}" = true ] || warn "$loc: sem healthcheck"
      printf '%s\n' "$sub" | awk -F'\t' '$1 ~ /\.cap_drop\[/ && toupper($2) == "ALL" {f=1} END{exit !f}' || warn "$loc: sem cap_drop: [ALL]"
      printf '%s\n' "$sub" | awk -F'\t' '$1 ~ /\.security_opt\[/ && $2 ~ /^no-new-privileges(:true)?$/ {f=1} END{exit !f}' || warn "$loc: sem security_opt: no-new-privileges:true"
      [[ "${val[$pre.read_only]:-}" =~ ^(true|yes)$ ]] || warn "$loc: sem read_only: true (com tmpfs onde precisar escrever)"
      if [ -z "${tem[$pre.mem_limit]:-}${tem[$pre.deploy.resources.limits.memory]:-}${tem[$pre.mem_reservation]:-}" ]; then warn "$loc: sem limite de memória (mem_limit)"; fi
      [ -n "${tem[$pre.pids_limit]:-}${tem[$pre.deploy.resources.limits.pids]:-}" ] || warn "$loc: sem pids_limit"
      if [[ "$s" =~ (adminer|pgadmin|phpmyadmin|mailhog|mailpit|redis-commander|portainer|mongo-express|swagger|kibana) ]] || [[ "$imagem" =~ (adminer|pgadmin|phpmyadmin|mailhog|mailpit|redis-commander|portainer|mongo-express) ]]; then
        printf '%s\n' "$sub" | awk -F'\t' '$1 ~ /\.profiles\[/ {f=1} END{exit !f}' || warn "$loc: ferramenta de debug/admin fora de 'profiles:' — sobe junto com tudo; isole em profile"
      fi
    fi
  done

  # ---- .env fora do git
  local dir; dir="$(dirname "$f")"
  if [ -f "$dir/.env" ]; then
    if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      if git -C "$dir" ls-files --error-unmatch .env >/dev/null 2>&1; then
        err "$nome: .env está VERSIONADO no git — segredo no histórico; remova do índice, rotacione o que vazou e ponha .env no .gitignore"
      elif ! git -C "$dir" check-ignore -q .env 2>/dev/null; then
        warn "$nome: .env existe e NÃO está no .gitignore — um 'git add .' o versiona"
      fi
    else
      grep -qE '^/?\.env$' "$dir/.gitignore" 2>/dev/null || warn "$nome: .env existe e o .gitignore não o lista"
    fi
  fi
  if printf '%s\n' "$flat" | awk -F'\t' '$1 ~ /env_file/ && $2 ~ /(^|\/)\.env(\.[a-z]+)?$/ {f=1} END{exit !f}' && [ ! -f "$dir/.env.example" ] && [ ! -f "$dir/env.example" ]; then
    warn "$nome: usa env_file/.env mas não há .env.example versionado documentando as chaves (sem valores)"
  fi
}

for f in "${arquivos[@]}"; do checar "$f" "${f#./}"; done

if [ "$strict" = 1 ]; then erros+=("${avisos[@]}"); avisos=(); fi
for a in "${avisos[@]:-}"; do [ -n "$a" ] && echo "  ! $a" >&2; done
if [ "${#erros[@]}" -gt 0 ]; then
  echo "✖ compose REPROVADO — ${#erros[@]} problema(s):" >&2
  for e in "${erros[@]}"; do echo "  · $e" >&2; done
  exit 1
fi
echo "✔ compose: ${#arquivos[@]} arquivo(s) verificado(s), piso cumprido."
