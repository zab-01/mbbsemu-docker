# docker/Dockerfile
FROM mcr.microsoft.com/dotnet/runtime:8.0-bookworm-slim

# ---- Basics ----
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
    MBBSEMU_HOME=/app \
    MOUNT_ROOT=/mbbsemu \
    PATH="/app:${PATH}"

# Tools needed to fetch & unpack release, and to grant low-port bind cap
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl tar libcap2-bin bash \
    && rm -rf /var/lib/apt/lists/*
    
# Non-root user
RUN useradd -r -u 10001 -g users mbbs
WORKDIR /app

# Copy scripts
COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/download-release.sh /app/download-release.sh
RUN chmod +x /entrypoint.sh /app/download-release.sh

# ---- Fetch official release at build time ----
# You can pin a tag like v0.5.0 later; 'latest' is fine to start.
ARG MBBSEMU_VERSION=latest
RUN /app/download-release.sh

# One bind mount path for ALL state: config, modules, db, logs
VOLUME ["/mbbsemu"]

# Expose defaults
EXPOSE 23/tcp 513/tcp

# Allow binding to <1024 without running as root
RUN setcap 'cap_net_bind_service=+ep' /app/MBBSEmu || true

USER mbbs
ENTRYPOINT ["/entrypoint.sh"]
CMD []
