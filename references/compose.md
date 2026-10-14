# Compose da casa — dev e hml, não produção

> Parte da skill **schematize-docker**. O `Dockerfile` está em `dockerfile.md`; os controles de
> runtime que o compose aplica, em `runtime.md`; a procedência da imagem, em `supply-chain.md`.
> Aqui fica o **arquivo `compose.yaml`**: como o ambiente de dev e de hml sobe de forma
> reprodutível e sem expor o que não deve.
>
> **Por que esta skill existe:** o compose é onde o banco vira `0.0.0.0:5432`, a senha vira
> `POSTGRES_PASSWORD: admin` commitada, o `depends_on` promete uma ordem que não existe e um
> `down -v` apaga o dado de hml numa sexta à tarde.
>
> **Fronteira (importante).** Compose é ferramenta de **dev e hml**. A **produção da casa** é o
> `<projeto>_ops` sobre systemd/container, decisão de `schematize-infra` (isolamento por serviço,
> deploy gated, segredos em cofre). Isso não é preconceito contra compose: é que prd exige
> user Linux por serviço, rollback por digest e gate de deploy, que um `docker compose up` na
> mão não dá. Se um projeto específico decidir compose em prd, é ADR com a infra, e o piso daqui vale
> **por inteiro**.
>
> O gate `scripts/check-compose.sh` cobre: `privileged`, `docker.sock`, banco publicado fora de
> loopback, segredo literal em `environment`, `depends_on` sem `condition`, `healthcheck` ausente,
> `latest`, falta de hardening, `.env` versionado. Exemplo completo: `assets/compose/compose.yaml`.

Convenção: **MUST** = piso · **VETADO** = reprova · `# docker-ok:` = waiver rastreável.

---

## 1. O arquivo

- Nome: **`compose.yaml`** (o preferido pela especificação; `docker-compose.yml` ainda é lido, mas
  é legado). Um por projeto, na raiz do repo (ou em `<projeto>_ops/`).
- **Sem a chave `version:`** — obsoleta; o compose a ignora e avisa. Quem a deixa mostra que copiou
  de um tutorial antigo.
- A CLI é o plugin **`docker compose`** (com espaço), não o `docker-compose` (hífen) legado
  em Python. Scripts e docs da casa usam a forma com espaço.
- **Imagem de terceiros por digest** (`postgres:<tag>@sha256:...`), como no Dockerfile
  (`dockerfile.md` seção 3); `latest` é reprovado pelo gate. Imagem própria: tag `sha-` ou digest
  (`supply-chain.md` seção 6).

```yaml
name: meuprojeto            # nome do projeto (prefixo dos recursos); ver seção 9
services:
  db: { ... }
  api: { ... }
```

---

## 2. Dependência: `healthcheck` + `condition`

`depends_on` **sem condição** só garante a ordem de *início* dos containers, não que o banco
aceita conexão. A API sobe, o banco ainda está iniciando, a API falha ou, pior, "funciona" com
retry escondido.

```yaml
services:
  db:
    image: postgres:<tag>@sha256:<digest>
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 5s
      timeout: 3s
      retries: 10
      start_period: 10s
  api:
    depends_on:
      db:
        condition: service_healthy
```

- **MUST:** `depends_on` na forma longa, **com `condition`** (o gate reprova a forma curta de lista).
- `service_healthy` quando a dependência tem `healthcheck`. `service_started` **só** quando não há
  como declarar saúde (e escreva o porquê). `service_completed_successfully` para job de
  inicialização (migração) que precisa terminar antes.
- `$$` escapa o `$` para o compose não interpolar antes da hora (a variável é do container).
- **MUST:** todo serviço de longa vida tem `healthcheck` (gate). Em imagem sem shell, o modo
  `--healthcheck` do binário (`dockerfile.md` seção 5).
- `docker compose up --wait` (e `--wait-timeout`) sobe e **bloqueia até healthy**: é o comando do
  CI e do script de smoke — o fim do `sleep 10` no meio do pipeline.

---

## 3. Profiles — o que sobe quando

`profiles:` marca serviços opcionais; só sobem se o profile for ativado. Mantém o `up` padrão
enxuto e dá lugar às ferramentas de apoio sem poluir o ambiente.

```yaml
services:
  api: { ... }                         # sempre
  adminer:
    image: adminer@sha256:<digest>
    profiles: [debug]
    ports: ["127.0.0.1:8081:8080"]     # só loopback
  seed:
    profiles: [seed]
```

```bash
docker compose up -d --wait                   # api + db
docker compose --profile debug up -d          # + adminer em 127.0.0.1
docker compose --profile seed run --rm seed
```

---

## 4. Redes — o banco não conversa com o mundo

