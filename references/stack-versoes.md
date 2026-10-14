# Anexo volátil — versões, digests e ferramental (docker)

> Parte da skill **schematize-docker**. **Fonte volátil:** tudo aqui tem prazo de validade e é
> atualizado **à parte** do corpo normativo — que não crava número (o lint do catálogo, regra
> `anexo-volatil`, reprova quando crava).
>
> **Verificado em: 2026-10-14.** Cadência: revisão trimestral e antes de cada release da skill.
> Digests de base mudam a cada rebuild da imagem de origem: **renove por Renovate/Dependabot**
> (`dockerfile.md` seção 3), não à mão. Fontes: `gh api releases` (GitHub), endoflife.date,
> go.dev/dl e API anônima dos registries; a fonte e a data estão em cada bloco.

## Docker e ecossistema de build/runtime

Fonte: `gh api repos/<org>/<repo>/releases/latest`, 2026-10-14.

| Componente | Versão | Publicada em | Nota |
|---|---|---|---|
| **Docker Engine** (moby) | 29.9.0 | 2026-10-08 | linha 29 sem EOL; **28.x EOL em 2026-05-13** (endoflife.date) |
| **Docker Compose** (plugin) | v5.6.0 | 2026-10-02 | CLI `docker compose` |
| **buildx** | v0.38.0 | 2026-10-07 | |
| **BuildKit** | v0.34.0 | 2026-10-07 | comportamento de `rewrite-timestamp` por versão <!-- reverificar --> |
| **containerd** | v2.4.2 | 2026-10-13 | |
| **Podman** | v6.1.4 | 2026-10-12 | |

Instalado nesta máquina na verificação: `docker` 29.9.0 e `compose` 5.6.0 (cliente; o daemon pode
não estar ativo). Flags de `docker buildx build` conferidas por `--help` em 2026-10-14: `--sbom`,
`--provenance`, `--attest`, `--secret`, `--ssh`, `--platform`, `--output`, `--cache-from`,
`--cache-to`. Flags de `docker compose up`: `--wait`, `--wait-timeout`, `--build`, `--watch`;
comando `docker compose watch`; opção global `--profile`, `-p`.

## Supply chain e lint

Fonte: `gh api releases`, 2026-10-14.

| Ferramenta | Versão | Publicada em | Papel |
|---|---|---|---|
| **cosign** | v3.1.3 | 2026-08-06 | assinatura keyless e verificação |
| **Trivy** | v0.75.0 | 2026-10-01 | scan de imagem/IaC (gate que trava) |
| **Grype** | v0.120.1 | 2026-10-06 | scan de vulnerabilidade |
| **Syft** | v1.54.1 | 2026-10-06 | SBOM |
| **hadolint** | v2.15.1 | 2026-07-31 | lint de Dockerfile (opcional no `check-dockerfile.sh`) |

Não verificados hoje: flags exatas do `docker scout` (`cves`, `sbom`, `--exit-code`)
<!-- reverificar -->; sintaxe de expiração `exp:` do `.trivyignore` <!-- reverificar -->; política
de retenção e de tag immutability de cada registry (GHCR, ECR, Harbor) <!-- reverificar -->;
status de depreciação do `podman generate systemd` frente ao Quadlet <!-- reverificar -->.

## Toolchains das linguagens (para as imagens de build)

Fontes: go.dev/dl, endoflife.date e releases oficiais, 2026-10-14.

| Linguagem | Versão | Nota |
|---|---|---|
| **Go** | 1.27.2 | go.dev/dl |
| **Rust** | 1.99.0 | |
| **Node** | 26.11.1 | **26 vira LTS em 2026-10-28**; 24 é o LTS ativo hoje. Node é legado (manutenção) |
| **Python** | 3.14.8 estável | 3.15.0 lançado em 2026-10-09 (não adotar antes do primeiro patch) |
| **Elixir** | 1.20.4 | imagem `elixir:1.20-otp-28-alpine` |
| **.NET** | 10.0.12 | **LTS até 2028-11-14**; **.NET 8 EOL em 2026-11-10** |
| **Ruby** | 4.0.7 | |

