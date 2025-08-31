#!/usr/bin/env bash
set -euo pipefail

: "${MBBSEMU_VERSION:=latest}"

if [[ "$MBBSEMU_VERSION" == "latest" ]]; then
  API_URL="https://api.github.com/repos/mbbsemu/MBBSEmu/releases/latest"
else
  API_URL="https://api.github.com/repos/mbbsemu/MBBSEmu/releases/tags/${MBBSEMU_VERSION}"
fi

JSON=$(curl -fsSL "$API_URL")
ASSET_URL=$(echo "$JSON" \
  | grep -Eo '"browser_download_url":\s*"[^"]+"' \
  | cut -d'"' -f4 \
  | grep -i 'linux-x64.*\.zip$' \
  | head -n1)

if [[ -z "$ASSET_URL" ]]; then
  echo "No linux-x64 asset found" >&2; exit 1
fi

curl -fsSL "$ASSET_URL" -o /tmp/mbbsemu.zip
unzip -q /tmp/mbbsemu.zip -d /app
chmod +x /app/MBBSEmu
rm /tmp/mbbsemu.zip
