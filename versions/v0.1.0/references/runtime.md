# Runtime do container — hardening, limites, rootless e CI

> Parte da skill **schematize-docker**. A imagem está em `dockerfile.md`, a procedência em
> `supply-chain.md`, o compose em `compose.md`. Aqui fica a **configuração do container em
> execução**: o que ele pode fazer, quanto pode consumir e o que enxerga do host.
>
> **Por que esta skill existe:** container **não é uma VM**; é um processo do host com visão
> restrita. Cada capability mantida, cada mount do host e cada `--privileged` reabre o caminho para
> fora. O incidente típico não é exploit sofisticado: é `-v /var/run/docker.sock:/var/run/docker.sock`
> "só para o CI" — que entrega o host inteiro.
>
> **Fronteira.** `schematize-infra -> references/isolamento.md` é dona do isolamento **do host**:
> user Linux por serviço, unit systemd, permissões de diretório, firewall. Aqui é a configuração do
> **container**. As duas camadas se somam (defesa em profundidade); nenhuma substitui a outra.
> Em k8s o equivalente vive no manifesto (tabela da seção 9). O gate de compose
> (`scripts/check-compose.sh`) cobra o que for estático.

Convenção: **MUST** = piso · **VETADO** = reprova · `# docker-ok:` = waiver rastreável.

---

## 1. O padrão da casa em um bloco

```yaml
services:
  api:
    image: ghcr.io/org/app@sha256:<digest>
    user: "10001:10001"
    read_only: true
    tmpfs: [ "/tmp:size=64m,mode=1777" ]
    cap_drop: [ ALL ]
    security_opt: [ "no-new-privileges:true" ]
    pids_limit: 256
    mem_limit: 512m
    cpus: 1.0
    init: true
    restart: unless-stopped
    stop_grace_period: 30s
    logging:
      driver: json-file
      options: { max-size: "10m", max-file: "5" }
    healthcheck:
      test: ["CMD", "/app", "--healthcheck"]
      interval: 15s
      timeout: 3s
      retries: 3
      start_period: 20s
```

Cada linha tem seu motivo nas seções abaixo. O gate `check-compose.sh` reprova a ausência de
hardening (`cap_drop`/`no-new-privileges`) e de `healthcheck`. `assets/compose/compose.yaml` é o
exemplo completo.

---

## 2. Rootfs somente leitura

`read_only: true` (`docker run --read-only`): o sistema de arquivos do container não é gravável.
O atacante que consegue execução não planta binário, não altera o código, não grava webshell.
O que a aplicação precisa **escrever** é declarado, um a um:

- **`tmpfs`** para efêmero (`/tmp`, `/run`, cache): em memória, some no restart.
  `tmpfs: ["/tmp:size=64m,noexec,nosuid"]` — `noexec` onde a app não executa o que grava.
- **Volume nomeado** para dado persistente (`compose.md` seção 5).

Aplicação que "precisa escrever em qualquer lugar" é aplicação que não declarou onde escreve:
conserte a aplicação, não o `read_only`. Escreve em `$HOME`? Aponte `HOME=/tmp` ou um tmpfs.

---

## 3. Capabilities, `no-new-privileges`, seccomp, LSM

- **`cap_drop: [ALL]`** e `cap_add` **apenas o mínimo comprovado**. O Docker concede por padrão um
  conjunto de ~14 capabilities (CHOWN, NET_RAW, SETUID, ...) que quase nenhum serviço usa. O mais
  comum de reabilitar: `NET_BIND_SERVICE` (porta < 1024 — prefira porta alta), `CHOWN`/`SETUID`/`SETGID`
  só em entrypoint que troca de usuário (e então o entrypoint é suspeito: troque na imagem).
  Cada `cap_add` leva comentário com o motivo. **Nunca** `SYS_ADMIN` (é o "quase root"), `SYS_PTRACE`,
  `NET_ADMIN` em serviço de aplicação.
