#!/usr/bin/env bash
set -euo pipefail

: "${MBBSEMU_VERSION:=latest}"
: "${MBBSEMU_HOME:=/app}"

if [ "$MBBSEMU_VERSION" = "latest" ]; then
  API_URL="https://api.github.com/repos/mbbsemu/MBBSEmu/releases/latest"
else
  API_URL="https://api.github.com/repos/mbbsemu/MBBSEmu/releases/tags/${MBBSEMU_VERSION}"
fi

JSON=$(curl -fsSL "$API_URL")
TARBALL_URL=$(printf "%s" "$JSON" | grep -Eo '"browser_download_url":\s*"[^"]+linux[^"]+\.tar\.gz"' | head -n1 | cut -d '"' -f4)

if [ -z "${TARBALL_URL:-}" ]; then
  echo "Could not locate a linux tarball in release ${MBBSEMU_VERSION}" >&2
  exit 1
fi

echo "Downloading: $TARBALL_URL"
curl -fsSL "$TARBALL_URL" -o /tmp/mbbsemu.tgz
tar -xzf /tmp/mbbsemu.tgz -C "${MBBSEMU_HOME}"
chmod +x "${MBBSEMU_HOME}/MBBSEmu"
rm -f /tmp/mbbsemu.tgz