```yaml
networks:
  frontend: {}
  backend:
    internal: true          # sem rota para fora do host

services:
  api: { networks: [frontend, backend] }
  db:  { networks: [backend] }     # só a rede interna
```

- `internal: true` corta a saída para a internet e a entrada de fora: o banco só é alcançado
  pelos serviços que estão na mesma rede.
- **VETADO: banco/cache publicado em `0.0.0.0`** (o gate reprova `ports:` de Postgres, MySQL,
  Redis, Mongo etc. fora de loopback). Publicar `5432:5432` equivale a `0.0.0.0:5432` e o Docker
  contorna o firewall do host (`runtime.md` seção 6).
- Acesso humano ao banco:
  - **`docker compose exec db psql -U app app`** — o caminho padrão, sem publicar porta;
  - **profile `debug`** com `ports: ["127.0.0.1:5432:5432"]` — loopback, só quando ativado;
  - de outra máquina: túnel SSH, nunca porta aberta.
- Porta de serviço de aplicação para o host: sempre explícita sobre o IP (`127.0.0.1:8080:8080`)
  em dev; atrás de proxy em hml.

---

## 5. Volumes — nomeado para dado, bind para código

| Tipo | Uso | Cuidado |
|---|---|---|
| **Volume nomeado** (`pgdata:`) | **dado** persistente (banco, uploads) | gerenciado pelo Docker; sobrevive ao `down`; é destruído por `down -v` |
| **Bind mount** (`./src:/app/src`) | código em dev (hot reload), config read-only | acopla o container ao caminho e às permissões do host; em hml é VETADO para dado |

```yaml
services:
  db:
    volumes:
      - pgdata:/var/lib/postgresql/data      # nomeado
  api:
    volumes:
      - ./config/app.toml:/etc/app/app.toml:ro   # config: sempre :ro
volumes:
  pgdata: {}
```

Bind mount de dado em dev dá problema de **dono** (UID do container x UID do host): o UID numérico
fixo da imagem (`dockerfile.md` seção 4) torna isso previsível — `chown` do diretório para o UID da
imagem, em vez de `chmod 777`. Em SELinux, `:z`/`:Z` no mount.

---

## 6. Variáveis e segredos

### `.env` fora do git

- **MUST:** `.env` no `.gitignore` e no `.dockerignore`. O gate reprova `.env` versionado.
- `.env` ou segredo que já entrou no git: tratar como vazado (revogar e rotacionar) — `schematize-git → references/segredos.md`.
- Versione **`.env.example`** com chaves e valores **fictícios ou vazios**, e a documentação do que
  cada uma faz. Quem clona copia `cp .env.example .env` e preenche.
- O compose lê `.env` do diretório do projeto **para interpolação** (`${VAR}` no YAML). Isso não
  passa a variável ao container: para isso, `environment:` ou `env_file:`.
- **`docker compose config` imprime o arquivo com TUDO interpolado — inclusive os segredos do
  `.env`.** É ótimo para validar, e é a fonte de vazamento clássica ao colar a saída num chat,
  issue ou log de CI. Cole só depois de revisar; no CI, não imprima `config` em log público.

### Segredo literal em `environment` é VETADO

```yaml
# ERRADO (o gate reprova): a senha fica no YAML versionado e em `docker inspect`
environment:
  POSTGRES_PASSWORD: admin
```

Use **`secrets:`** — o valor chega ao container como arquivo em `/run/secrets/<nome>`, não em
variável de ambiente (variável aparece em `docker inspect`, em `/proc/<pid>/environ`, em crash dump
e herdada por todo processo filho):

```yaml
services:
  db:
    image: postgres:<tag>@sha256:<digest>
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password   # a imagem lê do arquivo
    secrets: [db_password]
secrets:
  db_password:
    file: ./secrets/db_password.txt      # arquivo fora do git (.gitignore)
  # ou, a partir de variável do shell do host:
  # api_key:
  #   environment: API_KEY
```

- A imagem precisa ler o segredo de arquivo (`*_FILE` nas imagens oficiais de banco; a aplicação
  da casa lê caminho de arquivo — padrão que vale também para o cofre em prd, `schematize-infra ->
  references/segredos.md`).
- `env_file:` serve para configuração **não secreta** (URLs, flags); não é cofre.
- Interpolação com obrigatoriedade: `${DB_PASSWORD:?defina DB_PASSWORD}` aborta o `up` se faltar,
  em vez de subir com string vazia.

---

## 7. Reuso: override, `extends`, âncoras

- **Arquivos de override**: `compose.yaml` (base) + `compose.override.yaml` (carregado
  automaticamente: dev) ou `-f compose.yaml -f compose.hml.yaml` explícito para hml. Os arquivos
  são **mesclados** (listas somam, mapas se fundem). Dev e hml são arquivos distintos; hml não herda
  o hot reload do dev.
