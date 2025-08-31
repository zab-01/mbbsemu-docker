FROM debian:bookworm-slim

ENV MBBSEMU_HOME=/app \
    CONFIG_ROOT=/config \
    PATH="/app:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip bash libcap2-bin \
    && rm -rf /var/lib/apt/lists/*

SHELL ["/bin/bash", "-lc"]

WORKDIR /app

COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/download-release.sh /app/download-release.sh
RUN chmod +x /entrypoint.sh /app/download-release.sh

# Pull latest release (Linux x64 by default)
ARG MBBSEMU_VERSION=latest
RUN bash /app/download-release.sh

VOLUME ["/config"]
EXPOSE 23/tcp 513/tcp
RUN setcap 'cap_net_bind_service=+ep' /app/MBBSEmu || true

USER nobody
ENTRYPOINT ["/entrypoint.sh"]
