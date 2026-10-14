---
description: Mapa da skill schematize-docker (Docker/OCI: Dockerfile, imagem, compose, supply chain e runtime do container).
---
**schematize-docker** — a especialista do artefato OCI e do runtime de container.

| Comando | O que faz |
|---|---|
| `/docker-help` | esta lista |
| `/docker-load` | carrega à força TODO o corpo normativo (Dockerfile, supply chain, runtime, compose, linguagens) e passa a aplicá-lo |
| `/docker-review` | revisa Dockerfile e compose: roda `check-dockerfile.sh` e `check-compose.sh` (+ hadolint se houver) e lê o que a máquina não lê |
| `/docker-build` | gera ou ajusta o Dockerfile da stack a partir de `assets/dockerfiles/` e prova que passa no gate |
| `/docker-harden` | endurece imagem e runtime: base mínima, não-root, read-only, `cap_drop`, limites, sem socket |
| `/docker-compose` | audita ou gera o compose de dev/hml (profiles, healthcheck, banco fechado, `.env` fora do git) |
| `/docker-scan` | scan que trava + SBOM + provenance + assinatura/verificação (trivy, grype, scout, cosign) |
| `/docker-claude` | cria ou mescla o `CLAUDE.md` sempre-on de Docker na raiz do repo |
| `/docker-cc` · `/docker-handoff` | context compact / handoff no archive |

Pareia com: `schematize-infra` (isolamento por serviço, deploy gated, orquestração, cofre,
observabilidade), `schematize-engineering` (base, ops, efeito externo), as skills de linguagem
(o build da linguagem), `schematize-shell` (entrypoint e instaladores), `schematize-pentest`
(prova que o container não escapa).
