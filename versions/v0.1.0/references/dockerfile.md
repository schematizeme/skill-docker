# O Dockerfile da casa — a imagem como artefato mínimo, reprodutível e sem segredo

> Parte da skill **schematize-docker**. Este arquivo é o **piso da imagem**: o que o
> `scripts/check-dockerfile.sh` cobra e o que reprova o merge. Supply chain (assinatura, SBOM, scan,
> retenção) está em `supply-chain.md`; hardening em runtime, em `runtime.md`; compose, em
> `compose.md`; empacotamento por linguagem, em `linguagens.md`. Versões e digests: só em
> `stack-versoes.md`.
>
> **Por que esta skill existe:** a imagem é o artefato que vai para produção — e é onde moram os
> erros que nenhum teste de unidade vê: `latest` que muda sob os pés, processo rodando como root,
> `.env` dentro de uma camada, `curl | sh` sem verificação, 1 GB de toolchain no que deveria ter
> 15 MB. Dockerfile é código de produção.
>
> **Fronteira.** `schematize-infra` é dona do isolamento por serviço (user Linux + systemd), do
> deploy gated, da orquestração e do cofre de segredos. Esta skill é dona **da imagem** e da
> configuração do container. A base normativa é `schematize-engineering` (§28 archive, §35 DoD).

Convenção: **MUST** = regra que o gate cobra · **VETADO** = piso · `# docker-ok: <motivo>` =
waiver rastreável (sem motivo não vale).

---

## 1. Multi-stage — o toolchain não viaja para produção

Todo Dockerfile de aplicação tem **no mínimo dois estágios**: um que compila (com compilador,
cabeçalhos, gerenciador de pacotes) e um **final** que só contém o que roda.

```dockerfile
# syntax=docker/dockerfile:1
FROM golang:<corrente>-alpine@sha256:<digest> AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/app ./cmd/app

FROM gcr.io/distroless/static-debian<corrente>:nonroot@sha256:<digest>
COPY --from=build --chown=65532:65532 /out/app /app
USER 65532:65532
ENTRYPOINT ["/app"]
```

**MUST:** o estágio final **não** herda do estágio de build (`FROM build`). Herdar é copiar o
compilador, o cache e o código-fonte para produção. O que o final precisa vem por `COPY --from=`,
item a item.

Estágios nomeados (`AS build`, `AS deps`, `AS test`) permitem `docker build --target test` no CI sem
duplicar o arquivo. Estágio de **teste** nunca é o último: o que se publica é o último estágio.

---

## 2. A base — mínima por padrão, e a escolha se justifica

| Base | Quando | Preço |
|---|---|---|
| `scratch` | binário **estático** (Go com `CGO_ENABLED=0`, Rust musl) | sem shell, sem `/etc/passwd`, sem CA bundle, sem tzdata: você traz tudo que usa |
| **distroless** `static` | o mesmo, mas com CA bundle, tzdata e `/etc/passwd` com `nonroot` prontos | sem shell nem gerenciador de pacotes (é a vantagem e a dor do debug) |
| distroless `cc` / `base` | binário dinâmico com glibc (Rust gnu, .NET self-contained não aparado, Elixir release com NIF) | idem |
| **Chainguard** (`cgr.dev/chainguard/*`) | quando a casa quer base com CVE ~zero e rebuild diário | catálogo livre tem tags limitadas; a política de acesso é do registry <!-- reverificar --> |
| `-slim` (Debian) | precisa de glibc e de um shell para entrypoint/debug | maior; mais CVE de pacote não usado |
| `alpine` | build, ou runtime quando a linguagem é **musl-clean** | ver musl x glibc abaixo |

### musl x glibc — a armadilha de quem escolhe pelo tamanho

Alpine usa **musl**, não glibc. Consequências reais, não teóricas:

- **Resolvedor de DNS** diferente (musl não segue o mesmo `resolv.conf`/`search` de glibc em todos
  os casos): timeout intermitente em cluster com `ndots` alto aparece só em Alpine.
