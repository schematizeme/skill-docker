# syntax=docker/dockerfile:1
# Rails 8: bundle em modo deployment, assets:precompile e runtime em ruby slim, usuário 10001.
# Digests verificados em 2026-10-14; renove por Renovate/Dependabot, não à mão.
# Build: docker buildx build --provenance=mode=max --sbom=true --secret id=rails_master_key,src=config/master.key --build-arg SOURCE_DATE_EPOCH=$(git log -1 --pretty=%ct) -t app:sha-$(git rev-parse HEAD) .

FROM ruby:4.0-slim@sha256:ba6a00593739f9cb66de80ad2e395a93a52a13635867ee32918ba0ec083b1ff6 AS build
WORKDIR /rails
ENV RAILS_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT="development:test" BUNDLE_PATH=/usr/local/bundle
# docker-ok: toolchain de compilação só no estágio de build (descartado); pin pacote=versão exige snapshot do índice Debian, a reprodutibilidade vem do digest da base
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends build-essential git libyaml-dev libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Gemfile + Gemfile.lock antes do código.
COPY --link Gemfile Gemfile.lock ./
RUN --mount=type=cache,target=/root/.bundle/cache \
    bundle install --jobs 4 && bundle exec bootsnap precompile --gemfile

COPY --link . .
RUN bundle exec bootsnap precompile app/ lib/
# A master key entra só por secret do BuildKit (não vira camada nem aparece no `docker history`).
RUN --mount=type=secret,id=rails_master_key,target=/rails/config/master.key \
    SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

FROM ruby:4.0-slim@sha256:ba6a00593739f9cb66de80ad2e395a93a52a13635867ee32918ba0ec083b1ff6
WORKDIR /rails
ENV RAILS_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT="development:test" BUNDLE_PATH=/usr/local/bundle
# docker-ok: só bibliotecas de runtime (libpq5, jemalloc); pin pacote=versão exige snapshot do índice Debian, a reprodutibilidade vem do digest da base
RUN apt-get update && apt-get install -y --no-install-recommends libpq5 libjemalloc2 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 rails && useradd --uid 10001 --gid 10001 --create-home --shell /usr/sbin/nologin rails
COPY --link --from=build --chown=10001:10001 /usr/local/bundle /usr/local/bundle
COPY --link --from=build --chown=10001:10001 /rails /rails
ENV LD_PRELOAD=libjemalloc.so.2
USER 10001:10001
EXPOSE 3000
# Rails 8 expõe /up por default.
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 CMD ["ruby", "-rnet/http", "-e", "exit(Net::HTTP.get_response(URI('http://127.0.0.1:3000/up')).is_a?(Net::HTTPSuccess) ? 0 : 1)"]
ENTRYPOINT ["./bin/rails"]
CMD ["server", "-b", "0.0.0.0", "-p", "3000"]
