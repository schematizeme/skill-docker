#!/usr/bin/env bash
# schematize-docker — gate estático de Dockerfile (references/dockerfile.md, supply-chain.md).
#
# Lê o que está VERSIONADO (Dockerfile, Containerfile, *.Dockerfile e o .dockerignore ao lado) e
# cobra o piso da imagem. Não precisa do daemon Docker; usa o hadolint SE estiver instalado
# (opcional, nunca obrigatório: os achados dele entram como aviso).
#
# EXCEÇÃO DECLARADA de strict mode (`schematize-shell` -> `references/piso.md` seção 1): este script é
# um COLETOR — varre tudo e SOMA os achados. Com `set -e` abortaria no primeiro e esconderia o resto.
# Por isso `set -uo pipefail` sem `-e`.
#
# uso: check-dockerfile.sh [--strict] [--no-hadolint] [dir-ou-arquivo]
#   0 = passa · 1 = REPROVA · 2 = nada para verificar (e ausência de material não é aprovação)
#   --strict promove avisos a erros.
# Waiver rastreável: `# docker-ok: <motivo>` na linha da instrução ou na de cima (sem motivo não vale).
set -uo pipefail

strict=0; usar_hadolint=1; alvo=""
for a in "$@"; do
  case "$a" in
    --strict) strict=1 ;;
    --no-hadolint) usar_hadolint=0 ;;
    -*) echo "uso: check-dockerfile.sh [--strict] [--no-hadolint] [dir-ou-arquivo]" >&2; exit 2 ;;
    *) alvo="$a" ;;
  esac
done
alvo="${alvo:-.}"
erros=(); avisos=()

err()  { erros+=("$1"); }
warn() { avisos+=("$1"); }

# ------------------------------------------------------------------ descoberta
arquivos=()
if [ -f "$alvo" ]; then
  arquivos+=("$alvo")
