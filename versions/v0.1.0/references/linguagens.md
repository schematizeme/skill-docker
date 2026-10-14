# Empacotamento por linguagem — base, conteúdo da imagem final e armadilhas

> Parte da skill **schematize-docker**. As regras gerais (multi-stage, digest, `USER` numérico,
> `.dockerignore`, BuildKit) estão em `dockerfile.md`; aqui está a aplicação **linguagem por
> linguagem**. Versões e digests das bases: `stack-versoes.md`; os exemplos completos vivem em
> `assets/dockerfiles/<lang>.Dockerfile`.
>
> **Fronteira.** A **linguagem em si** é da skill dela (`schematize-go`, `schematize-rust`,
> `schematize-elixir`, `schematize-csharp`, `schematize-ruby`, `schematize-node`,
> `schematize-python`). Aqui é **só o empacotamento**: de onde parte a imagem, o que vai nela e o
> que costuma dar errado. Os tamanhos são **ordem de grandeza** para calibrar suspeita (imagem 10x
> maior que o esperado quase sempre tem toolchain ou cache dentro), não meta de contrato.

Os tamanhos abaixo são da imagem **final comprimida** de um serviço HTTP pequeno.

---

## 1. Go — o caso fácil

- **Base de build:** `golang:<corrente>-alpine` (por digest). **Final:** `scratch` ou distroless
  `static` (`:nonroot`).
- **Estático:** `CGO_ENABLED=0`, `-trimpath`, `-ldflags="-s -w"` (e `-buildvcs` conforme o
  `supply-chain.md`). Um binário, sem libc.
- **Na imagem final:** o binário. Em `scratch` você precisa **trazer**:
  - **CA bundle** (`COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/`) — sem ele,
    toda chamada HTTPS sai com `x509: certificate signed by unknown authority`;
  - **tzdata** se a app usa `time.LoadLocation` (ou `import _ "time/tzdata"` no binário, que embute);
  - **`/etc/passwd`** se quer `USER` por nome — com UID numérico (`USER 10001:10001`) não precisa.
  O distroless `static` já traz CA, tzdata e o usuário `nonroot` (65532): é o padrão da casa.
- **Armadilha CGO:** `net` e `os/user` usam o resolvedor C (cgo) quando `CGO_ENABLED=1`, o que
  quebra em `scratch`. Com `CGO_ENABLED=0` o Go usa o resolvedor puro (`netgo`), que é o que se quer.
  Dependência que **exige** cgo (SQLite via `mattn/go-sqlite3`, alguns drivers) → prefira a variante
  pura-Go (`modernc.org/sqlite`) ou use base `cc`/glibc e documente.
- **Healthcheck:** modo `--healthcheck` no binário (`dockerfile.md` seção 5).
- **Tamanho:** ~5 a 25 MB. Exemplo: `assets/dockerfiles/go.Dockerfile`.

---

## 2. Rust — musl estático ou glibc enxuta

- **Build:** `rust:<corrente>-alpine` (musl, binário estático) **ou** `rust:<corrente>-slim` (glibc).
- **Final:**
  - musl estático → `scratch`/distroless `static`;
  - glibc dinâmico (muitas crates com `openssl` do sistema, `jemalloc`, NIFs) → distroless **`cc`**
    (traz libgcc/libstdc++ e glibc).
- **Armadilhas:**
  - **musl x glibc:** o **alocador do musl é lento** sob contenção; serviço com muita alocação
    concorrente roda sensivelmente melhor com `mimalloc`/`jemalloc` (via crate) em musl, ou
    em glibc. Meça antes de decidir.
  - **OpenSSL:** no musl estático prefira `rustls` (sem lib de sistema). Crate com `openssl-sys`
    exige a lib instalada e vira dor de cross-compile.
  - **CA bundle** em `scratch` (mesma regra do Go) ou use `rustls-native-certs`/`webpki-roots`
    embutido.
- **Cache de build:** compilar Rust do zero leva minutos. Use **`cargo-chef`** (estágio `planner`
  gera `recipe.json`; estágio `cacher` compila só as **dependências**; o código vem depois) ou
  `--mount=type=cache` em `~/.cargo/registry` e `target/`. A ordem é a do manifesto antes do código
  (`dockerfile.md` seção 7). Nunca `COPY . .` antes de `cargo chef cook`.
- **Strip:** `strip = true` / `lto` no `Cargo.toml` (perfil release); `-C strip=symbols`.
- **Tamanho:** ~5 a 30 MB. Exemplo: `assets/dockerfiles/rust.Dockerfile`.

---

## 3. Node — legado, só manutenção

`schematize-node` é skill de **manutenção de legado**; serviço novo não nasce em Node. Para o que já
existe:

- **Base:** `node:<LTS corrente>-alpine` (por digest), runtime = a mesma base. Imagem final
  **não** é a de build.
- **Instalação:** `npm ci --omit=dev` (lockfile obrigatório, sem devDependencies). **Nunca**
  `npm install` em imagem. `NODE_ENV=production` antes do `npm ci` (algumas libs mudam o
  comportamento).
