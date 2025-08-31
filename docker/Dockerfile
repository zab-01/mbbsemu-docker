FROM debian:bookworm-slim

ENV MBBSEMU_HOME=/app \
    CONFIG_ROOT=/config \
    PATH="/app:${PATH}"

# Security: apply patches on build, install deps + gosu for privilege drop
RUN apt-get update \
 && apt-get -y upgrade \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip bash libcap2-bin gosu \
 && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /app

COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/download-release.sh /app/download-release.sh
RUN chmod +x /entrypoint.sh /app/download-release.sh

# Pull latest release
ARG MBBSEMU_VERSION=latest
RUN bash /app/download-release.sh

VOLUME ["/config"]
EXPOSE 23 513

# Allow binding low ports (23, 513) without root
RUN setcap 'cap_net_bind_service=+ep' /app/MBBSEmu || true

# Run as root just long enough to chown + drop to PUID/PGID via entrypoint
USER root
ENTRYPOINT ["/entrypoint.sh"]
