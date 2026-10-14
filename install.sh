#!/usr/bin/env bash
# install.sh — instala a skill schematize-docker no projeto atual (Claude Code).
#
# Motivo: padronizar a instalação de uma skill normativa do catálogo schematize
# skills, sem passos manuais e sem conflito de comandos entre skills.
# Como funciona: copia o corpo da skill para .claude/skills/schematize-docker/ e instala os
# comandos (já no padrão <slug>-*, globalmente únicos) ACHATADOS em
# .claude/commands/. Idempotente: reexecutar sobrescreve a mesma versão E **PODA** o
# comando que a skill removeu — sem a poda, o comando morto sobrevivia para sempre na
# máquina de quem já tinha instalado (achado A7b da vistoria de 2026-08-21).
# Entrada: $1 opcional = diretório do projeto alvo (default: diretório atual).
# Saída: .claude/skills/schematize-docker/ e .claude/commands/<slug>-*.md no alvo.
set -euo pipefail

SKILL_NAME="schematize-docker"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$PWD}"
SKILL_DIR="$DEST/.claude/skills/$SKILL_NAME"
CMD_DIR="$DEST/.claude/commands"

mkdir -p "$SKILL_DIR" "$CMD_DIR"

# Copia o corpo da skill, excluindo os artefatos de distribuição do repo.
# `*.zip` está na lista porque o zip da release mora no repo e ia junto para dentro
# da skill instalada, dobrando o peso e vazando o pacote para dentro do pacote.
EXCL=(.git .github versions install.sh README.md LICENSE '*.zip')
if command -v rsync >/dev/null 2>&1; then
  args=(); for e in "${EXCL[@]}"; do args+=(--exclude "$e"); done
  rsync -a --delete-excluded "${args[@]}" "$SRC"/ "$SKILL_DIR"/
else
  args=(); for e in "${EXCL[@]}"; do args+=(--exclude="$e"); done
  ( cd "$SRC" && tar "${args[@]}" -cf - . ) | ( cd "$SKILL_DIR" && tar -xf - )
fi

# Comandos achatados: nomes já são <slug>-* (únicos), convivem sem colidir.
# PODA primeiro: todo comando com um prefixo DESTA skill que não existe mais no pacote
# é removido do destino. É o que faz `install.sh` refletir a remoção, e não só a adição.
if [ -d "$SKILL_DIR/assets/commands" ]; then
  prefixos=""
  for f in "$SKILL_DIR"/assets/commands/*.md; do
    [ -e "$f" ] || continue
    b="$(basename "$f" .md)"
    p="${b%%-*}"
    case " $prefixos " in *" $p "*) ;; *) prefixos="$prefixos $p" ;; esac
  done
  for p in $prefixos; do
    for antigo in "$CMD_DIR/$p"-*.md; do
      [ -e "$antigo" ] || continue
      if [ ! -e "$SKILL_DIR/assets/commands/$(basename "$antigo")" ]; then
        rm -f "$antigo"
        echo "- comando removido pela skill, podado do destino: $(basename "$antigo")"
      fi
    done
  done
  cp "$SKILL_DIR"/assets/commands/*.md "$CMD_DIR"/ 2>/dev/null || true
fi

echo "✓ $SKILL_NAME instalada em $SKILL_DIR"
echo "✓ comandos em $CMD_DIR (use /<slug>-help para listar)"