- **Build + runtime separados:** estágio `build` instala tudo e compila (TypeScript, bundle); o
  final copia só `dist/` e as dependências de produção já instaladas.
- **Usuário:** a imagem oficial traz o usuário `node` (UID 1000) — use-o numérico (`USER 1000:1000`).
  Segredo de registry privado (`.npmrc` com token) por `--mount=type=secret`, **nunca** `COPY .npmrc`
  (o gate reprova `COPY` de arquivo de credencial).
- **Armadilhas:** PID 1 — `node` como PID 1 não trata SIGTERM sem handler explícito (`process.on`),
  e `npm start` cria um `sh` no meio: use `CMD ["node","dist/server.js"]` (exec) e `init: true`.
  Addon nativo (`node-gyp`) em Alpine exige `python3 make g++` no estágio de build e vira dor;
  `bcrypt`/`sharp` têm binário musl, confira. Gerenciador de runtime (`corepack`/`nvm`) não
  entra na imagem final.
- **Healthcheck:** `node healthcheck.js` (existe `node`, então o próprio runtime faz a sonda; não
  instale `curl` só para isso).
- **Tamanho:** ~120 a 250 MB. Exemplo: `assets/dockerfiles/node.Dockerfile`.

---

## 4. Elixir — `mix release`

- **Build:** `elixir:<corrente>-otp-<corrente>-alpine` (por digest) — ou a variante Debian/`slim`
  quando há NIF/dependência nativa.
- **Final:** o **release** (`mix release`) já empacota a BEAM; a imagem final é uma base mínima
  **do mesmo SO/libc** do build (Alpine → Alpine; Debian → `debian:<corrente>-slim`), com apenas as
  libs de sistema que o BEAM exige: `libstdc++`, `openssl`/`libssl`, `ncurses-libs`, `libgcc`.
  **Não** use a imagem `elixir` como final: leva Mix, Hex e o compilador.
- **Passos:** `MIX_ENV=prod mix deps.get --only prod`, `mix assets.deploy` (Phoenix),
  `mix release`; `COPY --from=build --chown=10001:10001 /app/_build/prod/rel/app ./`.
- **Armadilhas:**
  - **Locale/UTF-8:** `ENV LANG=C.UTF-8` — a BEAM avisa sem isso.
  - **musl x glibc:** NIF compilada em um e executada em outro quebra; build e final no mesmo libc.
  - **Clustering/epmd:** em container, `RELEASE_NODE`/`RELEASE_DISTRIBUTION` e cookie
    (**cookie é segredo**, por `secrets:`, nunca em `ENV` da imagem).
  - **`/tmp`** gravável em `read_only` (releases escrevem em `RELEASE_TMP`).
  - Migrations: comando `eval` do release (`bin/app eval "App.Release.migrate()"`) como job
    separado, não no `ENTRYPOINT`.
- **Tamanho:** ~50 a 120 MB. Exemplo: `assets/dockerfiles/elixir.Dockerfile`.

---

## 5. .NET — chiseled

- **Build:** `mcr.microsoft.com/dotnet/sdk:<LTS corrente>` (por digest). **Final:**
  `mcr.microsoft.com/dotnet/aspnet:<LTS corrente>-noble-chiseled` (ou `runtime-deps` se
  *self-contained*). **Chiseled** = Ubuntu "fatiada": sem shell, sem gerenciador de pacotes, usuário
  não-root pronto.
- **Publicação:** `dotnet publish -c Release -o /out --no-restore` (restore em camada própria,
  `*.csproj`/`NuGet.config` antes do código). Opcional: `PublishTrimmed=true` (corta assemblies
  não usados — **teste**: reflexão e serialização quebram em silêncio; `TrimmerRootAssembly`/
  `JsonSerializerContext` por source generator), `PublishReadyToRun=true` (startup), e
  `PublishAot` quando o perfil permite (serviço pequeno; sem reflexão dinâmica).
- **Usuário:** a imagem chiseled traz o usuário `app`; use **`USER $APP_UID`** (variável da imagem,
  número) — numérico, como pede o `dockerfile.md` seção 4.
- **Armadilhas:**
  - A imagem chiseled **não tem `curl` nem shell**: healthcheck é endpoint HTTP + sonda do
    orquestrador, ou um subcomando do próprio app; `ASPNETCORE_HTTP_PORTS=8080` (porta > 1024,
    pois não-root).
  - **ICU/globalização:** a chiseled padrão vem sem ICU; `InvariantGlobalization=true` se a app não
    precisa de cultura, ou use a variante `-extra`.
  - **Limites do cgroup:** o runtime respeita o limite de memória; ajuste `DOTNET_GCHeapHardLimitPercent`
    se necessário.
  - Chave de DataProtection e connection string: segredo por `secrets:`/cofre, não `ENV` da imagem.
- **Tamanho:** ~60 a 130 MB (aspnet chiseled) ou ~15 a 40 MB (AOT). Exemplo:
  `assets/dockerfiles/dotnet.Dockerfile`.

---

## 6. Ruby (Rails) — bundle em modo deployment

