---
description: schematize-docker — audita ou gera o compose de dev/hml (profiles, healthcheck, depends_on com condição, banco fechado, .env fora do git)
argument-hint: "[compose.yaml ou diretório]"
---

# /docker-compose — compose para dev e hml (produção da casa é a infra)

1. **Existe compose?** Rode `bash .claude/skills/schematize-docker/scripts/check-compose.sh --strict .`.
   Se sai `2`, não há o que auditar: pergunte se quer gerar a partir de
   `assets/compose/compose.yaml` (+ `.env.example`).
2. **Ao gerar:** sem `version:`; imagens por digest; `healthcheck` em todo serviço;
   `depends_on` com `condition: service_healthy`; banco e cache **sem `ports:`** (acesso por
   `docker compose exec`; se for indispensável, profile `debug` preso a `127.0.0.1`); rede interna
   para o dado; volumes nomeados; segredo por `secrets:` (`file:`), nunca `environment` literal;
   ferramentas de admin em `profiles:`; `read_only`, `cap_drop`, `mem_limit`, `pids_limit`.
3. **`.env`:** fora do git (`.gitignore`), `.env.example` versionado sem valor. Se o gate achar
   `.env` versionado: tire do índice (`git rm --cached`), **rotacione o que vazou** e avise — o
   histórico do git guarda o segredo.
4. **Âncoras/merge (`<<: *x`):** o gate lê a forma literal; valide a final com `docker compose config`
   (não cole a saída em lugar público — ela interpola o `.env`).
5. **Prove:** gate em `--strict` + `docker compose config -q` (sem daemon) + `docker compose up --wait`
   (com daemon). `down -v` apaga dado: nunca em hml com dado.
6. Orquestração, rede de produção e cofre: `schematize-infra`.
