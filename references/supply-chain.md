# Cadeia de suprimentos da imagem — reprodutível, atestada, assinada, verificada

> Parte da skill **schematize-docker**. O Dockerfile em si está em `dockerfile.md`; o hardening do
> container em `runtime.md`. Aqui ficam o que acontece **depois do build**: como provar de onde a
> imagem veio, o que há dentro dela, quem a assinou, e como o registry a guarda e a esquece.
> Versões e flags voláteis: `stack-versoes.md`.
>
> **Por que esta skill existe:** uma imagem sem procedência é um binário baixado de um desconhecido.
> Assinar sem **verificar** é teatro; escanear sem **travar** é relatório que ninguém lê; tag
> mutável em produção é "o que está rodando?" sem resposta.
>
> **Fronteira.** `schematize-infra` é dona do deploy gated, da orquestração e da política de
> admissão do cluster; esta skill define o **que a imagem carrega** (digest, attestations,
> assinatura) e o que o registry garante. A prova ofensiva (a admissão realmente rejeita imagem
> não assinada?) é de `schematize-pentest`.

Convenção: **MUST** = piso · **VETADO** = reprova · `# docker-ok:` = waiver rastreável.

---

## 1. Reprodutibilidade — o que se controla e o que não

Objetivo: o mesmo commit produz a **mesma imagem** (ou, no mínimo, a mesma imagem *funcional*, com
diferença explicável). O que a casa exige, em ordem de custo/benefício:

1. **Entradas fixas:** base por digest (`dockerfile.md` seção 3), dependências por **lockfile**
   (`go.sum`, `Cargo.lock`, `package-lock.json` com `npm ci`, `mix.lock`, `Gemfile.lock`,
   `uv.lock`), ferramentas baixadas com sha256 verificado.
2. **Tempo fixo:** `SOURCE_DATE_EPOCH` = timestamp do commit. BuildKit o honra para os metadados do
   build, e `rewrite-timestamp` normaliza o mtime dos arquivos das camadas:

```bash
export SOURCE_DATE_EPOCH="$(git log -1 --pretty=%ct)"
docker buildx build \
  --build-arg SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
  --output type=oci,dest=app.oci.tar,rewrite-timestamp=true .
```

   O comportamento exato de `rewrite-timestamp` (exporters que suporta, interação com `--load`)
   depende da versão do BuildKit <!-- reverificar -->.
3. **Compilador determinístico:** `-trimpath` (Go), `--remap-path-prefix` / `-C
   strip=symbols` (Rust), ordem de arquivos estável e sem timestamp embutido. Binário que embute
   `__DATE__`/`BuildTime` quebra tudo.
4. **Camadas estáveis:** `COPY` de arquivos com mtime normalizado; nenhum `RUN` que escreva
   timestamp, UUID ou número aleatório na imagem.

### O que ainda NÃO é bit-a-bit

Seja honesto no ADR: mesmo com tudo acima, uma imagem **pode** divergir por: pacote `apt`/`apk` sem
pin (o índice mudou), `npm`/`pip` que resolvem versão transitiva fora do lockfile, compressão gzip
diferente entre builders, ordem de entradas do tar, metadados do builder, diferença entre
plataformas. A meta realista é **digest reprodutível para base e dependências** + **verificação
de equivalência** (reconstruir e comparar o conteúdo com `diffoci` ou equivalente
<!-- reverificar -->), não a promessa de bit-a-bit universal. O que **nunca** é negociável é que o
digest que foi testado e assinado seja o digest que sobe.

---

## 2. Multi-arch com `buildx`

Duas formas de produzir `linux/amd64` + `linux/arm64`:

| Forma | Como | Preço |
|---|---|---|
| **QEMU** (emulação) | `docker/setup-qemu-action` + `--platform linux/amd64,linux/arm64` num runner só | simples; **lento** (5 a 20x) na arquitetura emulada, e raro bug de emulação em compilação pesada |
| **Builders nativos** | um nó por arquitetura (`docker buildx create --append` ou runners ARM do CI), build em paralelo | rápido e fiel; precisa de runner de cada arquitetura |

Preferência: **nativo quando o build é pesado** (Rust, .NET, C); QEMU aceitável para build leve
(Go com cross-compile real é melhor ainda: `GOARCH` no estágio de build com `FROM --platform=$BUILDPLATFORM`).

```dockerfile
FROM --platform=$BUILDPLATFORM golang:<corrente>-alpine@sha256:<digest> AS build
ARG TARGETOS TARGETARCH
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH CGO_ENABLED=0 go build -o /out/app ./cmd/app
```

```bash
docker buildx build --platform linux/amd64,linux/arm64 --push -t ghcr.io/org/app:sha-abc1234 .
docker buildx imagetools inspect ghcr.io/org/app:sha-abc1234   # mostra a manifest list
```

O resultado é uma **manifest list** (índice OCI): uma tag/digest aponta para um manifesto por
plataforma. **Assina-se o digest da manifest list** (e os filhos, se a política exigir). `--load`
no daemon clássico carrega só uma plataforma; multi-arch vai para `--push` ou `--output type=oci`.

---

