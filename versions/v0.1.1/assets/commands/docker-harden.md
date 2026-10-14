---
description: schematize-docker — endurece imagem e runtime do container: base mínima, não-root, read-only, cap_drop, limites, sem socket nem privileged
argument-hint: "[Dockerfile, compose.yaml ou diretório]"
---

# /docker-harden — o container nasce sem privilégio

1. **Meça o ponto de partida:** `check-dockerfile.sh` e `check-compose.sh` (sem `--strict`) e anote
   cada aviso — ele é a lista de trabalho.
2. **Imagem (`references/dockerfile.md`):** trocar a base por uma mínima (`references/linguagens.md`),
   multi-stage, `USER` numérico, sem shell/compilador no estágio final, `.dockerignore`, limpeza de
   apt/apk na mesma camada, segredo fora de `ARG`/`ENV`.
3. **Runtime (`references/runtime.md`):** `read_only: true` + `tmpfs` onde precisar escrever,
   `cap_drop: [ALL]` e `cap_add` só do necessário, `security_opt: [no-new-privileges:true]`,
   seccomp/AppArmor default, `mem_limit`, `pids_limit`, `init: true`, rede mínima. Remova
   `privileged`, `docker.sock`, `network_mode/pid/ipc: host`, `devices`.
4. **Um passo por vez, com prova:** depois de cada endurecimento, suba o serviço (ou diga que não
   subiu). `read_only` e `cap_drop` quebram quem escreve em disco ou escuta porta baixa: ajuste a
   causa (porta alta, `tmpfs`), não desligue o controle.
5. **Feche com o gate em `--strict`** e liste o que ainda exige decisão humana (ex.: capability que o
   serviço realmente precisa — vira `cap_add` explícito com `# docker-ok: <motivo>`).
6. User Linux + systemd do host, firewall e orquestração: `schematize-infra`. A prova de que o
   container não escapa é da `schematize-pentest`.
