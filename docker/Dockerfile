# syntax=docker/dockerfile:1.7

FROM debian:bookworm-slim

ENV MBBSEMU_HOME=/app \
    CONFIG_ROOT=/config \
    DOTNET_BUNDLE_EXTRACT_BASE_DIR=/config/.net \
    HOME=/config \
    PATH="/app:${PATH}"

RUN apt-get update \
 && apt-get -y upgrade \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip bash libcap2-bin gosu jq \
 && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /app

COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/download-release.sh /app/download-release.sh
RUN chmod +x /entrypoint.sh /app/download-release.sh

# Build arg for pinning a specific release if desired (non-secret)
ARG MBBSEMU_VERSION=latest

# Fetch the release asset at build time.
# We *optionally* read GH_TOKEN from a BuildKit secret to avoid rate limits.
RUN --mount=type=secret,id=GH_TOKEN \
    bash -lc 'export GH_TOKEN="$(cat /run/secrets/GH_TOKEN 2>/dev/null || true)"; bash /app/download-release.sh'

VOLUME ["/config"]
EXPOSE 23 513
RUN setcap 'cap_net_bind_service=+ep' /app/MBBSEmu || true
USER root
ENTRYPOINT ["/entrypoint.sh"]