else
  while IFS= read -r -d '' f; do arquivos+=("$f"); done < <(
    find "$alvo" -type f \( -name 'Dockerfile' -o -name 'Dockerfile.*' -o -name '*.Dockerfile' -o -name 'Containerfile' -o -name 'Containerfile.*' \) \
      -not -name '*.dockerignore' -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/versions/*' \
      -not -path '*/target/*' -print0 2>/dev/null
  )
fi
if [ "${#arquivos[@]}" -eq 0 ]; then
  echo "✖ nenhum Dockerfile/Containerfile em $alvo — nada para verificar (ausência de artefato não é conformidade)." >&2
  exit 2
fi

# ------------------------------------------------------------------ normalização
# Junta continuação (`\`), tira comentário de linha inteira e carrega heredoc de RUN como parte da
# instrução (o corpo é script e precisa ser lido). Saída: "<linha>\t<waiver 0|1>\t<INSTRUÇÃO> <args>".
normalizar() {
  awk '
    { raw[NR] = $0 }
    END {
      i = 1
      while (i <= NR) {
        l = raw[i]
        if (l ~ /^[[:space:]]*(#|$)/) { i++; continue }
        ini = i; txt = l
        while (txt ~ /\\[[:space:]]*$/ && i < NR) {
          sub(/\\[[:space:]]*$/, "", txt); i++
          nxt = raw[i]
          if (nxt ~ /^[[:space:]]*#/) { txt = txt " "; continue }
          txt = txt " " nxt
        }
        # heredoc: <<EOF, <<-EOF, <<"EOF", <<'"'"'EOF'"'"'
        if (match(txt, /<<-?["'"'"']?[A-Za-z_][A-Za-z0-9_]*["'"'"']?/)) {
          tag = substr(txt, RSTART, RLENGTH); gsub(/<<-?|["'"'"']/, "", tag)
          j = i + 1
          while (j <= NR && raw[j] !~ ("^[[:space:]]*" tag "[[:space:]]*$")) { txt = txt " ; " raw[j]; j++ }
          i = j
        }
        w = 0
        probe = raw[ini] " " ((ini > 1) ? raw[ini-1] : "")
        if (probe ~ /#[[:space:]]*docker-ok:[[:space:]]*[^[:space:]]+/) w = 1
        sub(/^[[:space:]]+/, "", txt)
        printf "%d\t%d\t%s\n", ini, w, txt
        i++
      }
    }' "$1"
}

secret_re='(PASSWORD|PASSWD|SECRET|TOKEN|API_?KEY|PRIVATE_?KEY|CREDENTIAL|ACCESS_?KEY|AUTH_?KEY)'

checar() {
  local f="$1" nome="$2"
  local -A args_default=() stage_names=()
  local n w linha instr resto
  local nstage=0 achou_user=0 user_final="" final_from_n=0 tem_hc=0 tem_syntax=0
  local copy_amplo_n=0 copy_estreito=0
  local primeiro_from=1

  head -3 "$f" | grep -qE '^#[[:space:]]*syntax[[:space:]]*=' && tem_syntax=1

  while IFS=$'\t' read -r n w linha; do
    instr="${linha%% *}"; resto="${linha#* }"
    [ "$instr" = "$linha" ] && resto=""
    instr="$(printf '%s' "$instr" | tr '[:lower:]' '[:upper:]')"
    local loc="$nome:$n"
    # achado(sev, msg): respeita o waiver da instrução
    achado() { if [ "$w" = 1 ]; then return; fi; if [ "$1" = e ]; then err "$loc: $2"; else warn "$loc: $2"; fi; }

    case "$instr" in
      ARG)
        if [ "$primeiro_from" = 1 ]; then
          local k="${resto%%=*}" v=""
          [[ "$resto" == *=* ]] && v="${resto#*=}"
          v="${v%\"}"; v="${v#\"}"
          args_default["$k"]="$v"
        fi
        local chave="${resto%%=*}"; chave="${chave%% *}"
        if [[ "$chave" =~ $secret_re ]] && [[ ! "$chave" =~ _FILE$ ]]; then
          achado e "ARG $chave carrega segredo — aparece no 'docker history'; use RUN --mount=type=secret"
        fi
        ;;
      FROM)
        primeiro_from=0
        nstage=$((nstage+1)); achou_user=0; user_final=""; final_from_n="$n"; tem_hc=0
        copy_estreito=0; copy_amplo_n=0
        local img as="" tok; local -a toks
        read -r -a toks <<< "$resto"
        img=""
        for tok in "${toks[@]}"; do
          case "$tok" in --*) continue ;; esac
          if [ -z "$img" ]; then img="$tok"; fi
        done
        for ((k=0; k<${#toks[@]}; k++)); do
          if [ "$(printf '%s' "${toks[$k]}" | tr '[:upper:]' '[:lower:]')" = "as" ]; then as="${toks[$((k+1))]:-}"; fi
        done
        # expande ${VAR}/$VAR com o default do ARG global
        local exp="$img" guarda=0
        while [[ "$exp" =~ \$\{?([A-Za-z_][A-Za-z0-9_]*)\}? ]] && [ "$guarda" -lt 5 ]; do
          local var="${BASH_REMATCH[1]}"
          if [ -n "${args_default[$var]+x}" ] && [ -n "${args_default[$var]}" ]; then
            exp="${exp//\$\{$var\}/${args_default[$var]}}"; exp="${exp//\$$var/${args_default[$var]}}"
          else break; fi
          guarda=$((guarda+1))
        done
        if [[ "$exp" == *'$'* ]]; then
          achado e "FROM $img: base não resolvível estaticamente — o default do ARG precisa trazer a imagem @sha256"
        elif [ "$exp" = scratch ] || [ -n "${stage_names[$exp]+x}" ]; then
          :
        else
          [[ "$exp" == *@sha256:* ]] || achado e "FROM $exp sem digest (@sha256:...) — tag é móvel; pine por digest"
          local semdig="${exp%%@*}" tag=""
          [[ "${semdig##*/}" == *:* ]] && tag="${semdig##*:}"
          if [ -z "$tag" ] && [[ "$exp" != *@sha256:* ]]; then achado e "FROM $exp sem tag — vira :latest"
          elif [ "$tag" = latest ]; then achado e "FROM $exp usa a tag móvel 'latest'"; fi
        fi
        [ -n "$as" ] && stage_names["$as"]=1
        ;;
      USER)
        achou_user=1; user_final="${resto%% *}"
        ;;
      HEALTHCHECK) tem_hc=1 ;;
      ENV)
        local -a pares; local ck; read -r -a pares <<< "$resto"
        local p
        if [[ "${pares[0]:-}" == *=* ]]; then
          for p in "${pares[@]}"; do
            [[ "$p" == *=* ]] || continue
            ck="${p%%=*}"
            if [[ "$ck" =~ $secret_re ]] && [[ ! "$ck" =~ _FILE$ ]]; then
              achado e "ENV $ck carrega segredo — persiste na camada e no 'docker inspect'; injete em runtime (cofre/secret)"
            fi
          done
        else
          ck="${pares[0]:-}"
          if [[ "$ck" =~ $secret_re ]] && [[ ! "$ck" =~ _FILE$ ]]; then
            achado e "ENV $ck carrega segredo — persiste na camada e no 'docker inspect'; injete em runtime (cofre/secret)"
          fi
        fi
        ;;
      ADD)
        local a1; a1="$(printf '%s' "$resto" | sed -E 's/--[a-z-]+(=[^ ]+)?[[:space:]]+//g' | awk '{print $1}')"
        if [[ "$a1" =~ ^(https?|ftp)://|^git@|^git\+ ]]; then
          achado e "ADD de origem remota ($a1) — sem verificação de integridade; use RUN curl -fsSLO + sha256sum -c, ou COPY --from"
        elif [[ ! "$a1" =~ \.(tar|tgz|tar\.gz|tar\.xz|tar\.bz2)$ ]]; then
          achado w "ADD de arquivo local — use COPY (ADD só para extrair tar local)"
        fi
        ;;
      COPY)
        if [[ "$resto" =~ (^|[[:space:]])(\./)?\.env([[:space:]]|$|\.) ]] || [[ "$resto" =~ (id_rsa|id_ed25519|\.pem|\.p12|\.pfx|\.key)([[:space:]]|$) ]]; then
          achado e "COPY de arquivo de segredo (.env/chave/certificado privado) para a imagem — monte em runtime ou use --mount=type=secret"
        fi
        if [[ "$resto" != *--from=* ]]; then
          local c1; c1="$(printf '%s' "$resto" | sed -E 's/--[a-z-]+(=[^ ]+)?[[:space:]]+//g' | awk '{print $1}')"
          if [ "$c1" = "." ] || [ "$c1" = "./" ]; then
            [ "$copy_estreito" = 0 ] && [ "$copy_amplo_n" = 0 ] && copy_amplo_n="$n"
          else copy_estreito=1; fi
        fi
        ;;
      ENTRYPOINT|CMD)
        [[ "$resto" == \[* ]] || achado w "$instr em forma shell — o processo vira filho de /bin/sh e não recebe SIGTERM; use a forma exec [\"bin\",\"arg\"]"
        ;;
      RUN)
        # copia amplo antes de RUN pesado => cache de camada perdido a cada mudança de código
        if [ "$copy_amplo_n" != 0 ] && [[ "$resto" =~ (install|build|compile|download|fetch) ]]; then
          achado w "'COPY . .' (linha $copy_amplo_n) antes de RUN de dependência/build — copie primeiro só o manifesto/lockfile (cache de camada)"
          copy_amplo_n=0
        fi
        if [[ "$resto" =~ (curl|wget)[^|\;]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh|ash|dash)([[:space:]]|$) ]] \
           || [[ "$resto" =~ (sh|bash)[[:space:]]+\<\([[:space:]]*(curl|wget) ]]; then
          achado e "curl|sh no build — executa código remoto sem verificação; baixe, confira sha256/assinatura, depois execute"
        fi
        if [[ "$resto" =~ chmod[[:space:]]+(-R[[:space:]]+)?(0?777|a\+rwx|ugo\+rwx) ]]; then
          achado e "chmod 777 — permissão mundial de escrita; dê só o necessário ao UID da aplicação"
        fi
        if [[ "$resto" =~ (^|[\;\&\|[:space:]])sudo[[:space:]] ]]; then achado w "sudo no build — o build já é root; no runtime o USER não-root não deve precisar de sudo"; fi
        if [[ "$resto" =~ apt(-get)?[[:space:]]+(-[a-zA-Z-]+[[:space:]]+)*(upgrade|dist-upgrade) ]]; then
          achado w "apt upgrade na imagem — builds deixam de ser reprodutíveis; atualize trocando o digest da base"
        fi
        if [[ "$resto" =~ apt(-get)?[[:space:]]+(-[a-zA-Z=-]+[[:space:]]+)*install ]]; then
          if [[ "$resto" != *"rm -rf /var/lib/apt/lists"* ]] && [[ "$resto" != *"--mount=type=cache"*"/var/lib/apt"* ]]; then
            achado e "apt-get install sem limpar /var/lib/apt/lists na MESMA camada — a imagem carrega o índice de pacotes"
          fi
          [[ "$resto" == *--no-install-recommends* ]] || achado w "apt-get install sem --no-install-recommends — puxa pacote que ninguém pediu"
          if ! [[ "$resto" =~ update ]]; then achado w "apt-get install sem 'apt-get update' na mesma camada — índice velho ou cache obsoleto"; fi
          local depois="${resto#*install}" t sem_pin=""
          for t in $depois; do
            case "$t" in
              -*|\&\&|\;|\|*|\\|"") continue ;;
              rm|apt*|cd|echo|true) break ;;
            esac
            [[ "$t" == *=* ]] || sem_pin="$sem_pin $t"
          done
          [ -n "$sem_pin" ] && achado w "apt-get install sem pin de versão (pacote=versão):$sem_pin"
        fi
        if [[ "$resto" =~ apk[[:space:]]+(-[a-zA-Z-]+[[:space:]]+)*add ]]; then
          [[ "$resto" == *--no-cache* ]] || achado e "apk add sem --no-cache — o índice fica na camada"
        fi
        ;;
    esac
  done < <(normalizar "$f")

  # --- cobranças do último estágio (a imagem que de fato roda)
  if [ "$nstage" -eq 0 ]; then
    err "$nome: nenhum FROM — não é um Dockerfile verificável"
    return
  fi
  if [ "$achou_user" = 0 ]; then
    err "$nome:$final_from_n: estágio final sem USER — o container roda como root por default"
  else
    case "$user_final" in
      root|root:*|0|0:*) err "$nome:$final_from_n: estágio final com USER $user_final — container não-root é o piso" ;;
      *) [[ "$user_final" =~ ^[0-9]+(:[0-9]+)?$ ]] || warn "$nome: USER $user_final por nome — prefira UID:GID numérico fixo (ex.: 10001:10001), estável entre imagens e com volume/securityContext" ;;
    esac
  fi
  [ "$tem_hc" = 1 ] || warn "$nome: sem HEALTHCHECK — ok se o orquestrador tem probes próprias (documente); para compose/standalone, declare"
  [ "$tem_syntax" = 1 ] || warn "$nome: sem '# syntax=docker/dockerfile:1' na primeira linha — heredoc, --link e --mount exigem o frontend recente"

  # --- .dockerignore ao lado
  local dir; dir="$(dirname "$f")"
  local di=""
  for c in "$f.dockerignore" "$dir/.dockerignore"; do [ -f "$c" ] && { di="$c"; break; }; done
  if [ -z "$di" ]; then
    err "$nome: sem .dockerignore — o contexto inteiro (.git, .env, node_modules) vai para o daemon e pode cair numa camada"
  else
    grep -qE '^[[:space:]]*(\*\*/)?\.env(\*|\.\*)?[[:space:]]*$' "$di" || err "$nome: .dockerignore não exclui .env — segredo local entra no contexto de build"
    grep -qE '^[[:space:]]*(\*\*/)?\.git/?[[:space:]]*$' "$di" || warn "$nome: .dockerignore não exclui .git"
  fi
}

for f in "${arquivos[@]}"; do
  nome="${f#./}"
  checar "$f" "$nome"
  # hadolint é opcional: se existir, soma os achados como AVISO (nunca é pré-requisito).
  if [ "$usar_hadolint" = 1 ] && command -v hadolint >/dev/null 2>&1; then
    while IFS= read -r l; do [ -n "$l" ] && warn "hadolint: $l"; done < <(hadolint --no-color --failure-threshold error "$f" 2>/dev/null)
  fi
done

# ------------------------------------------------------------------ veredito
if [ "$strict" = 1 ]; then erros+=("${avisos[@]}"); avisos=(); fi
for a in "${avisos[@]:-}"; do [ -n "$a" ] && echo "  ! $a" >&2; done
if [ "${#erros[@]}" -gt 0 ]; then
  echo "✖ Dockerfile REPROVADO — ${#erros[@]} problema(s):" >&2
  for e in "${erros[@]}"; do echo "  · $e" >&2; done
  exit 1
fi
echo "✔ Dockerfile: ${#arquivos[@]} arquivo(s) verificado(s), piso cumprido."