- **`security_opt: ["no-new-privileges:true"]`**: o processo e seus filhos **não ganham privilégio**
  via `setuid`/`setgid`/file capabilities. Mata a escalada clássica por binário setuid dentro da imagem.
- **seccomp**: o perfil **padrão do Docker** bloqueia dezenas de syscalls perigosas (`mount`,
  `reboot`, `kexec_load`, ...) e fica ligado se você não mexer. **VETADO**
  `security_opt: ["seccomp=unconfined"]` (waiver só com motivo). Para serviço exposto e maduro,
  um **perfil custom** (allowlist do que o binário realmente chama, gerado por `strace`/profiling
  em teste) é o próximo degrau.
- **AppArmor / SELinux**: ligue o perfil padrão (`docker-default` no Debian/Ubuntu; no
  RHEL/Fedora o SELinux com `:z`/`:Z` nos bind mounts). Não desligue (`apparmor=unconfined`,
  `label=disable`) para "fazer funcionar": o erro é do mount ou do caminho, e o `audit.log` diz qual.
- **`--privileged` é VETADO.** Ele desliga seccomp e AppArmor, concede todas as capabilities, dá
  acesso a todos os devices e permite montar o disco do host: um container privilegiado **é** o host.
  O gate reprova `privileged: true`. Se algum caso parece exigir: qual capability específica? qual
  device específico (`devices:` pontual)? Quase sempre a resposta é uma só e cabe numa linha.
- **Sem `--device`** de host em serviço de aplicação; sem `--pid=host`, `--ipc=host`,
  `--uts=host` (enxergar/sinalizar processos do host e compartilhar memória).

---

## 4. NUNCA montar `/var/run/docker.sock`

Quem fala com o socket do Docker **manda o daemon** (que roda como root) criar um container
privilegiado com `/` do host montado. **Acesso ao socket = root no host**, sem exploit nenhum. O gate
reprova o mount (`check-compose.sh`) e o `-v` equivalente.

Casos em que "precisam" do socket, e a alternativa:

| Necessidade | Alternativa |
|---|---|
| Proxy reverso que descobre containers (Traefik, nginx-proxy) | **socket proxy somente leitura** (ex.: `tecnativa/docker-socket-proxy`) expondo só `GET /containers` e `/events`, em rede interna; ou configuração por arquivo/provider estático <!-- reverificar --> |
| CI que **constrói** imagem | **BuildKit remoto** (`buildx` com driver `remote`/`kubernetes`) · **kaniko** · **buildah** (daemonless) · **Docker rootless dentro de um runner isolado e descartável** |
| CI que roda testes com containers | serviços do próprio CI (`services:`) · Testcontainers contra um daemon **dedicado e descartável**, nunca o do host |
| Orquestrar containers a partir de um painel | API do orquestrador com credencial de escopo mínimo, nunca o socket |

---

## 5. Limites de recurso — container sem teto derruba o host

Sem limite, um vazamento de memória ou um fork-bomb de **um** container leva todos os outros (o
OOM killer do host escolhe a vítima, e nem sempre é o culpado).

```bash
docker run --memory=512m --memory-swap=512m --cpus=1.0 --pids-limit=256 \
           --ulimit nofile=65536:65536 ...
```

- **`--memory`** (`mem_limit`): teto rígido. Estourar = **OOM kill do container**
  (`docker inspect` mostra `OOMKilled: true`, exit 137). `--memory-swap` igual ao `--memory`
  desliga o swap do container (swap mascara o vazamento e degrada tudo).
- **`--cpus`** (`cpus`): fração de CPU (cota CFS). `--cpu-shares` é peso relativo, não teto.
- **`--pids-limit`** (`pids_limit`): contém **fork bomb** e vazamento de threads.
- **`--ulimit nofile`**: banco e proxy pedem mais que o padrão; defina explícito, não ilimitado.
- Dimensione pelo **medido** (`docker stats`, métricas) com folga, e registre no archive. Runtime
  gerenciado (JVM, .NET, Go) precisa conhecer o limite: o cgroup é lido pelo runtime moderno, mas
  confira (`GOMEMLIMIT`, `DOTNET_GCHeapHardLimit` e afins vêm da skill da linguagem).

