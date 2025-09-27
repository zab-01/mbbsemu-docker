#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[init] $*"; }

CONFIG_ROOT="${CONFIG_ROOT:-/config}"
APP_JSON_SRC="/app/appsettings.json"
APP_JSON="${CONFIG_ROOT}/appsettings.json"
MODULES_JSON="${CONFIG_ROOT}/modules.json"
MODULES_DIR="${CONFIG_ROOT}/modules"
WCCDIR="${MODULES_DIR}/WCCMMUD"
RUNTIME_CACHE="${CONFIG_ROOT}/.net"

# Behavior flags (pull & run defaults)
MODULES_AUTODETECT="${MODULES_AUTODETECT:-true}"
MODULES_FIX_CASE="${MODULES_FIX_CASE:-true}"
MODULES_RELAX_PERMS="${MODULES_RELAX_PERMS:-true}"

# Auto-fetch MajorMUD content if missing — SINGLE ZIP (v2)
AUTO_FETCH_WCCMMUD="${AUTO_FETCH_WCCMMUD:-true}"
WCCMMUD_URL_DEFAULT="https://download.mbbsemu.com/modules/WCCMMUD/WCCMMUD_1.11p_DOS_MBBSEmu_v2.zip"
# Back-compat: allow WCCMMUD_URL2 env to override if someone still sets it
WCCMMUD_URL="${WCCMMUD_URL:-${WCCMMUD_URL2:-$WCCMMUD_URL_DEFAULT}}"

# Optional DB nudge
AUTO_ENABLE_WCCMMUD="${AUTO_ENABLE_WCCMMUD:-false}" # off by default (schema varies)

# Host UID/GID (Unraid typical: 99/100)
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# Licensing envs (optional)
MUD_REG_NUMBER="${MUD_REG_NUMBER:-}"
MUD_ACTIVATION_CODE="${MUD_ACTIVATION_CODE:-}"
MUD_PLUS_ACTIVATION_CODE="${MUD_PLUS_ACTIVATION_CODE:-}"

# --- user / ownership ---------------------------------------------------------
if [[ "$(id -u)" -eq 0 ]]; then
  getent group "${PGID}" >/dev/null 2>&1 || groupadd -g "${PGID}" mbbs || true
  if id -u mbbs >/dev/null 2>&1; then
    usermod -o -u "${PUID}" -g "${PGID}" -d "${CONFIG_ROOT}" mbbs || true
  else
    useradd -o -u "${PUID}" -g "${PGID}" -M -d "${CONFIG_ROOT}" -s /usr/sbin/nologin mbbs || true
  fi
fi

mkdir -p "${MODULES_DIR}" "${CONFIG_ROOT}/logs" "${RUNTIME_CACHE}"
chmod u+rwx,go+rx "${CONFIG_ROOT}" 2>/dev/null || true
if [[ "$(id -u)" -eq 0 ]]; then
  chown -R "${PUID}:${PGID}" "${CONFIG_ROOT}" || true
fi

export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${RUNTIME_CACHE}"
export HOME="${CONFIG_ROOT}"

# --- appsettings.json ---------------------------------------------------------
if [[ ! -f "${APP_JSON}" ]]; then
  if [[ -f "${APP_JSON_SRC}" ]]; then
    log "Seeding appsettings.json from release"
    install -o "${PUID}" -g "${PGID}" -m 0644 "${APP_JSON_SRC}" "${APP_JSON}"
  else
    log "Creating default appsettings.json"
    cat > "${APP_JSON}" <<'JSON'
{
  "Application": {
    "BBSName": "MBBSEmu BBS",
    "MaxNodes": 100,
    "LogLevel": "Information",
    "DoLoginRoutine": true
  },
  "Telnet": { "Enabled": true, "IP": "0.0.0.0", "Port": 23, "Heartbeat": false },
  "Rlogin": { "Enabled": true, "IP": "0.0.0.0", "Port": 513, "PortPerModule": true },
  "Database": { "File": "/config/mbbsemu.db" }
}
JSON
    chown "${PUID}:${PGID}" "${APP_JSON}"
  fi
fi

# Force DB path to /config
sed -i 's#"File"[[:space:]]*:[[:space:]]*"[^"]*"#"File": "/config/mbbsemu.db"#g' "${APP_JSON}" || true

