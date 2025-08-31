# syntax=docker/dockerfile:1.7

FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-bookworm-slim

ENV MBBSEMU_HOME=/app \
    CONFIG_ROOT=/config \
    DOTNET_BUNDLE_EXTRACT_BASE_DIR=/config/.net \
    HOME=/config \
    TERM=xterm \
    PATH="/app:${PATH}"

# keep base patched; install tooling and runtime libs (ICU from base, ncurses here)
RUN apt-get update \
 && apt-get -y upgrade \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip bash libcap2-bin gosu jq \
      libncursesw6 \
 && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ----- build-time area -----
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

# ----- runtime area -----
# start in /config so any generated files (e.g., BBSGEN.DB) go to the bind mount
WORKDIR /config

# entrypoint will drop to PUID/PGID via gosu
USER root
ENTRYPOINT ["/entrypoint.sh"]
