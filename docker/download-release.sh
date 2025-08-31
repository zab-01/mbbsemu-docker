#!/usr/bin/env bash
set -euo pipefail
: "${MBBSEMU_VERSION:=latest}"
: "${MBBSEMU_HOME:=/app}"
URL_JSON=$(wget -qO- https://api.github.com/repos/mbbsemu/MBBSEmu/releases/${MBBSEMU_VERSION})
TARBALL_URL=$(echo "$URL_JSON" | grep -Eo '"browser_download_url":\s*"[^"]+linux[^"]+\.tar\.gz"' | head -n1 | cut -d '"' -f4)
wget -O /tmp/mbbsemu.tgz "${TARBALL_URL}"
tar -xzf /tmp/mbbsemu.tgz -C "${MBBSEMU_HOME}"
chmod +x "${MBBSEMU_HOME}/MBBSEmu"
rm -f /tmp/mbbsemu.tgz