## Digests das bases usadas nos exemplos

Verificados em **2026-10-14** pela API anônima dos registries. Tag e digest andam **juntos** no
`FROM` (`image:tag@sha256:...`); o digest muda a cada rebuild da base: **renove por
Renovate/Dependabot**.

| Imagem:tag | Digest |
|---|---|
| `golang:1.27-alpine` | `sha256:f92b6ef800e499660581efdabdf25d9d817a9d124eaf900924f0504e7e27e12d` |
| `alpine:3.23` | `sha256:85fe1e81d6758c208f3e1eed4338a1997e19d4be002d4dd32d3100c9a8c010a0` |
| `rust:1.99-alpine` | `sha256:0cce0a5e0e8ba67b455257a3a02a1d99005f382748789d6464460028810f1627` |
| `node:26-alpine` | `sha256:143494b1da2945f061539253adc65e4f1569ddf07da2d384c022c791a9d90a4a` |
| `python:3.14-slim` | `sha256:a2b82f3c48559aa0a8446d9af49826b6e2b2016f4cd2afabfe6013ec53729170` |
| `elixir:1.20-otp-28-alpine` | `sha256:54a8abc9bb4c4ee308f09b07ca27a9b5c91bb245d71c97fbc72e0c7ac60a8880` |
| `ruby:4.0-slim` | `sha256:ba6a00593739f9cb66de80ad2e395a93a52a13635867ee32918ba0ec083b1ff6` |
| `debian:trixie-slim` | `sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f` |
| `postgres:18-alpine` | `sha256:77f585114c32fbca283dc835b0596f4e52b51b4c6662d7810b2f4084f60a1873` |
| `redis:8-alpine` | `sha256:3811787313eba226a2ef38658c6ccb91cd5e110edc89c37767de373120a0e5a0` |
| `busybox:1.37` | `sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e` |
| `gcr.io/distroless/static-debian13:nonroot` | `sha256:e2e927ec666bae08560abb3c55d0659eceabb657f56b6782ab500a9fc7f555e3` |
| `gcr.io/distroless/cc-debian13:nonroot` | `sha256:e792ab3d241a468a4fd7519ddbbebe66b49b5f365771716ea688ad40b6c6f1c2` |
| `gcr.io/distroless/base-debian13:nonroot` | `sha256:a0d70d6a97cd697d9362bc2aae4a6560dd65817e365d0043b07325a97975dc91` |
| `mcr.microsoft.com/dotnet/sdk:10.0` | `sha256:0d99ebf1ccad15037b5c98c9fe8979d6b8dbac23812feae2277a0b277b5c5ffa` |
| `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled` | `sha256:84def277556c2843a44fdeefbd3145d0a2e32d8f736d0c1a7b0a96b2880b0187` |

## GitHub Actions pinadas por SHA

Verificadas com `gh api` em **2026-10-14**. No workflow (`assets/ci/github-actions-docker.yml`) o
`uses:` referencia o **SHA do commit** da tag (com a tag em comentário), nunca a tag móvel; renove
por Renovate/Dependabot.

| Action | Versão |
|---|---|
| `actions/checkout` | v7.0.1 |
| `docker/setup-buildx-action` | v4.4.1 |
| `docker/setup-qemu-action` | v4.4.0 |
| `docker/login-action` | v4.6.0 |
| `docker/build-push-action` | v7.4.0 |
| `docker/metadata-action` | v6.2.0 |
| `aquasecurity/trivy-action` | v0.36.0 |
| `sigstore/cosign-installer` | v4.1.2 |

O SHA de cada tag deve ser lido de `gh api repos/<org>/<repo>/git/ref/tags/<tag>` no momento de
atualizar o workflow (resolva tag anotada para o commit).

## Regra que NÃO é volátil

O **piso** (`dockerfile.md`, `runtime.md`, `compose.md`, `supply-chain.md`) e os gates
(`scripts/check-dockerfile.sh`, `scripts/check-compose.sh`) valem independente da versão. Número
muda; "toda base por digest, usuário numérico, nenhum segredo na camada, deploy pelo digest
verificado" não.