---

## 6. Rede mínima

- Rede **dedicada por stack**; banco em rede `internal: true` (sem rota para fora). Detalhe em
  `compose.md` seção 4.
- **`ports:` publica no host**; só o que é de fato exposto, e **em loopback** quando o acesso é
  local (`127.0.0.1:5432:5432`). Publicar `0.0.0.0` com firewall "de reserva" é a causa clássica de
  banco na internet — **o Docker escreve regras de iptables que contornam o ufw/firewalld**
  <!-- reverificar o comportamento com nftables nas versões correntes -->; não confie no firewall
  do host para proteger porta publicada.
- **VETADO `--network host`** (`network_mode: host`): o container usa a pilha de rede do host, sem
  isolamento. Exceção rara (agente de métrica de host), com `docker-ok` e ADR.
- Sem `expose`/`ports` para o que só é consumido por outro container da mesma rede.

---

## 7. User namespaces e rootless

- **`userns-remap`** (daemon): o root do container (UID 0) mapeia para um UID **sem privilégio** no
  host. Mesmo que o atacante escape sendo "root", é um UID sem poder. Custo: volumes e bind mounts
  precisam do mapeamento de dono; alguns recursos (`--privileged`, `--net=host`) ficam indisponíveis.
- **Docker rootless**: o **próprio daemon** roda sem root, no UID de um usuário comum, com user
  namespace. Um escape cai num usuário sem privilégios. Limitações: sem portas < 1024 (ajuste de
  `net.ipv4.ip_unprivileged_port_start`), rede via `slirp4netns`/`pasta` (mais lenta), alguns
  drivers de storage e de rede indisponíveis. Bom padrão para host de CI e de desenvolvimento.
- **Podman** — *daemonless* e rootless por desenho: sem socket privilegiado persistente, cada
  container é filho do processo do usuário (fork/exec, com `conmon`). Mesma CLI quase integral
  (`alias docker=podman`). Para rodar como serviço use **Quadlet** (arquivos `.container` em
  `~/.config/containers/systemd/`, gerados em unit systemd) — o antigo `podman generate systemd` é
  legado, **prefira Quadlet** <!-- reverificar o status de depreciação na versão corrente -->.

**Quando preferir qual:**

| Cenário | Escolha |
|---|---|
| Host de dev/CI com várias pessoas | Docker rootless ou Podman |
| Serviço em host systemd da casa, unit por serviço | **Podman + Quadlet** (a unit já é do systemd; o user Linux do serviço é o do `schematize-infra -> references/isolamento.md`) |
| Compose já existente, equipe fluente em Docker | Docker Engine com hardening da seção 1; rootless quando possível |
| Precisa de recurso exclusivo (Swarm, extensões Desktop) | Docker Engine |

---

## 8. Logs, restart e parada

### Logging com rotação — o disco que encheu

O driver padrão `json-file` **não rotaciona** por padrão: um serviço verboso enche o disco do host
em dias, e a queda é de **todos** os serviços. **MUST** rotação explícita:

```yaml
logging:
  driver: json-file
  options: { max-size: "10m", max-file: "5" }
```

Ou global em `/etc/docker/daemon.json`: `{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"5"}}`
(vale para containers **criados depois**). Em produção com agregador, driver `journald`/`syslog`/
`fluentd` ou stdout coletado pelo agente — a aplicação loga em **stdout/stderr** (12-factor), nunca
em arquivo dentro do container. Observabilidade: `schematize-infra -> references/observabilidade.md`.

### Restart policy