## 3. SBOM e provenance como attestations

Duas atestações que o BuildKit gera no próprio build e **anexa ao registry** como artefatos OCI
referenciados pelo digest da imagem (não são camadas):

```bash
docker buildx build --sbom=true --provenance=mode=max --push -t ghcr.io/org/app:sha-abc1234 .
# equivalente longo:  --attest type=sbom --attest type=provenance,mode=max
```

- **SBOM** (lista de componentes: pacotes do SO e dependências da linguagem) — formato SPDX por
  padrão. Serve para responder "essa CVE nova atinge o quê, hoje?" sem rebuild.
- **Provenance** (SLSA): quem/onde/como construiu — repositório, commit, workflow, argumentos de
  build, base usada. `mode=max` inclui os argumentos e o contexto completos (pode conter dado
  sensível se você passou segredo por `--build-arg`: mais uma razão do veto a segredo em `ARG`);
  `mode=min` omite.

Inspeção:

```bash
docker buildx imagetools inspect ghcr.io/org/app@sha256:<digest> \
  --format '{{ json .SBOM }}'          # SBOM
docker buildx imagetools inspect ghcr.io/org/app@sha256:<digest> \
  --format '{{ json .Provenance }}'    # provenance
syft ghcr.io/org/app@sha256:<digest> -o spdx-json > sbom.spdx.json   # SBOM independente
docker scout sbom ghcr.io/org/app@sha256:<digest>                     # idem, Docker Scout <!-- reverificar -->
```

Nível **SLSA**: build em CI hospedado (não na máquina do dev) com provenance gerada pela
plataforma ≈ **SLSA Build L2**; builder isolado e provenance não forjável (workflow reutilizável do
`slsa-github-generator` ou equivalente) ≈ **L3** <!-- reverificar o mapeamento atual -->. A meta da
casa é L2 em tudo e L3 no que é crítico.

SBOM de uma imagem de `scratch`/distroless só enxerga o que o binário declara (Go embute módulos;
Rust precisa de `cargo auditable`). Documente a lacuna no ADR em vez de fingir cobertura.

---

## 4. Assinatura — cosign keyless, por digest

Chave de assinatura de longa vida é um segredo a mais para vazar. A casa usa **keyless**: o CI
obtém um token OIDC do provedor (identidade do workflow), o Sigstore emite um certificado de vida
curta e registra a assinatura no log de transparência (Rekor).

```bash
# no CI (permissions: id-token: write, packages: write)
cosign sign --yes ghcr.io/org/app@sha256:<digest>
```

**MUST: assine o DIGEST, nunca a tag.** Tag move; a assinatura "da tag" assina o que ela apontava
naquele instante e o cosign avisa. A saída do `build-push-action` expõe o `digest` — use-o.

Anexe também as attestations próprias, se a política pedir (resultado do scan, SBOM extra):

```bash
cosign attest --yes --type spdxjson --predicate sbom.spdx.json ghcr.io/org/app@sha256:<digest>
```

### Verificação — o que dá valor à assinatura