- **`extends`**: reaproveita a definição de um serviço de outro arquivo; bom para N workers com a
  mesma base. Limite: não herda `depends_on`, `volumes_from`, `links`.
- **Âncoras YAML** (`x-comum: &comum`, `<<: *comum`) para blocos repetidos (hardening, logging):

```yaml
x-hardening: &hardening
  read_only: true
  cap_drop: [ALL]
  security_opt: ["no-new-privileges:true"]
  logging: { driver: json-file, options: { max-size: "10m", max-file: "5" } }

services:
  api:
    <<: *hardening
    image: ...
```

- **O gate `check-compose.sh` NÃO resolve a mescla `<<:`** (nem o merge de múltiplos arquivos): ele
  lê o texto. Hardening vindo de âncora pode ser lido como ausente, ou o inverso. Por isso, a
  verdade é **`docker compose config`** (que expande âncoras, merge e interpolação): valide o
  resultado com ele (`docker compose -f ... config -q` no CI falha em erro de sintaxe) e, para o
  que o gate não enxerga, declare o hardening **explícito no serviço** ou use `# docker-ok:` com
  o motivo apontando para a âncora.

---

## 8. Desenvolvimento: `watch`, `build` e cache

- **`docker compose watch`** (ou `up --watch`): observa o contexto e, conforme a regra em
  `develop.watch`, faz `sync` (copia o arquivo para o container), `rebuild` (reconstrói) ou
  `sync+restart`. Substitui o bind mount de código com menos atrito de permissão e funciona com
  imagem final enxuta.

```yaml
services:
  api:
    build: .
    develop:
      watch:
        - { action: sync,    path: ./src,         target: /app/src }
        - { action: rebuild, path: ./package.json }
```

- `docker compose up --build` reconstrói antes de subir; o **cache de camadas** do BuildKit evita o
  custo (`dockerfile.md` seção 7). `--no-cache` só quando o cache é a suspeita.
- `build:` no compose: `context`, `dockerfile`, `target` (use `target: dev` em dev com ferramentas
  de debug, e o final em hml), `args` (nunca segredo), `secrets` (de build) e `cache_from`.
- Em hml a imagem vem de `image:` (digest do CI), **não** de `build:` — o que roda em hml é o
  artefato que foi testado, não um build local.

---

## 9. Nome do projeto e limpeza

- **`-p` / `name:`**: o nome do projeto prefixa containers, redes e volumes
  (`meuprojeto-db-1`, `meuprojeto_pgdata`). Dois checkouts com o mesmo nome de diretório colidem:
  fixe `name:` no arquivo ou use `-p` (e `COMPOSE_PROJECT_NAME`) para ambientes paralelos.
- `docker compose down` remove containers e redes; **mantém** volumes nomeados.
- **`docker compose down -v` DESTRÓI os volumes — o dado.** Em dev é a forma de resetar; **em hml
  com dado, nunca**. O script de reset pede confirmação explícita, imprime os volumes que serão
  apagados e recusa rodar se o ambiente é hml (variável de ambiente `AMBIENTE`). Backup antes de
  qualquer operação destrutiva (`schematize-infra -> references/resiliencia.md`).
- `docker compose down --remove-orphans` limpa serviço removido do arquivo; `docker compose
  ps`/`logs -f --tail=100` para inspecionar; `docker system prune` **não** é rotina — pergunte
  antes (`--volumes` apaga volume órfão com dado).

---

## 10. Checklist do compose

- [ ] `compose.yaml` sem `version:`; `name:` fixo.
- [ ] Imagens por digest (terceiros) ou `sha-`/digest (próprias); sem `latest`.
- [ ] `healthcheck` em todo serviço de longa vida; `depends_on` longo com `condition`.
- [ ] Banco em rede `internal`; nenhuma porta de dados fora de `127.0.0.1`.
- [ ] Dado em volume **nomeado**; bind só para código/config `:ro`.
- [ ] Segredos por `secrets:` (`*_FILE`); `.env` no `.gitignore`; `.env.example` versionado.
- [ ] Hardening explícito (`cap_drop`, `no-new-privileges`, `read_only`, limites) ou `docker-ok` com motivo.
- [ ] `docker compose config -q` verde; `scripts/check-compose.sh` verde.
- [ ] Sem `privileged`, sem `docker.sock`.

---

## Regra de bolso

Compose é o **ensaio**, não o palco: sobe o ambiente de dev/hml com saúde declarada, rede interna
para o dado, segredo em arquivo e nenhuma porta de banco no mundo. O que o gate não consegue ler
(âncoras, merge) o `docker compose config` mostra — e o `config` imprime segredo, então não cole.
`down -v` apaga dado: só onde o dado é descartável.