# Ensure Account.DefaultKeys contains PAYING
ensure_paying_key() {
  if command -v jq >/dev/null 2>&1; then
    tmp="$(mktemp)"
    jq '
      (.Account //= {}) |
      (.Account.DefaultKeys //= ["DEMO","NORMAL","USER"]) |
      (.Account.DefaultKeys |= ( . + ["PAYING"] | unique))
    ' "${APP_JSON}" > "${tmp}" && mv "${tmp}" "${APP_JSON}"
  else
    if ! grep -q '"Account"' "${APP_JSON}"; then
      sed -E -i 's/^\{/\{\n  "Account": { "DefaultKeys": ["DEMO","NORMAL","USER","PAYING"] },/' "${APP_JSON}" || true
    else
      grep -q '"PAYING"' "${APP_JSON}" || sed -E -i 's/("DefaultKeys"[[:space:]]*:[[:space:]]*\[[^]]*)\]/\1,"PAYING"]/' "${APP_JSON}" || true
    fi
  fi
  log 'Ensured Account.DefaultKeys contains "PAYING"'
}
ensure_paying_key

# Apply GSBL.BTURNO if provided (base-10 safe, keep leading zeros)
if [[ -n "${MUD_REG_NUMBER}" ]]; then
  REG_RAW="$(printf '%s' "${MUD_REG_NUMBER}" | tr -cd '0-9')"
  REG_PAD="$(printf '%08d' $((10#${REG_RAW:-0})))"
  if command -v jq >/dev/null 2>&1; then
    tmp="$(mktemp)"
    jq --arg reg "${REG_PAD}" '.["GSBL.BTURNO"]=$reg' "${APP_JSON}" > "${tmp}" && mv "${tmp}" "${APP_JSON}"
  else
    if grep -q '"GSBL.BTURNO"' "${APP_JSON}"; then
      sed -E -i 's/"GSBL\.BTURNO":[^,}]+/"GSBL.BTURNO": "'"${REG_PAD}"'"/' "${APP_JSON}" || true
    else
      sed -E -i '0,/\{/{s/\{/\{\n  "GSBL.BTURNO": "'"${REG_PAD}"'",/}' "${APP_JSON}" || true
    fi
  fi
  log "Applied GSBL.BTURNO=${REG_PAD}"
fi

# --- auto-fetch MajorMUD (single ZIP) if missing -----------------------------
fetch_and_merge_zip() {
  local url="$1"
  local t; t="$(mktemp -d)"
  log "Fetching: ${url}"
  curl -fL --retry 3 --retry-delay 2 -o "${t}/pkg.zip" "${url}"
  mkdir -p "${t}/x"
  unzip -oqq "${t}/pkg.zip" -d "${t}/x"
  mkdir -p "${WCCDIR}"
  shopt -s dotglob nullglob
  local src
  if [[ -d "${t}/x/WCCMMUD" ]]; then
    src="${t}/x/WCCMMUD"
  else
    src="${t}/x"
  fi
  cp -a "${src}/." "${WCCDIR}/"
  shopt -u dotglob nullglob
  rm -rf "${t}"
}

need_wccmmud() {
  [[ ! -d "${WCCDIR}" ]] && return 0
  [[ ! -f "${WCCDIR}/WCCMMUD.DLL" ]] && return 0
  [[ ! -f "${WCCDIR}/WCCMMUD.MSG" ]] && return 0
  return 1
}

maybe_fetch_wccmmud() {
  [[ "${AUTO_FETCH_WCCMMUD}" == "true" ]] || return 0
  if need_wccmmud; then
    log "WCCMMUD content missing; auto-fetch enabled"
    fetch_and_merge_zip "${WCCMMUD_URL}"
    if [[ -d "${WCCDIR}" ]]; then
      find "${WCCDIR}" -type d -exec chmod u+rwx,go+rx {} + 2>/dev/null || true
      find "${WCCDIR}" -type f -exec chmod u+rw,go+r {} + 2>/dev/null || true
      chown -R "${PUID}:${PGID}" "${WCCDIR}" 2>/dev/null || true
      local count; count=$(find "${WCCDIR}" -type f | wc -l | tr -d ' ')
      log "WCCMMUD ready (${count} files)"
    fi
  fi
}
maybe_fetch_wccmmud

# --- patch activation lines ---------------------------------------------------
patch_activation() {
  local msg
  # MajorMUD
  msg="${WCCDIR}/WCCMMUD.MSG"
  if [[ -n "${MUD_ACTIVATION_CODE}" && -f "${msg}" ]]; then
    local safe; safe="$(printf '%s' "${MUD_ACTIVATION_CODE}" | sed -e 's/[&/]/\\&/g')"
    sed -E -i "s/^ACTIVATE \{[^}]*\}.*/ACTIVATE {${safe}}/" "${msg}" || true
    log "Patched WCCMMUD activation"
  fi
  # MajorMUD Plus
  msg="${WCCDIR}/WCCMMPLS.MSG"
  if [[ -n "${MUD_PLUS_ACTIVATION_CODE}" && -f "${msg}" ]]; then
    local safe; safe="$(printf '%s' "${MUD_PLUS_ACTIVATION_CODE}" | sed -e 's/[&/]/\\&/g')"
    sed -E -i "s/^ACTIVATE \{[^}]*\}.*/ACTIVATE {${safe}}/" "${msg}" || true
    log "Patched WCCMMPLS activation"
  fi
}
patch_activation

# --- modules.json (create if missing; add WCCMMUD when present) --------------
ensure_modules_json() {
  if [[ -n "${MODULES_JSON_INLINE:-}" ]]; then
    printf "%s" "${MODULES_JSON_INLINE}" > "${MODULES_JSON}"
  elif [[ ! -f "${MODULES_JSON}" ]]; then
    if [[ -d "${WCCDIR}" ]]; then
      log "Creating modules.json with WCCMMUD"
      printf '{ "Modules": [ { "Identifier": "WCCMMUD", "Path": "/config/modules/WCCMMUD" } ] }\n' > "${MODULES_JSON}"
    else
      printf '{ "Modules": [] }\n' > "${MODULES_JSON}"
    fi
  fi
  chown "${PUID}:${PGID}" "${MODULES_JSON}" 2>/dev/null || true
}
ensure_modules_json

# --- normalize perms ----------------------------------------------------------
for f in "${APP_JSON}" "${MODULES_JSON}" "${CONFIG_ROOT}/mbbsemu.db"; do
  [ -e "$f" ] && chmod u+rw,go+r "$f" 2>/dev/null || true
done

if [[ -d "${MODULES_DIR}" && "${MODULES_RELAX_PERMS}" == "true" ]]; then
  log "Normalizing permissions under ${MODULES_DIR}"
  find "${MODULES_DIR}" -type d -exec chmod u+rwx,go+rx {} + 2>/dev/null || true
  find "${MODULES_DIR}" -type f -exec chmod u+rw,go+r {} + 2>/dev/null || true
fi

if [[ "${MODULES_FIX_CASE}" == "true" && -d "${WCCDIR}" ]]; then
  d="${WCCDIR}"
  [[ -f "${d}/WCCMMUD.EXE"  && ! -e "${d}/wccmmud.EXE"  ]] && ln -sf "WCCMMUD.EXE"  "${d}/wccmmud.EXE"  || true
  [[ -f "${d}/WCCMMUTL.EXE" && ! -e "${d}/wccmmutl.EXE" ]] && ln -sf "WCCMMUTL.EXE" "${d}/wccmmutl.EXE" || true
fi

# --- first-run DB init --------------------------------------------------------
if [[ ! -f "${CONFIG_ROOT}/mbbsemu.db" && -n "${SYSOP_PASSWORD:-}" ]]; then
  log "Initializing database with provided SYSOP_PASSWORD"
  chmod u+rw,go+r "${APP_JSON}" 2>/dev/null || true
  if [[ "$(id -u)" -eq 0 ]]; then
    gosu "${PUID}:${PGID}" bash -lc "(cd '${CONFIG_ROOT}' && /app/MBBSEmu -DBRESET '${SYSOP_PASSWORD}')"
  else
    (cd "${CONFIG_ROOT}" && /app/MBBSEmu -DBRESET "${SYSOP_PASSWORD}")
  fi
  [ -f "${CONFIG_ROOT}/mbbsemu.db" ] && chmod u+rw,go+r "${CONFIG_ROOT}/mbbsemu.db" 2>/dev/null || true
fi

# --- optional: auto-enable in DB (best effort; schema varies) -----------------
if [[ "${AUTO_ENABLE_WCCMMUD}" == "true" && -f "${CONFIG_ROOT}/mbbsemu.db" && -x "$(command -v sqlite3)" ]]; then
  for tbl in Modules Module ModuleConfig ModuleConfiguration TbModules; do
    if sqlite3 "${CONFIG_ROOT}/mbbsemu.db" ".tables" | tr ' ' '\n' | grep -qi "^$tbl$"; then
      cols="$(sqlite3 "${CONFIG_ROOT}/mbbsemu.db" "PRAGMA table_info($tbl);" | awk -F'|' '{print tolower($2)}')"
      idcol="$(echo "$cols" | grep -E '^(identifier|moduleid|id)$' | head -1 || true)"
      encol="$(echo "$cols" | grep -E '^(enabled|is_enabled|active)$' | head -1 || true)"
      if [[ -n "${idcol:-}" && -n "${encol:-}" ]]; then
        sqlite3 "${CONFIG_ROOT}/mbbsemu.db" "UPDATE $tbl SET $encol=1 WHERE lower($idcol)='wccmmud';" && log "Auto-enabled WCCMMUD in DB ($tbl)"
        break
      fi
    fi
  done
fi

# --- start -------------------------------------------------------------------
cd "${CONFIG_ROOT}"
log "Starting MBBSEmu (Telnet 0.0.0.0:23, Rlogin 0.0.0.0:513)"
if [[ "$(id -u)" -eq 0 ]]; then
  exec gosu "${PUID}:${PGID}" /app/MBBSEmu -S "${APP_JSON}" -C "${MODULES_JSON}"
else
  exec /app/MBBSEmu -S "${APP_JSON}" -C "${MODULES_JSON}"
fi
