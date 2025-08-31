FROM debian:bookworm-slim

ENV MBBSEMU_HOME=/app \
    CONFIG_ROOT=/config \
    DOTNET_BUNDLE_EXTRACT_BASE_DIR=/config/.net \
    HOME=/config \
    PATH="/app:${PATH}"

# keep base patched; install deps + gosu for privilege drop
RUN apt-get update \
 && apt-get -y upgrade \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip bash libcap2-bin gosu \
 && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /app

# scripts
COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/download-release.sh /app/download-release.sh
RUN chmod +x /entrypoint.sh /app/download-release.sh

# fetch latest stable release at build-time (never at runtime)
ARG MBBSEMU_VERSION=latest
RUN bash /app/download-release.sh

# all mutable state lives here
VOLUME ["/config"]

# telnet / rlogin
EXPOSE 23 513

# allow binding low ports as non-root
RUN setcap 'cap_net_bind_service=+ep' /app/MBBSEmu || true

# run as root only long enough for entrypoint to chown + gosu drop to PUID/PGID
USER root
ENTRYPOINT ["/entrypoint.sh"]
