# syntax=docker/dockerfile:1.7

FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-bookworm-slim

ENV MBBSEMU_HOME=/app \
    CONFIG_ROOT=/config \
    DOTNET_BUNDLE_EXTRACT_BASE_DIR=/config/.net \
    HOME=/config \
    TERM=xterm \
    PATH="/app:${PATH}"

# keep base patched; install tooling and runtime libs
# (ICU comes from base, ncurses here; add jq, unzip, sqlite3, gosu, libcap2-bin)
RUN apt-get update \
 && apt-get -y upgrade \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip bash libcap2-bin gosu jq sqlite3 \
      libncursesw6 \
 && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /app

# scripts
COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/download-release.sh /app/download-release.sh
RUN chmod +x /entrypoint.sh /app/download-release.sh

# (optional) pin to a specific release with MBBSEMU_VERSION
ARG MBBSEMU_VERSION=latest

# Fetch latest stable release at build time using a BuildKit secret (no token in layers)
RUN --mount=type=secret,id=GH_TOKEN \
    bash -lc 'export GH_TOKEN="$(cat /run/secrets/GH_TOKEN 2>/dev/null || true)"; bash /app/download-release.sh'

# persist user config/data
VOLUME ["/config"]

# Telnet / Rlogin
EXPOSE 23 513

# allow binding low ports as non-root
RUN setcap 'cap_net_bind_service=+ep' /app/MBBSEmu || true

# start in /config so generated files land in the volume
WORKDIR /config

USER root
ENTRYPOINT ["/entrypoint.sh"]
