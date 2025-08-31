# docker/Dockerfile
FROM mcr.microsoft.com/dotnet/runtime:8.0-bookworm-slim

ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
    MBBSEMU_HOME=/app \
    MOUNT_ROOT=/mbbsemu \
    PATH="/app:${PATH}"

# Ensure bash exists, plus curl/tar and setcap
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl tar libcap2-bin bash \
    && rm -rf /var/lib/apt/lists/*

# Use bash for all subsequent RUN steps (avoids /bin/sh invoking)
SHELL ["/bin/bash", "-lc"]

# Non-root user
RUN useradd -r -u 10001 -g users mbbs
WORKDIR /app

# Copy scripts from build context
COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/download-release.sh /app/download-release.sh

# Quick debug to prove the files & bash exist (remove later)
RUN echo "DEBUG: which bash -> $(which bash)" \
 && echo "DEBUG: /app contents:" && ls -al /app \
 && echo "DEBUG: head of download-release.sh:" && head -n 5 /app/download-release.sh \
 && bash -n /app/download-release.sh

# Fetch official release at build time
ARG MBBSEMU_VERSION=latest
RUN bash /app/download-release.sh

# Single bind mount for all state
VOLUME ["/mbbsemu"]

EXPOSE 23/tcp 513/tcp

# Allow low ports without running the container as root
RUN setcap 'cap_net_bind_service=+ep' /app/MBBSEmu || true

USER mbbs
ENTRYPOINT ["/entrypoint.sh"]
CMD []
