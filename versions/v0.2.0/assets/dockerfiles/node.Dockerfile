# syntax=docker/dockerfile:1
# LEGADO: apenas para manutenção de serviço Node existente. Serviço novo não nasce em Node
# (ver schematize-node e o rol de linguagens); esta receita existe para não deixar o legado sem piso.
# Digests verificados em 2026-10-14; renove por Renovate/Dependabot, não à mão.
# Build: docker buildx build --provenance=mode=max --sbom=true -t app:sha-$(git rev-parse HEAD) .

FROM node:26-alpine@sha256:143494b1da2945f061539253adc65e4f1569ddf07da2d384c022c791a9d90a4a AS deps
WORKDIR /app
# Lockfile antes do código; npm ci falha se package.json e lock divergirem. Só dependências de produção.
COPY --link package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev --ignore-scripts

FROM node:26-alpine@sha256:143494b1da2945f061539253adc65e4f1569ddf07da2d384c022c791a9d90a4a AS build
WORKDIR /app
COPY --link package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --ignore-scripts
COPY --link . .
# Compila TypeScript/bundle para dist/ (devDependencies só existem neste estágio).
RUN npm run build

FROM node:26-alpine@sha256:143494b1da2945f061539253adc65e4f1569ddf07da2d384c022c791a9d90a4a
WORKDIR /app
ENV NODE_ENV=production
COPY --link --from=deps /app/node_modules ./node_modules
COPY --link --from=build /app/dist ./dist
COPY --link package.json ./
# UID 1000 é o usuário `node` da imagem oficial, aqui por número.
USER 1000:1000
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 CMD ["node", "-e", "fetch('http://127.0.0.1:3000/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
ENTRYPOINT ["node"]
CMD ["dist/main.js"]
