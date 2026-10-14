# schematize-docker

> **A imagem é o artefato que vai para produção.** Esta skill é o piso de Docker/OCI da casa:
> Dockerfile multi-stage por digest e não-root, BuildKit (cache e segredo efêmero), compose de dev
> com banco fechado, buildx multi-arch, SBOM e provenance, cosign, scan que trava, runtime
> hardening e **tag imutável = sha do git** — com gates estáticos que **não precisam do daemon**.

Pacote de **skill normativa para [Claude Code](https://claude.com/claude-code)**.
Parte do catálogo **schematize skills**.

## Por que ela existe

A `schematize-infra` já exigia imagem não-root, pinada e sem segredo em camada — em parágrafos
espalhados e com um gate que só olhava `USER` e `ports:`. Ninguém dizia como se escreve o
Dockerfile nem o que o compose de dev pode expor. O resultado: `FROM node:latest`, `ARG TOKEN`,
`curl | sh`, `-p 5432:5432` e o `docker.sock` montado "só para o CI". Aqui mora o **como da
imagem**; a infra continua com o **onde e com quem ela roda**.

## Instalar

### Pelo app schematize (recomendado)

```bash
schematize install docker    # requer o CLI schematize instalado
```

### Manual

```bash
git clone https://github.com/schematizeme/skill-docker.git /tmp/skill-docker
bash /tmp/skill-docker/install.sh .        # instala em .claude/ do projeto atual
bash /tmp/skill-docker/install.sh "$HOME"  # ou global
```

## O que tem dentro

- **SKILL.md** — o contrato: 13 pisos inegociáveis, a fronteira com a infra e o mapa de references.
- **references/** — `dockerfile`, `supply-chain`, `runtime`, `compose`, `linguagens` e
  `stack-versoes` (anexo volátil com data de verificação).
- **scripts/** — `check-dockerfile.sh` e `check-compose.sh` (gates estáticos, waiver rastreável
  `# docker-ok: <motivo>`, `--strict`) e os `*.test.sh` (71 casos, a maioria vermelhos plantados).
- **assets/** — Dockerfiles por linguagem, `.dockerignore`, `compose.yaml` de dev, workflow de CI,
  `.hadolint.yaml`, `CLAUDE.md` sempre-on, `commands/`.

## Comandos

| Comando | O que faz |
|---|---|
| `/docker-help` | lista os comandos |
| `/docker-load` | carrega o corpo normativo e passa a aplicá-lo |
| `/docker-review` | roda os gates e revisa o que a máquina não lê |
| `/docker-build` | gera ou ajusta o Dockerfile da stack |
| `/docker-harden` | endurece imagem e runtime |
| `/docker-compose` | audita ou gera o compose de dev/hml |
| `/docker-scan` | scan que trava, SBOM, provenance, assinatura |
| `/docker-claude` | cria/mescla o `CLAUDE.md` sempre-on |
| `/docker-cc` · `/docker-handoff` | context compact / handoff no archive |

## Versão

**v0.1.0** — changelog em `CHANGELOG.md`.

## Regra de ouro

**O container nasce sem privilégio e a imagem sai com proveniência.** Não é "usamos Docker" — é
que cada decisão que dá poder (root, capability, segredo, porta, tag móvel) está **escrita e
justificada**, ou não existe.

MIT.
