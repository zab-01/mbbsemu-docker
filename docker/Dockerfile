# ---------- builder ----------
ARG DOTNET_VERSION=8.0
FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION} AS builder
SHELL ["/bin/bash", "-lc"]
WORKDIR /src

ARG MBBSEMU_REF=master

RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Clone and verify
RUN git clone --depth=1 --branch "${MBBSEMU_REF}" https://github.com/mbbsemu/MBBSEmu.git . \
 && git rev-parse --is-inside-work-tree \
 && echo "DEBUG: top-level after clone:" && ls -al

# Restore using the solution (more robust than guessing the csproj path)
RUN test -f MBBSEmu.sln || (echo "ERROR: MBBSEmu.sln missing" && ls -R && exit 1)
RUN dotnet --info && dotnet restore MBBSEmu.sln

# Publish: try subfolder csproj first, fallback to root csproj
RUN set -e; \
   if [ -f "./MBBSEmu/MBBSEmu.csproj" ]; then \
      echo "Publishing ./MBBSEmu/MBBSEmu.csproj"; \
      dotnet publish ./MBBSEmu/MBBSEmu.csproj -c Release -o /out -p:PublishSingleFile=true -p:PublishTrimmed=false; \
   elif [ -f "./MBBSEmu.csproj" ]; then \
      echo "Publishing ./MBBSEmu.csproj"; \
      dotnet publish ./MBBSEmu.csproj -c Release -o /out -p:PublishSingleFile=true -p:PublishTrimmed=false; \
   else \
      echo "ERROR: could not find MBBSEmu.csproj in repo; layout unexpected" && ls -R && exit 1; \
   fi

# ---------- runtime ----------
FROM mcr.microsoft.com/dotnet/runtime:8.0-bookworm-slim
SHELL ["/bin/bash", "-lc"]
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
    MBBSEMU_HOME=/app \
    MOUNT_ROOT=/mbbsemu \
    PATH="/app:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libcap2-bin \
 && rm -rf /var/lib/apt/lists/*

RUN useradd -r -u 10001 -g users mbbs
WORKDIR /app

COPY --from=builder /out/ /app/
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/mbbsemu"]
EXPOSE 23/tcp 513/tcp
RUN setcap 'cap_net_bind_service=+ep' /app/MBBSEmu || true

USER mbbs
ENTRYPOINT ["/entrypoint.sh"]
CMD []
