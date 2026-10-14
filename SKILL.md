---
name: schematize-docker
metadata:
  version: 0.1.0
description: >-
  Docker/OCI de ponta a ponta: Dockerfile multi-stage por digest e não-root, BuildKit, compose de dev, buildx, SBOM e provenance, cosign, scan, runtime hardening, registry. Use ao tocar Dockerfile, compose.yaml, imagem, container, buildx ou registry. Traz gates estáticos e CI.
---
<!-- cross-skill: isolamento.md, entrega.md, segredos.md, resiliencia.md, iac.md -> schematize-infra -->
<!-- cross-skill: efeitos-externos.md, ops.md -> schematize-engineering -->

# Docker/OCI da casa (schematize-docker)

Disciplina normativa para **a imagem e o container**. A tese é curta: **a imagem é o artefato que
vai para produção — então ela é reproduzível, mínima, não-root, sem segredo, assinada, e o
container que a executa começa sem privilégio nenhum**. Um Dockerfile é código de produção: ele
decide o que roda como root, o que fica gravado em camada para sempre e qual CVE você entrega.

**Versão:** skill `schematize-docker` v0.1.0. Changelog em `CHANGELOG.md`.

## Precedência e herança (leia antes de divergir)

<!-- herdado:engineering/precedencia:foraRol intro="Esta skill é a especialista do **artefato OCI** e do **runtime de container**: Dockerfile, imagem, compose de dev/hml, registry e a cadeia de suprimentos da imagem. Não é linguagem nem serviço — é o empacotamento. O **isolamento por serviço** (user Linux + systemd), o **deploy gated**, a orquestração, o cofre de segredos e a observabilidade são da `schematize-infra`." cmd="docker" -->Esta skill é a especialista do **artefato OCI** e do **runtime de container**: Dockerfile, imagem, compose de dev/hml, registry e a cadeia de suprimentos da imagem. Não é linguagem nem serviço — é o empacotamento. O **isolamento por serviço** (user Linux + systemd), o **deploy gated**, a orquestração, o cofre de segredos e a observabilidade são da `schematize-infra`.

1. **Onde esta skill divergir da base, a BASE MANDA.** Aqui mora a especialização — a lib, o gate, a
   sintaxe da linguagem. Divergência de *piso* é defeito desta skill, não variante local.
2. **O que não está repetido aqui é HERDADO, não dispensado.** Valem integralmente, sem cópia local:
   - **§28 Archive** — `<projeto>/<projeto>_archive/` é **repositório git próprio, PRIVADO e
     obrigatório**, criticidade 0 (`schematize-archive`).
   - **§35 Definition of Done** e a lista de anti-padrões (citada por **título**, nunca por número).
   - **§39 Índice/MAPA** — enumeração exaustiva (uma entrada por unidade chamável, `M == N`) e grafo
     com arestas em ASCII (`A -> B`), nunca a seta unicode.
   - **IAM** (`schematize-engineering` → `references/iam.md`): identidade ≠ email, ≥2 fatores, ReBAC
     multi-tenant, argon2id-only para senha nova, sessão longa e logout irreversível.
   - **Efeito externo** nunca sai de não-produção (`schematize-engineering` →
     `references/efeitos-externos.md`).
   - **Orquestração** (`schematize-engineering` → `references/orquestracao.md` §9): o principal não
     desenvolve (é Claude Opus); executor mais barato que resolve — `haiku`/`sonnet` → Codex Terra → Cursor → `opus` só após falha; visual direto ao Codex; imagem via Codex Terra, nunca API paga.
3. **QA, ops, IAM e índice não têm comando próprio aqui:** vêm da base `/eng-*`. Para trabalho
   contínuo use `/eng-overdev`; para planejar `/eng-plan`; para varrer a base `/eng-scan`; para
   revisão geral `/eng-review` (e `/eng-ops`, `/eng-iam`, `/eng-index`). Os comandos
   `/docker-*` cobrem só o piso da linguagem.<!-- /herdado -->

## Por que ela nasceu

