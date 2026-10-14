---
description: schematize-docker — scan que trava, SBOM, provenance e assinatura (trivy/grype/scout, buildx attestations, cosign) com verificação
argument-hint: "[imagem@digest ou diretório do build]"
---

# /docker-scan — você entrega tudo o que embarca

1. **Qual imagem?** Sempre por **digest** (`img@sha256:...`), nunca por tag móvel. Sem imagem
   construída: audite o `assets/ci/github-actions-docker.yml` do repo (ou gere a partir do exemplo).
2. **Scan que trava** (`references/supply-chain.md`): `trivy image --severity HIGH,CRITICAL --exit-code 1 <img>`
   (ou `grype <img> --fail-on high`, ou `docker scout cves`). O scan roda **antes** de publicar a
   tag de release. Aceite de CVE: `.trivyignore` com motivo, ADR e **validade** — nunca silêncio.
3. **SBOM e provenance como attestation:** `docker buildx build --sbom=true --provenance=mode=max`;
   inspecione com `docker buildx imagetools inspect <img> --format '{{json .SBOM}}'` e `--format '{{json .Provenance}}'`.
   SBOM avulso: `syft <img> -o cyclonedx-json`.
4. **Assinatura e verificação:** `cosign sign <img>@<digest>` (keyless por OIDC no CI) e
   **`cosign verify` com `--certificate-identity` e `--certificate-oidc-issuer`** — a verificação
   na admissão é o que protege; assinar sem verificar não protege.
5. **Relate** CVE por severidade e se há correção disponível, o que travou, o que foi aceito (com
   ADR e prazo) e o que **não foi verificado** (ex.: sem daemon, sem acesso ao registry). Segredo
   achado na imagem: rotação imediata, `schematize-infra -> references/segredos.md`.
