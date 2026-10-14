# Changelog — schematize-docker

Todas as mudanças relevantes deste pacote, no formato [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
com versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [0.1.1] — 2026-10-14
Integração ao catálogo (grafo, skills.json, herdados) e correção do texto de precedência herdado.

### Alterado
- Blocos herdados ressincronizados com a `schematize-engineering` v0.27.0 (`tools/sync-herdados.mjs`): orquestração com a regra de imagem (nunca pelo Claude; detecta Codex/Gemini e pergunta ao usuário qual usar, Codex como sugestão) e `schematize overdev delegar` (comando do app) no lugar do falso nome de skill `schematize-overdev`.
- Bloco "Precedência e herança" passa à variante `dominio`: o texto antigo dizia que os comandos `/docker-*` "cobrem só o piso da linguagem", o que é falso para skill de domínio/ferramenta.

## [0.1.0] — 2026-10-14
Skill nova: Docker/OCI de ponta a ponta, porque a casa já exigia "imagem não-root, pinada por digest, sem segredo em layer" em quatro parágrafos espalhados pela `schematize-infra` e com um único gate (`USER` e `ports:`), sem dizer como se escreve o Dockerfile, o que o BuildKit dá de graça, como a tag vira imutável nem o que o compose de dev pode expor.

### Adicionado
- `SKILL.md` com 13 pisos inegociáveis, a fronteira com `schematize-infra` (isolamento por serviço, deploy gated, orquestração, cofre, observabilidade ficam lá), `schematize-engineering`, as skills de linguagem, shell e pentest, e a regra de mídia da casa.
- `references/`: `dockerfile`, `supply-chain`, `runtime`, `compose`, `linguagens` e o anexo volátil `stack-versoes` (versões, digests e actions verificados em 2026-10-14).
- `scripts/check-dockerfile.sh` e `scripts/check-compose.sh`: gates estáticos que não precisam do daemon (hadolint opcional), com waiver rastreável `# docker-ok: <motivo>`, `--strict`, e exit `2` quando não há artefato. `*.test.sh` com 71 casos, a maioria vermelhos plantados.
- `assets/`: Dockerfiles de referência (Go, Rust, Node legado, Elixir, .NET, Ruby, Python) por digest e não-root, `.dockerignore`, `compose.yaml` de dev + `.env.example`, workflow de CI (buildx multi-arch, SBOM, provenance, trivy, cosign; actions pinadas por SHA verificado com `gh api`), `.hadolint.yaml`, `CLAUDE.md` sempre-on.
- Comandos: `/docker-help`, `/docker-load`, `/docker-review`, `/docker-build`, `/docker-harden`, `/docker-compose`, `/docker-scan`, `/docker-claude`, `/docker-cc`, `/docker-handoff`.