- **Alocador** do musl é mais lento sob contenção; runtime com muita alocação (Ruby, Python com
  extensões) pode perder desempenho e ganhar fragmentação.
- **Binário pré-compilado** (wheel Python, gem nativa, addon Node) frequentemente é só glibc: no
  Alpine vira compilação do zero (build lento) ou erro de carga.
- Um binário compilado em glibc **não roda** em Alpine/`scratch`; o inverso (musl estático) roda
  em qualquer lugar.

**Regra:** escolha a base pelo **runtime da linguagem** (ver `linguagens.md`), não pelo tamanho no
`docker images`. Estático puro: `scratch`/distroless `static`. Dinâmico: a base da glibc.

Imagem final **nunca** é `ubuntu`/`debian` completa "porque é familiar".

---

## 3. Pin por digest — e o digest apodrece

**MUST:** todo `FROM` referencia a base **por digest** (`FROM image:tag@sha256:...`). Tag é ponteiro
móvel: `alpine:3.23` hoje e amanhã são imagens diferentes; build que "funcionava ontem" é o sintoma.
`latest`, ou a ausência de tag, é **VETADO** (o gate reprova `FROM` sem digest e `latest`).

Mantenha a **tag legível junto do digest** — o digest sozinho é ilegível, a tag sozinha é mutável:

```dockerfile
FROM alpine:<tag>@sha256:<digest>
```

**O digest apodrece.** Digest fixo congela também os patches de segurança da base: seis meses
depois você tem uma imagem reprodutível **e vulnerável**. Pin sem automação é dívida. O par é
sempre:

1. **Renovate** ou **Dependabot** abrindo PR de atualização de digest (versão e digest juntos), com
   o CI (build + scan) rodando no PR;
2. **rebuild periódico** (semanal) da imagem para absorver patch mesmo sem mudança de código
   (`supply-chain.md` seção 8).

```json
{ "extends": ["config:best-practices"], "dockerfile": { "enabled": true },
  "pinDigests": true }
```

Digests usados nos exemplos desta skill vivem em `stack-versoes.md` (anexo volátil, com data de
verificação).

---

## 4. Usuário não-root — UID:GID **numérico** e fixo

**MUST:** a imagem final declara `USER` com **UID:GID numérico**, não-zero. `USER root` explícito
no estágio final, ou ausência de `USER`, é reprovado pelo gate.

```dockerfile
USER 10001:10001          # certo: numérico, fixo, documentado
USER app                  # frágil: depende de /etc/passwd existir na imagem final
```

Por que **numérico e fixo**:

- **`runAsNonRoot: true` do Kubernetes só aceita UID numérico** — com `USER app` o kubelet não
  consegue verificar que não é 0 e recusa o pod (`container has runAsNonRoot and image has
  non-numeric user`).
- **Volumes:** o dono dos arquivos num volume nomeado/bind é um número. UID que muda entre builds
  (ou entre bases) faz o volume existente virar ilegível. Fixar o UID é fixar o contrato com o dado.
- **`scratch` não tem `/etc/passwd`:** nome não resolve; número funciona sem nada.
- **Mapeamento com user namespaces** (`runtime.md`) opera em números.

Crie o usuário no estágio final só se a base não trouxer (distroless `nonroot` traz o 65532):

```dockerfile
RUN addgroup -g 10001 -S app && adduser -u 10001 -S -G app -H -s /sbin/nologin app
```

`COPY --chown=10001:10001` para os arquivos que a aplicação precisa **escrever**; o resto fica
`root:root` somente leitura — a aplicação não deve poder reescrever o próprio binário.

**VETADO:** `sudo` na imagem, `chmod 777` / `chmod -R 777` (reprovado pelo gate), `setuid` que não
seja da base. Se o processo precisa de privilégio, o desenho está errado (porta < 1024? use porta
alta e deixe o mapeamento para o runtime; a capability `NET_BIND_SERVICE` é último recurso).

---

## 5. HEALTHCHECK x probes — são coisas diferentes

