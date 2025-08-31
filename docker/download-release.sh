#!/usr/bin/env bash
set -euo pipefail

: "${MBBSEMU_VERSION:=latest}"
: "${MBBSEMU_HOME:=/app}"
: "${GH_TOKEN:=}"
: "${MBBSEMU_ASSET_URL:=}"   # manual override if needed

curl_api() {
  local url="$1"
  if [[ -n "$GH_TOKEN" ]]; then
    curl -fsSL -H "Authorization: Bearer ${GH_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" "$url"
  else
    curl -fsSL "$url"
  fi
}

# If caller gave us a direct asset URL, use it.
if [[ -n "$MBBSEMU_ASSET_URL" ]]; then
  ASSET_URL="$MBBSEMU_ASSET_URL"
else
  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  case "$arch" in
    amd64|x86_64) patt='linux.*(x64|amd64).*' ;;
    arm64|aarch64) patt='linux.*(arm64|aarch64).*' ;;
    *) patt='linux.*' ;;
  esac

  api_url="https://api.github.com/repos/mbbsemu/MBBSEmu/releases"
  [[ "$MBBSEMU_VERSION" == "latest" ]] && api_url+="/latest" || api_url+="/tags/${MBBSEMU_VERSION}"

  echo "==> Querying ${api_url}"
  json="$(curl_api "$api_url")" || { echo "ERROR: GitHub API request failed"; exit 1; }

  echo "==> Looking for asset matching: ${patt} and extension (zip|tar.gz|tgz|tar.xz)"
  ASSET_URL="$(jq -r --arg patt "$patt" '
      (.assets // [])[]
      | select(.name|test($patt;"i"))
      | select(.name|test("\\.(zip|tar\\.gz|tgz|tar\\.xz)$";"i"))
      | .browser_download_url
    ' <<<"$json" | head -n1)"

  if [[ -z "${ASSET_URL:-}" || "${ASSET_URL}" == "null" ]]; then
    echo "ERROR: No matching asset found."
    echo "Assets available:"
    jq -r '(.assets // [])[] | .name' <<<"$json" | sed 's/^/  - /'
    echo "You may set build-arg MBBSEMU_ASSET_URL to override."
    exit 1
  fi
fi

echo "==> Downloading asset: $ASSET_URL"
tmp=/tmp/mbbsemu_asset
rm -f "$tmp" "$tmp".*

curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$ASSET_URL" || { echo "ERROR: download failed"; exit 1; }

# Extract into /app, never prompt
echo "==> Extracting into ${MBBSEMU_HOME}"
case "$ASSET_URL" in
  *.zip)     unzip -oqq "$tmp" -d "$MBBSEMU_HOME" ;;
  *.tar.gz|*.tgz) tar -xzf "$tmp" -C "$MBBSEMU_HOME" --overwrite ;;
  *.tar.xz)  tar -xJf "$tmp" -C "$MBBSEMU_HOME" --overwrite ;;
  *) echo "ERROR: unknown archive type: $ASSET_URL"; exit 1 ;;
esac

chmod +x "${MBBSEMU_HOME}/MBBSEmu" || true
rm -f "$tmp"
echo "==> Done."
