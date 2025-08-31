ARG DOTNET_VERSION=8.0
FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION} AS builder
WORKDIR /src
ARG MBBSEMU_REF=master
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*
RUN git clone --depth=1 --branch ${MBBSEMU_REF} https://github.com/mbbsemu/MBBSEmu.git .
RUN dotnet publish MBBSEmu.csproj -c Release -o /out \
    -p:PublishSingleFile=true -p:PublishTrimmed=false

FROM mcr.microsoft.com/dotnet/runtime:8.0-bookworm-slim
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
    MBBSEMU_HOME=/app \
    MOUNT_ROOT=/mbbsemu \
    PATH="/app:${PATH}"
RUN apt-get update && apt-get install -y --no-install-recommends libcap2-bin ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN useradd -r -u 10001 -g users mbbs
WORKDIR /app
COPY --from=builder /out/ /app/
COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/download-release.sh /app/download-release.sh
RUN chmod +x /entrypoint.sh /app/download-release.sh
VOLUME ["/mbbsemu"]
EXPOSE 23/tcp 513/tcp
RUN setcap 'cap_net_bind_service=+ep' /app/MBBSEmu || true
USER mbbs
ENTRYPOINT ["/entrypoint.sh"]
CMD []