- **`HEALTHCHECK`** é recurso do **Docker, compose e swarm**: o daemon executa o comando
  periodicamente e marca o container `healthy`/`unhealthy`. É o que `depends_on:
  condition: service_healthy` e `docker compose up --wait` consomem.
- **Kubernetes ignora o `HEALTHCHECK` da imagem.** Lá existem **probes** no manifesto:
  `startupProbe` (a app ainda está subindo — protege liveness), `livenessProbe` (travou? reinicia)
  e `readinessProbe` (recebe tráfego?).
- **liveness != readiness.** Readiness cai quando a dependência (banco) cai — **tira do balanceador,
  não reinicia**. Liveness que checa o banco faz o cluster inteiro reiniciar em cascata quando o
  banco tem um soluço. Liveness checa só "o processo está vivo e não travado".
- A podman respeita `HEALTHCHECK` apenas com formato de imagem Docker (não OCI puro)
  <!-- reverificar -->.

**MUST:** imagem de serviço (que escuta porta) declara `HEALTHCHECK` — o gate de compose cobra
healthcheck no serviço — **ou** o compose o declara. Os endpoints (`/healthz` liveness,
`/readyz` readiness) pertencem à aplicação; a skill da linguagem os desenha.

### Healthcheck em imagem sem shell nem curl

Em distroless/`scratch` não existe `curl`, `wget` nem `sh` — `HEALTHCHECK CMD curl ...` falha
sempre. A solução da casa: o **próprio binário** tem um modo de sonda.

```dockerfile
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3 \
  CMD ["/app", "--healthcheck"]
```

`/app --healthcheck` faz GET em `127.0.0.1:$PORT/healthz`, sai `0` ou `1`, e **não** sobe o
servidor. Forma exec (array JSON) obrigatória: sem shell, `CMD curl ...` em shell-form quebra.

---

## 6. `.dockerignore` — é segurança, não só velocidade

`COPY . .` copia **o contexto inteiro** para uma camada. Sem `.dockerignore`, o `.env`, a chave
privada, o `.git` (com histórico de segredos já removidos), o `node_modules` do host e o
`target/` entram na imagem. Camada é permanente: apagar o arquivo numa `RUN` depois **não** o
remove da camada anterior, e `docker history`/`docker save` o entrega.

**MUST:** todo Dockerfile tem `.dockerignore` ao lado (o gate reprova a ausência e `COPY` de `.env`
ou chave). Base mínima:

```
.git
.gitignore
.env
.env.*
!.env.example
*.pem
*.key
id_*
**/node_modules
**/target
**/__pycache__
.schematize
*_archive
Dockerfile*
compose*.y*ml
*.md
```

Estratégia **allowlist** (`*` e depois `!src`, `!go.mod`...) é mais segura que blocklist para
projeto com muitos artefatos: nada entra por esquecimento. O `*_archive` (convenção da casa,
`schematize-engineering` §28) **nunca** entra em imagem.

---

## 7. Cache de camadas e BuildKit

### Ordem das camadas

O cache invalida da primeira camada alterada para baixo. Logo: **o que muda pouco vai primeiro**.

```dockerfile
COPY go.mod go.sum ./     # manifesto e lockfile: mudam raramente
RUN go mod download       # camada cacheada enquanto o manifesto não mudar
COPY . .                  # código: muda a cada commit
RUN go build ...
```

`COPY . .` antes de instalar dependência refaz o download a cada alteração de uma linha.

### BuildKit (padrão no Docker Engine corrente)

Primeira linha do arquivo: `# syntax=docker/dockerfile:1` — habilita o frontend corrente
independentemente do daemon.

```dockerfile
# cache persistente de gerenciador de pacotes: fora da imagem, entre builds
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends ca-certificates

# SEGREDO de build: montado em tmpfs, NÃO entra em camada nem em docker history
RUN --mount=type=secret,id=npm_token,target=/run/secrets/npm_token \
    NPM_TOKEN="$(cat /run/secrets/npm_token)" npm ci --omit=dev

# chave SSH para dependência privada: o agent é encaminhado, a chave não é gravada
RUN --mount=type=ssh git clone git@github.com:org/priv.git /src/priv
```

