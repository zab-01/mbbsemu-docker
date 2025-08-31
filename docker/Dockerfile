FROM debian:bookworm-slim

ENV MBBSEMU_HOME=/app \
    CONFIG_ROOT=/config \
    PATH="/app:${PATH}"

# Update base image and install dependencies
RUN apt-get update \
 && apt-get -y upgrade \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip bash libcap2-bin \
 && rm -rf /var/lib/apt/lists/*

# Use bash for all RUN commands
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /app

COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/download-release.sh /app/download-release.sh

RUN chmod +x /entrypoint.sh /app/download-release.sh

# Fetch the latest MBBSEmu release
ARG MBBSEMU_VERSION=latest
RUN bash /app/download-release.sh

# Config volume + exposed ports
VOLUME ["/config"]
EXPOSE 23 513

# Allow low-port binding (e.g., telnet on 23)
RUN setcap 'cap_net_bind_service=+ep' /app/MBBSEmu || true

USER nobody
ENTRYPOINT ["/entrypoint.sh"]
