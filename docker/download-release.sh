#!/usr/bin/env bash
set -euo pipefail

: "${MBBSEMU_VERSION:=latest}"
: "${MBBSEMU_HOME:=/app}"

if [[ "$MBBSEMU_VERSION" == "latest" ]]; then
  API_URL="https://api.github.com/repos/mbbsemu/MBBSEmu/releases/latest"
else
  API_URL="https://api.github.com/repos/mbbsemu/MBBSEmu/releases/tags/${MBBSEMU_VERSION}"
fi

JSON="$(curl -fsSL "$API_URL")"
ASSET_URL="$(printf "%s" "$JSON" \
  | grep -Eo '"browser_download_url":\s*"[^"]+"' \
  | cut -d'"' -f4 \
  | grep -Ei 'linux.*x64.*\.(zip|tar\.gz)$' \
  | head -n1 || true)"

if [[ -z "${ASSET_URL:-}" ]]; then
  echo "ERROR: No linux x64 asset found for ${MBBSEMU_VERSION}" >&2
  exit 1
fi

TMP=/tmp/mbbsemu_asset
rm -f "$TMP" "$TMP".*

curl -fsSL "$ASSET_URL" -o "$TMP"

# extract into /app and NEVER prompt (idempotent)
if [[ "$ASSET_URL" =~ \.zip$ ]]; then
  unzip -oqq "$TMP" -d "$MBBSEMU_HOME"
else
  tar -xzf "$TMP" -C "$MBBSEMU_HOME" --overwrite
fi

chmod +x "$MBBSEMU_HOME/MBBSEmu" || true
rm -f "$TMP"
