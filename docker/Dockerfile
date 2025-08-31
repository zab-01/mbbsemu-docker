# docker/Dockerfile
# ---------- builder ----------
ARG DOTNET_VERSION=8.0
FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION} AS builder
SHELL ["/bin/bash", "-lc"]
WORKDIR /src

# build args (customize the ref/tag you want to build)
ARG MBBSEMU_REF=master

# tools
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/*

# fetch source
RUN git clone --depth=1 --branch "${MBBSEMU_REF}" https://github.com/mbbsemu/MBBSEmu.git .

# quick sanity: show what we cloned (helps debug if the repo layout changes)
RUN echo "DEBUG: ls -al /src" && ls -al /src

# restore + publish (handle either root csproj or subfolder csproj)
RUN if [ -f "MBBSEmu.csproj" ]; then \
      echo "Publishing root csproj"; \
      dotnet restore MBBSEmu.csproj && \
      dotnet publish MBBSEmu.csproj -c Release -o /out -p:PublishSingleFile=true -p:PublishTrimmed=false; \
    elif [ -f "MBBSEmu/MBBSEmu.csproj" ]; then \
      echo "Publishing subfolder csproj"; \
      dotnet restore MBBSEmu/MBBSEmu.csproj && \
      dotnet publish MBBSEmu/MBBSEmu.csproj -c Release -o /out -p:PublishSingleFile=true -p:PublishTrimmed=false; \
    else \
      echo "Could not find MBBSEmu.csproj; repo layout unexpected" && ls -R && exit 1; \
    fi

# ---------- runtime ----------
FROM mcr.microsoft.com/dotnet/runtime:8.0-bookworm-slim
SHELL ["/bin/bash", "-lc"]
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
    MBBSEMU_HOME=/app \
    MOUNT_ROOT=/mbbsemu \
    PATH="/app:${PATH}"

# small deps and capability for low ports
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libcap2-bin && rm -rf /var/lib/apt/lists/*

# non-root user
RUN useradd -r -u 10001 -g users mbbs
WORKDIR /app

# copy built binary
COPY --from=builder /out/ /app/

# entry + volumes
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
VOLUME ["/mbbsemu"]

# ports + capability
EXPOSE 23/tcp 513/tcp
RUN setcap 'cap_net_bind_service=+ep' /app/MBBSEmu || true

USER mbbs
ENTRYPOINT ["/entrypoint.sh"]
CMD []
