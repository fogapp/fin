# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Fog builds it on deploy; to build'n'run by hand:
# docker build -t fin .
# docker run -d -p 80:80 -e SECRET_KEY_BASE=<long-random-hex> --name fin fin

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.9
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages (zstd unpacks the file components of fog-backup/1 artifacts).
# The Postgres client comes from PGDG pinned to major 18, the fleet standard
# (fog internal/pg/pg.go; fog docs/postgres-18-proposal.md). Debian's stock
# postgresql-client (v15 on bookworm, v17 on trixie) is older, and a pg_dump
# older than the server it dumps refuses to run, which silently kills every
# fog backup. The PGDG suite follows the base image's Debian release. Bump
# the pin when the fleet moves majors.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates curl && \
    install -d /usr/share/postgresql-common/pgdg && \
    curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc && \
    echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt '"$(. /etc/os-release && echo "$VERSION_CODENAME")"'-pgdg main' > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y libjemalloc2 libvips postgresql-client-18 zstd && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems and Node.js for frontend
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config curl && \
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install --no-install-recommends -y nodejs && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems. COPY the vendor directory itself, not a glob:
# `COPY vendor/* ./vendor/` flattens each subdirectory's contents, so the
# vendored flare gem (vendor/gems/flare) would land at vendor/flare where
# the Gemfile's path: can't see it.
COPY vendor ./vendor
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Build frontend SPA (outputs directly to ../public via vite.config.ts)
WORKDIR /rails/frontend
RUN npm ci && npm run build
WORKDIR /rails

# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security.
# /rails/storage is where Active Storage files and fog-backup staging
# live: created here, owned by the app user, so a deploy without a volume
# mounted over it (plain docker) still has somewhere to write.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p /rails/storage /rails/tmp && chown -R rails:rails /rails
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
