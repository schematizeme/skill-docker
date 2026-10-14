---
description: schematize-docker — gera ou ajusta o Dockerfile da stack a partir dos exemplos da skill e prova que passa no gate
argument-hint: "[go|rust|node|elixir|dotnet|ruby|python] [diretório do serviço]"
---

# /docker-build — escrever a imagem do jeito da casa

1. **Detecte a stack** pelo manifesto (`go.mod`, `Cargo.toml`, `package.json`, `mix.exs`, `*.csproj`,
   `Gemfile`, `pyproject.toml`) ou pelo argumento. Stack fora do rol: pergunte; não invente.
2. **Parta do exemplo**: `.claude/skills/schematize-docker/assets/dockerfiles/<stack>.Dockerfile`
   mais o `.dockerignore` ao lado. Leia `references/linguagens.md` para a armadilha da stack. Se já
   existe Dockerfile, **ajuste** o existente (não reescreva): preserve o que funciona e troque só o
   que o gate reprova.
3. **Adapte** nome do binário/módulo, porta, comando de healthcheck e `USER`. Mantenha: base por
   digest (copie o digest de `references/stack-versoes.md` ou resolva o atual), multi-stage,
   manifesto antes do código, `--mount=type=cache`, segredo só por `--mount=type=secret`.
4. **Prove**:
   ```bash
   bash .claude/skills/schematize-docker/scripts/check-dockerfile.sh --strict <diretório>
   docker buildx build --provenance=mode=max --sbom=true -t <img>:sha-$(git rev-parse --short HEAD) .   # se houver daemon
   ```
   Sem daemon na máquina: diga que o build **não** foi provado e entregue só o resultado do gate.
5. **Entregue** o diff, o resultado do gate e o que ficou sem verificar. Não publique imagem daqui:
   release sai do CI (`assets/ci/github-actions-docker.yml`).