A `schematize-infra` já exigia "imagem não-root, pinada por digest, sem segredo em layer" — em
**quatro parágrafos espalhados** e com **um** gate que só olhava `USER` e `ports:`. Ninguém dizia como
se escreve o Dockerfile, o que o BuildKit dá de graça (cache, segredo efêmero), como a tag vira
imutável, nem o que o compose de dev pode e não pode expor. O resultado previsível: `FROM node:latest`,
`ARG TOKEN`, `curl | sh`, `-p 5432:5432` e `/var/run/docker.sock` montado "só para o CI". Aqui mora
o **como da imagem**; a infra continua com o **onde e com quem ela roda**.

## Fronteira com as outras skills

| Skill | É dela | É desta |
|---|---|---|
| `schematize-infra` | user Linux + systemd por serviço (`schematize-infra -> references/isolamento.md`), deploy gated e orquestração (`-> references/entrega.md`), cofre e rotação de segredo (`-> references/segredos.md`), SLO/alertas, backup/DR, rede/TLS (`-> references/resiliencia.md`) | Dockerfile, imagem, `.dockerignore`, BuildKit, compose, registry/tags, SBOM/provenance/assinatura/scan da imagem, flags de runtime do container |
| `schematize-engineering` | a base: §28 archive, §35 DoD, fluxo de ambientes (`schematize-engineering -> references/ops.md`), efeito externo (`schematize-engineering -> references/efeitos-externos.md`) | o piso de container que a base cobra de qualquer stack |
| `schematize-go` · `-rust` · `-elixir` · `-csharp` · `-ruby` · `-node` · `-python` | a linguagem, o build da linguagem, o gate dela | só o **empacotamento** dela numa imagem (`references/linguagens.md`) |
| `schematize-shell` | script (`entrypoint.sh`, `install.sh`) é código de produção | o que o script faz dentro da imagem: sem `curl \| sh`, sem root |
| `schematize-pentest` | **prova** que o container não escapa, que o banco não está exposto | o lado construtivo: o que fechar antes |
| `schematize-qa` | smoke e pirâmide de teste | o teste de que a imagem sobe e responde `healthy` |

Regra de bolso: **a infra decide onde e com quem a imagem roda; a docker decide o que está dentro
dela e com que privilégio o container nasce.** Pedido que cruza a fronteira vai pela infra e cita esta skill.

## Comandos (Claude Code)

| Comando | O que faz |
|---|---|
| `/docker-help` | lista os comandos |
| `/docker-load` | carrega à força o corpo normativo (Dockerfile, supply chain, runtime, compose, linguagens) |
| `/docker-review` | revisa Dockerfile e compose contra o piso: roda os dois gates (+ hadolint se houver) e lê o que a máquina não lê |
| `/docker-build` | gera ou ajusta o Dockerfile da stack a partir dos exemplos, e prova que passa no gate |
| `/docker-harden` | endurece a imagem e o runtime: base mínima, não-root, read-only, `cap_drop`, limites |
| `/docker-compose` | audita ou gera o compose de dev/hml (profiles, healthcheck, banco fechado, `.env` fora do git) |
| `/docker-scan` | scan que trava + SBOM + provenance + assinatura e verificação (trivy/grype/scout, cosign) |
| `/docker-claude` | cria/mescla o `CLAUDE.md` sempre-on de Docker na raiz do repo |
| `/docker-cc` · `/docker-handoff` | context compact / handoff arquivado |

## Como usar

1. **Rode os gates antes de discutir estilo:** `bash scripts/check-dockerfile.sh .` e
   `bash scripts/check-compose.sh .` — `0` passa · `1` reprova · `2` **nada para verificar** (que
   não é aprovação). `--strict` promove aviso a erro (use no CI de release).
2. **Escreva a imagem** (`references/dockerfile.md`): multi-stage, base por digest, `USER` numérico,
   cache e segredo pelo BuildKit. Parta do exemplo da sua linguagem (`references/linguagens.md`).
3. **Feche a cadeia de suprimentos** (`references/supply-chain.md`): reprodutível, SBOM + provenance,
   scan que trava, assinatura verificada, tag imutável = sha do git.
