---
description: schematize-docker — revisa Dockerfile e compose contra o piso: roda os dois gates (e o hadolint, se houver) e lê o que a máquina não lê
argument-hint: "[Dockerfile, compose.yaml ou diretório]"
---

# /docker-review — a imagem é o artefato que vai para produção

## 1. A máquina primeiro

```bash
bash .claude/skills/schematize-docker/scripts/check-dockerfile.sh --strict .   # a imagem
bash .claude/skills/schematize-docker/scripts/check-compose.sh --strict .      # o runtime de dev/hml
command -v hadolint >/dev/null && hadolint Dockerfile                          # opcional
```

`0` passa · `1` reprova · `2` **nada para verificar** — que não é aprovação. Sem `--strict` o aviso
não trava; no CI de release use `--strict`. Waiver: `# docker-ok: <motivo>` (sem motivo não vale).

## 2. Depois, o que a máquina não lê

- **Base:** é a mínima possível para esta linguagem (`references/linguagens.md`)? O digest é recente
  e quem o renova está configurado (Renovate/Dependabot)?
- **Camadas:** existe segredo escondido em `RUN` (`echo`, `curl -u`, `git clone https://token@`)? Cada
  `RUN` que baixa algo verifica integridade? O que o `COPY . .` leva, de fato, para dentro?
- **Estágio final:** só o necessário para rodar? Há shell, compilador ou gerenciador de pacote
  sobrando? O `USER` é numérico e o dono dos arquivos escritos bate com ele?
- **Sinais e saúde:** `ENTRYPOINT` em forma exec, o processo trata `SIGTERM`, existe `init`
  quando há filhos. `HEALTHCHECK` funciona **sem curl** numa imagem sem shell? O orquestrador tem as
  probes dele (`liveness` ≠ `readiness`)?
- **Compose:** o que está publicado em `ports:` e a quem? Banco só na rede interna? `depends_on`
  espera `service_healthy`? O `.env` real está fora do git e o `.env.example` documenta as chaves?
- **Supply chain:** o CI gera SBOM + provenance, escaneia antes de publicar, assina por digest e
  alguém **verifica** a assinatura? A tag é o sha do git?
- **Runtime:** `read_only`, `cap_drop: ALL`, `no-new-privileges`, limites de memória/CPU/pids.
  Nada de `--privileged` nem socket montado.

## 3. Feche

Achado vira correção no mesmo PR ou item de checklist com dono — não "depois". Mexeu num gate? Rode
o vermelho dele: `bash scripts/check-dockerfile.test.sh` (38 casos) e `bash scripts/check-compose.test.sh` (33).
Pedido sobre user Linux/systemd, deploy ou cofre: é da `schematize-infra`.
