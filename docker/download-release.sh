#!/usr/bin/env bash
set -euo pipefail

: "${MBBSEMU_VERSION:=latest}"
: "${MBBSEMU_HOME:=/app}"

# map architecture -> asset pattern
arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$arch" in
  amd64|x86_64) asset_re='linux.*(x64|amd64).*\.(zip|tar\.gz)$' ;;
  arm64|aarch64) asset_re='linux.*(arm64|aarch64).*\.(zip|tar\.gz)$' ;;
  *) asset_re='linux.*\.(zip|tar\.gz)$' ;;
esac

if [[ "$MBBSEMU_VERSION" == "latest" ]]; then
  api_url="https://api.github.com/repos/mbbsemu/MBBSEmu/releases/latest"
else
  api_url="https://api.github.com/repos/mbbsemu/MBBSEmu/releases/tags/${MBBSEMU_VERSION}"
fi

json="$(curl -fsSL "$api_url")"

asset_url="$(printf "%s" "$json" \
  | grep -Eo '"browser_download_url":\s*"[^"]+"' \
  | cut -d'"' -f4 \
  | grep -E "${asset_re}" \
  | head -n1 || true)"

if [[ -z "${asset_url:-}" ]]; then
  echo "ERROR: No asset matching ${asset_re} for ${MBBSEMU_VERSION}" >&2
  exit 1
fi

tmp=/tmp/mbbsemu_asset
rm -f "$tmp" "$tmp".*

curl -fsSL "$asset_url" -o "$tmp"

# extract into /app and NEVER prompt (idempotent)
if [[ "$asset_url" =~ \.zip$ ]]; then
  unzip -oqq "$tmp" -d "$MBBSEMU_HOME"
else
  tar -xzf "$tmp" -C "$MBBSEMU_HOME" --overwrite
fi

chmod +x "$MBBSEMU_HOME/MBBSEmu" || true
rm -f "$tmp"