4. **Endureça o runtime** (`references/runtime.md`): read-only, `cap_drop: ALL`, sem privilégio,
   sem `docker.sock`, com limites; rootless/Podman quando couber.
5. **Compose só para dev/hml** (`references/compose.md`): produção da casa é `<projeto>_ops` sobre
   systemd/container (infra), não compose.

Mapa de references:

| Tarefa | Reference |
|---|---|
| Dockerfile: multi-stage, base mínima, digest, `USER`, `HEALTHCHECK` vs probes, `.dockerignore`, cache, BuildKit (`--mount`), heredoc, `COPY --link`, higiene de apt/apk | `references/dockerfile.md` |
| Reprodutibilidade, multi-arch (buildx), SBOM/provenance, cosign, scan como gate, registry, tags imutáveis e retenção | `references/supply-chain.md` |
| Runtime: read-only, caps, seccomp/AppArmor, sem `--privileged`/socket, limites, rootless, Podman, logs | `references/runtime.md` |
| Compose de dev/hml: profiles, healthcheck + `depends_on`, redes, volumes, banco fechado, `.env`, secrets | `references/compose.md` |
| Go, Rust, Node (legado), Elixir, .NET, Ruby, Python — base, o que vai na imagem, armadilhas | `references/linguagens.md` |
| Versões, digests e actions verificados (anexo volátil, com data) | `references/stack-versoes.md` |

Assets prontos: `assets/dockerfiles/*.Dockerfile` (um por linguagem) + `.dockerignore` ·
`assets/compose/compose.yaml` + `.env.example` · `assets/ci/github-actions-docker.yml` (buildx
multi-arch, SBOM, provenance, trivy, cosign, actions pinadas por SHA) · `assets/lint/.hadolint.yaml`.

## Artefatos executáveis

| Artefato | Cobre | Reprova quando |
|---|---|---|
| `scripts/check-dockerfile.sh` | `dockerfile.md`, `supply-chain.md` | `FROM` sem digest ou `latest`/sem tag · estágio final sem `USER` ou `USER root` · `ADD` remoto · segredo em `ARG`/`ENV` · `COPY` de `.env`/chave · `curl\|sh` · `chmod 777` · `apt` sem limpeza na camada / `apk` sem `--no-cache` · sem `.dockerignore` ou sem `.env` nele · **repo sem Dockerfile** (exit 2). Avisos: sem pin de apt, `CMD` em forma shell, sem `HEALTHCHECK`, `COPY . .` antes do build |
| `scripts/check-compose.sh` | `compose.md`, `runtime.md` | `privileged` · `docker.sock` · `network_mode/pid/ipc: host` · `cap_add` perigosa · `unconfined` · `user: root` · banco publicado fora do loopback · segredo literal em `environment` · `service_healthy` sem healthcheck · `latest` · `.env` versionado · **repo sem compose** (exit 2). Avisos: sem `cap_drop`/`read_only`/limites, `depends_on` em lista |
| `scripts/*.test.sh` | os dois gates | 71 casos, a maioria vermelhos plantados, sem precisar do daemon |

Waiver rastreável, nunca silencioso: `# docker-ok: <motivo>` na linha da instrução (ou na de
cima) — **sem motivo não vale**; no compose, isenta só o **aviso** de hardening do serviço, nunca
um erro de segurança. Se o `hadolint` estiver instalado, os achados dele entram como aviso
(opcional, nunca obrigatório).

## Pisos inegociáveis (vetam o atalho)

1. **Base por digest, nunca tag móvel.** `FROM imagem:tag@sha256:...`. `latest` e imagem sem tag
   são vetados. O digest apodrece: quem renova é Renovate/Dependabot, em PR, com o scan rodando.
2. **Não-root com UID:GID numérico fixo.** `USER 10001:10001` no estágio final (ou o `nonroot` da
   distroless). Sem `USER` o container é root. `sudo` e `chmod 777` não entram na imagem.
