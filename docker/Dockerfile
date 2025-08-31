FROM debian:bookworm-slim

ENV MBBSEMU_HOME=/app \
    CONFIG_ROOT=/config \
    PATH="/app:${PATH}"

# Install deps including bash + unzip
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip bash libcap2-bin \
    && rm -rf /var/lib/apt/lists/*

# Make sure all RUN use bash
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /app

COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/download-release.sh /app/download-release.sh

RUN chmod +x /entrypoint.sh /app/download-release.sh

# Run the script explicitly with bash
ARG MBBSEMU_VERSION=latest
RUN bash /app/download-release.sh

VOLUME ["/config"]
EXPOSE 23 513

# allow binding low ports
RUN setcap 'cap_net_bind_service=+ep' /app/MBBSEmu || true

USER nobody
ENTRYPOINT ["/entrypoint.sh"]