- **Base:** `ruby:<corrente>-slim` (por digest), em **dois estágios**: `build` (com
  `build-essential`, `libpq-dev`, `git`) e `final` (só as libs de runtime: `libpq5`, `libvips`,
  `libjemalloc2`). Alpine/musl é possível mas as gems nativas ficam frágeis: prefira Debian `slim`.
- **Passos (padrão Rails corrente, o `Dockerfile` gerado pelo `rails new` é um bom ponto de
  partida):**
  - `BUNDLE_DEPLOYMENT=1`, `BUNDLE_WITHOUT="development:test"`; `bundle install` com `Gemfile` e
    `Gemfile.lock` copiados **antes** do código; depois `rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache`;
  - **`bundle exec bootsnap precompile`** (gems e app) para startup;
  - **`SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile`** no build — o dummy é para o Rails
    não exigir `credentials` real durante o build (**a chave real nunca entra na imagem**;
    `RAILS_MASTER_KEY` vem por `secrets:`/cofre em runtime);
  - **jemalloc** (`LD_PRELOAD=libjemalloc.so.2` ou `MALLOC_ARENA_MAX=2`): reduz fragmentação e
    memória do Ruby de forma mensurável.
- **Usuário:** `rails` (UID/GID fixo `1000:1000` numérico) com `chown` só em `db`, `log`, `storage`,
  `tmp`. Com `read_only`, `tmp`/`log` em tmpfs ou volume.
- **Armadilhas:** `COPY . .` sem `.dockerignore` leva `config/master.key` e `.env` à imagem —
  `.dockerignore` obrigatório com `config/*.key`; migração (`db:prepare`) no `ENTRYPOINT` roda a cada
  réplica que sobe: faça como job separado ou com lock; `bin/rails server` como PID 1 sem `init`
  deixa zumbis de processos filhos.
- **Tamanho:** ~150 a 300 MB. Exemplo: `assets/dockerfiles/ruby.Dockerfile`.

---

## 7. Python — ferramenta, não serviço de produto

`schematize-python` define Python como **ferramenta** (dados/ML, automação, ferramental), nunca como
serviço de produto novo. A imagem existe para empacotar essa ferramenta de forma reprodutível:

- **Base:** `python:<corrente>-slim` (Debian, glibc, por digest) — **evite Alpine** para Python: as
  *wheels* binárias são glibc (`manylinux`); no musl tudo compila do zero (lento e frágil).
- **Gerenciador:** **`uv`** com `uv.lock` — instalação rápida e resolvida pelo lockfile
  (`uv sync --frozen --no-dev`); traga o `uv` por `COPY --from=ghcr.io/astral-sh/uv:<tag>@sha256:...`
  (não `pip install uv` solto). **Venv** em `/app/.venv` copiada do estágio de build para o final:
  `COPY --from=build /app/.venv /app/.venv` e `PATH="/app/.venv/bin:$PATH"`.
- **Variáveis:** `PYTHONUNBUFFERED=1` (log sem buffer), `PYTHONDONTWRITEBYTECODE=1` (rootfs
  somente leitura), `PIP_NO_CACHE_DIR=1` se usar `pip`.
- **Armadilhas:** dependência com extensão C sem wheel exige `gcc`/headers **no estágio de build
  apenas**; `pickle` e `torch` em imagem: o peso do ML (GB) é inevitável, mas separe o modelo (volume
  ou artefato versionado) da imagem; `pip install` direto de Git/URL sem hash: use
  `uv`/`pip --require-hashes`.
- **Tamanho:** ~60 a 150 MB (sem ML); ML pode passar de 1 GB. Exemplo:
  `assets/dockerfiles/python.Dockerfile`.

---

## 8. Tabela de decisão rápida

| Linguagem | Final | Estático? | Armadilha principal |
|---|---|---|---|
| Go | `scratch` / distroless `static` | sim (`CGO_ENABLED=0`) | CA bundle e tzdata em `scratch`; cgo |
| Rust | `scratch` (musl) / distroless `cc` | musl: sim | alocador do musl; openssl vs rustls; cache de build |
| Node (legado) | `node:*-alpine` | não | PID 1 / `npm start`; addon nativo; `.npmrc` |
| Elixir | base mínima do mesmo libc | não | libc igual ao build; locale; cookie do cluster |
| .NET | `aspnet` chiseled | não (AOT: quase) | sem shell/curl; ICU; trimming |
| Ruby | `ruby:*-slim` | não | `SECRET_KEY_BASE_DUMMY`, `master.key`, jemalloc |
| Python | `python:*-slim` | não | Alpine vs wheels; venv copiada |

---

## Regra de bolso

A linguagem escolhe a base, a base escolhe o que a imagem final precisa carregar. Estático
(Go/Rust musl): `scratch`/distroless — e lembre do CA bundle. Dinâmico: a base do **mesmo libc**
do build, nunca a imagem de build como final. Em qualquer uma: manifesto antes do código, usuário
numérico, nenhum segredo na camada — e o tamanho final é o termômetro: 10x o esperado significa
toolchain ou cache dentro.