`restart: unless-stopped` (serviço de longa vida) ou `on-failure:5` (limita o loop de crash). **Evite
`always` sem limite** em serviço que quebra na subida: vira loop de reinício que esconde a falha e
consome CPU. Restart policy **não substitui** healthcheck nem monitoramento: container que reinicia
sozinho 40 vezes é incidente, não sucesso.

### Parada graciosa

`docker stop` = SIGTERM, espera `--stop-timeout` (padrão 10 s), depois SIGKILL.
`stop_grace_period: 30s` no compose para serviço com drenagem de conexões ou *flush* de fila. O
tempo deve ser **maior** que o pior shutdown medido e menor que o do orquestrador acima. O app
precisa tratar SIGTERM (`dockerfile.md` seção 8) — senão o prazo todo é perdido.

---

## 9. Docker em CI — DinD x socket

O CI precisa construir imagens. Ordem de preferência:

1. **Build sem daemon do host**: `buildx` com builder remoto/Kubernetes, kaniko ou buildah.
2. **Docker-in-Docker (DinD)** com daemon **efêmero**, rootless se possível, num runner descartável
   por job. O DinD tradicional usa `--privileged` — aceitável **apenas** num runner isolado, sem
   segredo permanente, destruído ao fim do job, e documentado em ADR.
3. **Socket do host montado** — **VETADO** (seção 4). Em runner compartilhado o job de qualquer um
   vira root no runner e lê o segredo do job do outro.

Regras adicionais: runner de PR de **fork** nunca recebe segredo nem credencial de registry;
push só em branch protegida; cache de build por `type=gha`/`type=registry`, não por volume do host.
O workflow de referência é `assets/ci/github-actions-docker.yml`.

---

## 10. Equivalente em Kubernetes

Os mesmos controles, na linguagem do orquestrador (o manifesto é de `schematize-infra`; esta tabela
é para o par ficar consistente):

| Controle (docker/compose) | Kubernetes (`securityContext` e afins) |
|---|---|
| `user: "10001:10001"` | `runAsUser: 10001`, `runAsGroup: 10001`, `runAsNonRoot: true` |
| `read_only: true` + `tmpfs` | `readOnlyRootFilesystem: true` + `emptyDir` (`medium: Memory`) |
| `cap_drop: [ALL]` / `cap_add` | `capabilities.drop: [ALL]` / `capabilities.add` |
| `no-new-privileges:true` | `allowPrivilegeEscalation: false` |
| seccomp padrão / custom | `seccompProfile: { type: RuntimeDefault }` / `Localhost` |
| AppArmor / SELinux | anotação/`appArmorProfile` · `seLinuxOptions` |
| `privileged: true` (vetado) | `privileged: false` (o padrão); Pod Security `restricted` |
| `mem_limit` / `cpus` | `resources.limits.memory` / `cpu` (+ `requests`) |
| `pids_limit` | `podPidsLimit` no kubelet <!-- reverificar --> |
| `HEALTHCHECK` / `healthcheck:` | `livenessProbe` / `readinessProbe` / `startupProbe` |
| `stop_grace_period` | `terminationGracePeriodSeconds` |
| `userns-remap` | `hostUsers: false` (user namespaces no pod) |
| rede `internal` | `NetworkPolicy` default-deny |
| `restart:` | `restartPolicy` do pod (e o controlador) |
| `init: true` | `shareProcessNamespace` ou `tini` na imagem |

Pod Security Admission no nível **`restricted`** é o piso do namespace: ele exige exatamente a
tabela acima.

---

## Regra de bolso

Container nasce **sem poder algum** (`cap_drop: ALL`, `no-new-privileges`, rootfs somente leitura,
usuário numérico) e **com teto** (memória, CPU, pids, log); cada permissão devolvida é uma linha
comentada com o motivo. Socket do Docker, `--privileged` e rede do host não são "casos
especiais": são o jeito de entregar o host. Prefira rootless/Podman quando o host é nosso.
