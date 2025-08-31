# MBBSEmu – Pull & Run (GHCR)

Turn-key Docker image for MBBSEmu with all config externalized.

## Run
```bash
git clone https://github.com/YOUROWNER/mbbsemu-dockerized.git
cd mbbsemu-dockerized
cp .env.example .env    # optional
mkdir -p mbbsemu/config/modules
docker compose up -d
# telnet localhost 2323