```bash
cosign verify ghcr.io/org/app@sha256:<digest> \
  --certificate-identity "https://github.com/<org>/<repo>/.github/workflows/release.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

`--certificate-identity` + `--certificate-oidc-issuer` **fixam quem pode assinar**: sem eles,
qualquer pessoa com um certificado Sigstore válido (isto é, qualquer um) "assinou". Use a forma
exata (ou `--certificate-identity-regexp` ancorada), nunca um regexp frouxo `.*`.

### Verificar NA ADMISSÃO — senão não protege

**Assinar sem verificar não protege nada.** O atacante que empurra uma imagem para o registry não
a assina; a proteção só existe se **quem executa** recusa o não assinado:

- **Kubernetes:** controlador de admissão (Kyverno `verifyImages`, Sigstore policy-controller,
  Ratify/Gatekeeper) com a identidade e o issuer acima, em modo **enforce** (não `audit`).
- **Host com systemd/podman:** a etapa de deploy (`schematize-infra -> references/entrega.md`) roda
  `cosign verify` do digest **antes** de `pull`/`up`, e aborta se falhar. Podman também verifica
  via `policy.json` (`sigstoreSigned`) <!-- reverificar -->.
- O pipeline de deploy recebe o **digest**, não a tag, e verifica **esse** digest.

A prova de que a recusa funciona (empurrar imagem não assinada e ver o deploy recusar) é caso de
`schematize-pentest` e entra no DoD (`schematize-engineering` §35).

---

## 5. Scan de vulnerabilidade — gate que TRAVA

Ferramentas: **Trivy**, **Grype**, **Docker Scout**. Uma basta; duas dão cobertura cruzada (bases de
dados diferentes). O scan roda **em dois momentos**: no PR (antes do merge) e **agendado** sobre o
que está em produção (CVE nova aparece depois do deploy).

```bash
trivy image --severity HIGH,CRITICAL --exit-code 1 ghcr.io/org/app@sha256:<digest>
grype ghcr.io/org/app@sha256:<digest> --fail-on high
docker scout cves --exit-code --only-severity critical,high <imagem>   # <!-- reverificar flags -->
```

**MUST:** `HIGH`/`CRITICAL` **reprova** o pipeline (exit code != 0). Relatório sem `exit-code` é
decoração.

### Exceções — com data, motivo e prazo

- **`--ignore-unfixed`** (ignora CVE sem correção publicada) só com **ADR datado** que registre:
  por que é aceitável (não alcançável, não exposto), a compensação e o **prazo de revisão**.
  Ligar `--ignore-unfixed` como padrão silencioso apaga justamente o risco que existe sem remédio.
- **`.trivyignore`** (ou `.grype.yaml`) — cada linha com **motivo e validade**:

```
# CVE-2026-0000  pacote libfoo  inalcançável: serviço não carrega o módulo afetado
# ADR-0042  revisar até 2026-12-01
CVE-2026-0000 exp:2026-12-01
```

  O Trivy aceita `exp:AAAA-MM-DD` na linha do `.trivyignore` <!-- reverificar -->: ao vencer, o
  achado volta a reprovar. Exceção **sem validade** é VETADA.
- Correção preferida é sempre **trocar/atualizar a base** (rebuild, seção 8), não ignorar.

O scan também lê `Dockerfile`/IaC (`trivy config`) — complementa o `check-dockerfile.sh`, não o
substitui (o gate da casa roda sem rede e sem daemon).

---

## 6. Registry — tags e o que elas prometem

| Tag | Natureza | Uso |
|---|---|---|
| `sha-<7+ do git>` | **imutável**: um commit, uma imagem | a tag de verdade; é o que o CI publica sempre |
| `1.4.2` (semver) | alias de **release**, aponta para um `sha-` | conveniência humana; criada só no release |
| `main` / `edge` | móvel: último build da branch | só dev/hml; nunca referenciada em deploy |
| `latest` | **proibida em deploy** | o gate reprova no Dockerfile e no compose |

**MUST:** o **deploy referencia o digest** (`image: ghcr.io/org/app@sha256:...`), não a tag — tag
imutável por convenção ainda pode ser sobrescrita por engano ou invasão; digest não. A tag
`sha-<commit>` existe para o humano achar a imagem a partir do commit; o digest é o que se
executa e se assina.

**Tag immutability** do registry: ligue onde existe (ECR `imageTagMutability=IMMUTABLE`, Harbor
"tag immutability rules", GHCR não tem trava de imutabilidade por tag no momento — compense com
digest e com permissão de escrita mínima <!-- reverificar cada registry -->). Imutabilidade é
defesa em profundidade; o digest no deploy é a defesa principal.

---

## 7. Retenção — o registry não é um depósito infinito

Sem política, o registry cresce até custar caro e, pior, até que ninguém saiba o que pode apagar.
A política de **lifecycle** (todo registry tem uma: ECR lifecycle policy, Harbor retention,
GHCR `actions/delete-package-versions` ou o equivalente da organização
<!-- reverificar o mecanismo de cada um -->) segue as regras:

1. **Reter tudo que está em produção** (e em hml): o digest atualmente implantado e o
   **anterior** (o rollback). A fonte da verdade é o manifesto de deploy; retenção que apaga o digest
   em uso quebra o rollback.
2. **Reter as N últimas por branch** (ex.: 20 de `main`, 5 por branch de feature).
3. **Reter tags de release** (semver) pelo tempo de suporte da versão.
4. **Apagar não-tagueadas** (manifestos órfãos, camadas sem referência) com idade (ex.: > 14 dias).
5. **Apagar tag de branch/PR** ao fechar o PR.
6. Attestations e assinaturas (`.sig`, `.att`, referrers) **seguem a imagem**: a política não pode
   apagar a assinatura de uma imagem retida.

---

## 8. Rebuild periódico e rollback

- **Rebuild semanal agendado** (cron do CI) de toda imagem em produção, **mesmo sem mudança de
  código**: absorve patch da base e do SO (`dockerfile.md` seção 3 — o digest pinado apodrece).
  O rebuild passa pelo scan e pelo mesmo pipeline de promoção; digest novo, deploy gated normal.
- **Rollback = redeploy do digest anterior.** Não é rebuild. Rebuildar para "voltar" produz uma
  imagem nova, diferente da que estava ok. Como o deploy referencia digest e a retenção guarda o
  anterior, voltar é só reaplicar o manifesto anterior (`schematize-infra -> references/entrega.md`
  para a mecânica de rolling/blue-green/canary).

---

## 9. O pipeline de referência

`assets/ci/github-actions-docker.yml` implementa a sequência, com actions pinadas por SHA:
build com cache → `--sbom`/`--provenance` → push por sha → scan que trava → `cosign sign` do
digest → verificação de teste. A ordem importa: **scan antes de assinar** (não se assina o que
reprova) e **assinar antes de promover**.

---

## Regra de bolso

Constrói-se **uma vez**, em CI, e o artefato é o **digest**: atestado (SBOM + provenance),
escaneado (trava em HIGH/CRITICAL), assinado (keyless, identidade fixada) e **verificado por quem o
executa**. Tag é rótulo para humano; o que sobe, o que se assina e o que se desfaz com rollback é
sempre o digest.
