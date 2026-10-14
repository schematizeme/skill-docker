---
description: schematize-docker — context compact: grava o handoff no archive e roda /compact.
---
Antes de compactar, **grave o handoff** em `<projeto>/<projeto>_archive/context/` no par
**context + checklist** do padrão da `schematize-archive` (prefixo `AAAA-MM-DD-<slug>-`) (FEITO vs
ABERTO), seguindo a `schematize-archive`. Inclua: Dockerfiles e composes revisados/escritos, os
achados de `check-dockerfile.sh` e `check-compose.sh` que ficaram abertos, os waivers
`# docker-ok:` concedidos (com o motivo), os digests/tags usados e o que **não** foi provado por
falta de daemon. Só então rode `/compact`.
