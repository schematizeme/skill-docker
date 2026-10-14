---
description: schematize-docker — carrega à força TODO o corpo normativo (Dockerfile, supply chain, runtime, compose, linguagens) e passa a aplicá-lo nesta sessão.
---
Carregue **agora** o corpo normativo da skill `schematize-docker`. A partir daqui, nesta sessão,
isto **não é opcional**.

1. **Leia na íntegra, sem trabalhar de memória.** Caminho:
   `.claude/skills/schematize-docker/references/*.md` (projeto) ou
   `~/.claude/skills/schematize-docker/references/*.md` (global):
   - `dockerfile.md` — multi-stage, base por digest, `USER` numérico, `HEALTHCHECK` vs probes,
     `.dockerignore`, cache, BuildKit (`--mount=type=cache|secret`), heredoc, `COPY --link`.
   - `supply-chain.md` — reprodutibilidade, multi-arch, SBOM/provenance, cosign, scan que trava,
     registry, tag imutável = sha do git e retenção.
   - `runtime.md` — read-only, caps, seccomp/AppArmor, sem `--privileged`/socket, limites, rootless
     e Podman.
   - `compose.md` — compose de dev/hml: profiles, `depends_on` com condição, redes, banco fechado,
     `.env` fora do git, secrets.
   - `linguagens.md` — Go, Rust, Node (legado), Elixir, .NET, Ruby, Python: base e armadilhas.
   - `stack-versoes.md` — anexo volátil: versões, digests e actions, com data de verificação.
2. **Rode os gates no repo atual** antes de opinar sobre estilo:
   `bash .claude/skills/schematize-docker/scripts/check-dockerfile.sh .` e
   `bash .claude/skills/schematize-docker/scripts/check-compose.sh .`
3. **Aplique daqui em diante** a todo Dockerfile e compose que você escrever ou tocar, e diga qual
   piso está aplicando quando ele mudar o que você ia fazer. Isolamento por serviço, deploy gated e
   cofre de segredos continuam com a `schematize-infra`.
