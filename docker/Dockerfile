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

# Build args (optionally passed from GH Actions)
ARG MBBSEMU_VERSION=latest
ARG GH_TOKEN
ENV GH_TOKEN="${GH_TOKEN}"

# Fetch the release asset at build time (no runtime unzipping)
RUN bash /app/download-release.sh

VOLUME ["/config"]
EXPOSE 23 513
RUN setcap 'cap_net_bind_service=+ep' /app/MBBSEmu || true
USER root
ENTRYPOINT ["/entrypoint.sh"]