3. **Segredo nunca em `ARG`, `ENV` nem camada.** Segredo de build só por
   `RUN --mount=type=secret`; segredo de runtime entra no start (secret/cofre), nunca na imagem.
   `COPY .env` e chave privada são vetados. O cofre é da `schematize-infra -> references/segredos.md`.
4. **Imagem mínima e multi-stage.** Toolchain só no estágio de build; a imagem final leva o
   binário/runtime e nada mais (distroless, chainguard, scratch, chiseled, alpine/slim quando não
   há opção). Menos pacote, menos CVE, menos superfície.
5. **`.dockerignore` é segurança.** Sem ele o contexto inteiro (`.git`, `.env`, chaves) vai para o
   daemon e pode cair numa camada. Exclui `.env` e `.git` no mínimo.
6. **Nada remoto sem verificação.** `ADD <url>` e `curl | sh` são vetados. Baixe, confira
   `sha256sum -c` (ou assinatura) e só então execute.
7. **Cache e reprodutibilidade por construção.** Manifesto/lockfile antes do código;
   `--mount=type=cache` para gerenciador de pacote; `SOURCE_DATE_EPOCH` e `-trimpath` onde a
   linguagem permite; lockfile commitado. Build de release sai do CI, nunca da máquina de dev.
8. **A imagem sai com proveniência.** SBOM e provenance como attestation no push, scan que
   **trava** em HIGH/CRITICAL (aceite só com ADR datado e prazo), assinatura cosign **por digest**
   e verificação **na admissão** — assinar sem verificar não protege.
9. **Tag imutável = sha do git.** Deploy referencia o digest; `latest` não existe em registry de
   deploy; rollback é redeploy do digest anterior. Registry com tag immutability e retenção
   declarada.
10. **O container nasce sem privilégio.** `read_only`, `cap_drop: ALL`, `no-new-privileges`,
    seccomp/AppArmor default, limites de memória/CPU/pids. **Nunca** `--privileged`, nunca
    `/var/run/docker.sock` montado, nunca `--net=host`/`--pid=host`.
11. **Banco e cache nunca em `0.0.0.0`.** No compose, dado fica na rede interna; acesso humano por
    `docker compose exec` ou profile de debug preso a `127.0.0.1`. `.env` fora do git
    (`.env.example` versionado, sem valor).
12. **Compose é dev/hml, não produção da casa.** Dependência espera `service_healthy`; `depends_on`
    em lista só espera o processo arrancar. `down -v` destrói dado: nunca em hml com dado.
13. <!-- herdado:engineering/orquestracao:curto -->**Orquestrador não desenvolve; subagent barato executa.** O agent principal só planeja, despacha e revisa; ação onerosa vira micro-tasks para o executor mais barato que resolve: `haiku` (mecânico) / `sonnet` (código; falhou → mesmo subagent corrige, até 2 rodadas) → Codex `gpt-5.6-terra` → Cursor → subagent `opus` (motivo) → `park`; **visual vai direto ao Codex**; **imagem: pedir ao Codex Terra, nunca API de imagem paga**; papéis em `agentes.toml`. No overdev, cada item do checklist vai a um subagent e o principal revisa antes do `- [x]`. **Sem frota ociosa:** idle com pendência volta ao trabalho; dependente de outro agent → mata e enfileira com gatilho; terminou → mata (§9.6). Detalhe: `schematize-engineering` → `references/orquestracao.md` §9.<!-- /herdado -->

## Mídia

Esta skill não gera imagem nem mídia. Se um trabalho de container pedir visual gerado (diagrama
de arquitetura para o README, ícone), vale a regra da casa: **nunca por modelo Claude** — detecte
Codex/Gemini e **pergunte ao usuário qual usar**; sem nenhum disponível, avise sem rodeio que
visual gerado pelo Claude sai ruim de verdade (qualidade inversamente proporcional à de código) e
ofereça alternativas: instalar Codex/Gemini, imagem de banco com licença comercial, asset do
cliente. Diagrama de arquitetura em Mermaid versionado (`schematize-docs`) dispensa tudo isso.
