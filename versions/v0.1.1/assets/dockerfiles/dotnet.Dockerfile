# syntax=docker/dockerfile:1
# .NET: restore/publish no SDK, execução em aspnet chiseled (sem shell, sem gerenciador de pacote, não-root).
# Digests verificados em 2026-10-14; renove por Renovate/Dependabot, não à mão.
# Build: docker buildx build --provenance=mode=max --sbom=true --build-arg SOURCE_DATE_EPOCH=$(git log -1 --pretty=%ct) -t app:sha-$(git rev-parse HEAD) .

FROM mcr.microsoft.com/dotnet/sdk:10.0@sha256:0d99ebf1ccad15037b5c98c9fe8979d6b8dbac23812feae2277a0b277b5c5ffa AS build
WORKDIR /src
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

# Projeto/lock antes do código: o restore só refaz quando os .csproj ou packages.lock.json mudam.
COPY --link App/App.csproj App/packages.lock.json ./App/
RUN --mount=type=cache,target=/root/.nuget/packages \
    dotnet restore App/App.csproj --locked-mode

COPY --link . .
# Determinismo: ContinuousIntegrationBuild + paths mapeados; sem apphost (rodamos via `dotnet App.dll`).
RUN --mount=type=cache,target=/root/.nuget/packages \
    dotnet publish App/App.csproj -c Release -o /out --no-restore \
      -p:UseAppHost=false -p:ContinuousIntegrationBuild=true -p:DebugType=none

FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled@sha256:84def277556c2843a44fdeefbd3145d0a2e32d8f736d0c1a7b0a96b2880b0187
WORKDIR /app
COPY --link --from=build /out ./
ENV ASPNETCORE_HTTP_PORTS=8080 DOTNET_EnableDiagnostics=0
# $APP_UID da imagem chiseled vale 1654; fixado por número.
USER 1654:1654
EXPOSE 8080
# Chiseled não tem shell nem curl: a probe é do orquestrador (readiness/liveness em /healthz), não da imagem.
HEALTHCHECK NONE
ENTRYPOINT ["dotnet", "App.dll"]