```bash
docker buildx build --secret id=npm_token,src=$HOME/.npmrc-token \
                    --ssh default -t app:dev .
```

**VETADO — segredo em `ARG`, `ENV` ou camada.** `ARG` e `ENV` ficam gravados nos metadados da imagem
(`docker history`, `docker inspect`) e nas camadas; mesmo um `ARG` "só no build" vaza. O gate
reprova nome de variável com `TOKEN`/`SECRET`/`PASSWORD`/`KEY` em `ARG`/`ENV`. Segredo de build só por
`--mount=type=secret`; segredo de runtime só pelo cofre (`schematize-infra -> references/segredos.md`),
nunca na imagem.

### Outros recursos que valem o uso

- **Heredocs** no `RUN`/`COPY` (`RUN <<EOF ... EOF`): script de várias linhas sem `&& \` encadeado
  e sem arquivo auxiliar. Para script não trivial, o piso é o do `schematize-shell -> references/piso.md`
  (`set -eux` na primeira linha do heredoc).
- **`COPY --link`**: a camada é independente das anteriores; trocar a base não invalida o `COPY`.
  Ganho de cache em reconstrução; use no estágio final.
- **`--mount=type=bind`** para fonte read-only em estágio de build sem criar camada.
- **Cache entre CI runs**: `--cache-from`/`--cache-to` (`type=gha` ou `type=registry`); ver
  `assets/ci/github-actions-docker.yml`.

---

## 8. `ENTRYPOINT`/`CMD`, PID 1 e sinais

**MUST:** `ENTRYPOINT` e `CMD` em **exec form** (array JSON). O gate reprova `CMD` em shell-form.

```dockerfile
ENTRYPOINT ["/app"]          # exec: o app é o PID 1 e recebe SIGTERM
CMD ["serve"]                # argumentos padrão, substituíveis
# ERRADO:  CMD /app serve    # vira /bin/sh -c "...": o sh é o PID 1 e NÃO repassa sinal
```

Por quê: `docker stop` envia **SIGTERM** ao PID 1 e, após o prazo (10 s por padrão), **SIGKILL**. Em
shell-form o PID 1 é o `sh`, que não repassa o sinal: o app é morto à força, conexões cortadas,
transação aberta, sem *graceful shutdown*.

Além disso:

- **PID 1 tem semântica especial** no Linux: não tem handler padrão de sinal (SIGTERM é ignorado se
  o processo não instalou handler) e deve fazer *reap* de órfãos. App que não faz isso deixa
  **zumbis** (processo que spawna filhos: headless browser, `git`, `ffmpeg`). Solução: `--init` no
  `docker run`, `init: true` no compose, ou `tini` como `ENTRYPOINT ["/sbin/tini","--","/app"]`.
- `STOPSIGNAL` quando a app espera outro sinal (ex.: SIGQUIT para parada graciosa em alguns
  servidores). Declare `STOPSIGNAL SIGTERM` explícito só quando difere do padrão.
- O prazo de parada se ajusta no runtime (`--stop-timeout`, `stop_grace_period`; `runtime.md`).
- **Um processo por container.** Supervisor (`supervisord`, `s6` com N serviços) dentro da imagem é
  VETADO: perde-se restart por unidade, log por serviço e healthcheck honesto. Dois processos =
  dois containers (ou um sidecar).

---

## 9. Higiene de `apt` e `apk`

Debian/Ubuntu: instalar, limpar **na mesma camada** (limpar em outra `RUN` não encolhe nada), sem
recomendados, com pacotes pinados.

```dockerfile
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates=<versao-pinada> tzdata=<versao-pinada> \
 && rm -rf /var/lib/apt/lists/*
```

Alpine: `apk add --no-cache pacote=~<versao>` (o `--no-cache` dispensa o `rm` do índice).

**MUST (gate):** `apt-get install` sem `--no-install-recommends`, sem limpeza de
`/var/lib/apt/lists` na mesma `RUN`, ou sem pin é reprovado. `apt-get update` **sozinho** numa
`RUN` própria é o clássico bug de cache velho — sempre encadeado ao `install`.

Pin de pacote tem o mesmo problema do digest: a versão sai do repositório e o build quebra. Pine
quando a reprodutibilidade importa (imagem final) e renove por automação; no estágio de build
descartável o rigor é menor, mas o gate ainda avisa.

---

## 10. `ADD` x `COPY`, e `curl | sh`

- **`COPY`** por padrão. `ADD` só para extrair um `.tar` local (`ADD app.tar.gz /opt/`).
- **`ADD <url>` é VETADO** (o gate reprova): baixa sem verificação de integridade e sem cache
  determinístico. (`ADD --checksum=sha256:... <url>` existe no BuildKit; se usar, é a única forma
  aceitável e vem com `# docker-ok:` explicando por que não `curl` verificado.)
- **`curl ... | sh` / `curl | bash` é VETADO** (o gate reprova): executa o que o servidor entregar
  *naquele instante*, sem verificar nada. A alternativa é **baixar, verificar e só então usar**:

```dockerfile
ARG TOOL_VERSION=<versao>
ARG TOOL_SHA256=<sha256-publicado-pelo-autor>
RUN curl -fsSLo /tmp/tool.tgz "https://example.org/tool-${TOOL_VERSION}-linux-amd64.tgz" \
 && echo "${TOOL_SHA256}  /tmp/tool.tgz" | sha256sum -c - \
 && tar -xzf /tmp/tool.tgz -C /usr/local/bin tool \
 && rm /tmp/tool.tgz
```

Melhor ainda: `COPY --from=<imagem-oficial-pinada-por-digest> /bin/tool /usr/local/bin/tool` — a
imagem do projeto já é verificável e assinada. O sha256 fica fixo no repositório e muda junto da
versão (por PR, com revisão).

---

## 11. `LABEL` OCI — a imagem diz de onde veio

Toda imagem publicada carrega as anotações padrão, para que quem a encontra num registry volte ao
commit exato:

```dockerfile
ARG REVISION=unknown
ARG VERSION=dev
LABEL org.opencontainers.image.source="https://github.com/<org>/<repo>" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.licenses="<SPDX>"
```

`ARG` para revisão/versão **não é segredo** (é metadado público) — o gate só reprova `ARG` com
nome de segredo. No CI, `docker/metadata-action` preenche tudo isso (`assets/ci/github-actions-docker.yml`).
A `revision` é o sha do git — o mesmo da tag imutável (`supply-chain.md` seção 7).

---

## 12. Lista de verificação do Dockerfile

- [ ] `# syntax=docker/dockerfile:1`; multi-stage; final sem toolchain.
- [ ] Todo `FROM` com tag legível **e** digest; nada de `latest`; automação de renovação ativa.
- [ ] `USER` numérico (UID:GID) no final; sem `sudo`, sem `chmod 777`.
- [ ] `.dockerignore` presente e com `.env`/chaves/`.git`/`*_archive`.
- [ ] Manifesto/lockfile antes do código; `--mount=type=cache` onde há gerenciador de pacotes.
- [ ] Zero segredo em `ARG`/`ENV`/camada; `--mount=type=secret` para o de build.
- [ ] `ENTRYPOINT`/`CMD` em exec form; `init`/`tini` se há processos filhos; um processo por container.
- [ ] `apt`: `--no-install-recommends` + limpeza na mesma camada; `curl` verificado por sha256.
- [ ] `HEALTHCHECK` (ou equivalente no compose) em exec form, sem depender de `curl` em imagem sem shell.
- [ ] `LABEL` OCI com `source`/`revision`/`version`.
- [ ] `scripts/check-dockerfile.sh` verde (e `hadolint` se instalado).

---

## Regra de bolso

A imagem final é **um binário, um usuário numérico, um processo, nenhum segredo e nenhuma
ferramenta que o atacante queira**. Base fixada por digest e renovada por robô; qualquer coisa que
chegue pela rede entra com `sha256sum -c`; qualquer coisa secreta entra por `--mount=type=secret`
ou não entra.
