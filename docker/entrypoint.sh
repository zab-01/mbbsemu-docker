#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[init] $*"; }

CONFIG_ROOT="${CONFIG_ROOT:-/config}"
APP_JSON_SRC="/app/appsettings.json"
APP_JSON="${CONFIG_ROOT}/appsettings.json"
MODULES_JSON="${CONFIG_ROOT}/modules.json"
MODULES_DIR="${CONFIG_ROOT}/modules"
RUNTIME_CACHE="${CONFIG_ROOT}/.net"

# Pull & run defaults
MODULES_AUTODETECT="${MODULES_AUTODETECT:-true}"
MODULES_FIX_CASE="${MODULES_FIX_CASE:-true}"
MODULES_RELAX_PERMS="${MODULES_RELAX_PERMS:-true}"
AUTO_FETCH_WCCMMUD="${AUTO_FETCH_WCCMMUD:-true}"
AUTO_ENABLE_WCCMMUD="${AUTO_ENABLE_WCCMMUD:-true}"

# Licensing
MUD_REG_NUMBER="${MUD_REG_NUMBER:-}"
MUD_ACTIVATION_CODE="${MUD_ACTIVATION_CODE:-}"
MUD_PLUS_ACTIVATION_CODE="${MUD_PLUS_ACTIVATION_CODE:-}"

# Host UID/GID (Unraid: 99/100)
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

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

# --- seed/ensure appsettings.json --------------------------------------------
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

# --- ensure Account.DefaultKeys includes PAYING -------------------------------
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

# --- GSBL.BTURNO --------------------------------------------------------------
if [[ -n "${MUD_REG_NUMBER}" ]]; then
  REG_RAW="$(printf '%s' "${MUD_REG_NUMBER}" | tr -cd '0-9')"
  # Use base-10 printf to avoid octal interpretation
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

# --- (optional) fetch WCCMMUD pack into /config/modules/WCCMMUD --------------
maybe_fetch_wccmmud() {
  local d="${MODULES_DIR}/WCCMMUD"
  [[ "${AUTO_FETCH_WCCMMUD}" == "true" ]] || return 0
  [[ -d "${d}" ]] && [[ -n "$(ls -A "${d}" 2>/dev/null)" ]] && return 0
  # No network fetch here (offline-friendly). If you want auto-download, wire it here.
  return 0
}
maybe_fetch_wccmmud

# --- patch activation lines ---------------------------------------------------
patch_activation() {
  local msg
  if [[ -n "${MUD_ACTIVATION_CODE}" ]]; then
    msg="${MODULES_DIR}/WCCMMUD/WCCMMUD.MSG"
    if [[ -f "${msg}" ]]; then
      local safe; safe="$(printf '%s' "${MUD_ACTIVATION_CODE}" | sed -e 's/[&/]/\\&/g')"
      sed -E -i "s/^ACTIVATE \{[^}]*\}.*/ACTIVATE {${safe}}/" "${msg}" || true
      log "Patched WCCMMUD activation"
    fi
  fi
  if [[ -n "${MUD_PLUS_ACTIVATION_CODE}" ]]; then
    msg="${MODULES_DIR}/WCCMMUD/WCCMMPLS.MSG"
    if [[ -f "${msg}" ]]; then
      local safe; safe="$(printf '%s' "${MUD_PLUS_ACTIVATION_CODE}" | sed -e 's/[&/]/\\&/g')"
      sed -E -i "s/^ACTIVATE \{[^}]*\}.*/ACTIVATE {${safe}}/" "${msg}" || true
      log "Patched WCCMMPLS activation"
    fi
  fi
}
patch_activation

# --- ensure modules.json exists (add WCCMMUD if dir present) -----------------
ensure_modules_json() {
  if [[ ! -f "${MODULES_JSON}" ]]; then
    if [[ "${MODULES_AUTODETECT}" == "true" && -d "${MODULES_DIR}/WCCMMUD" ]]; then
      log "Creating modules.json with WCCMMUD"
      printf '{ "Modules": [ { "Identifier": "WCCMMUD", "Path": "/config/modules/WCCMMUD" } ] }\n' > "${MODULES_JSON}"
    else
      log "Creating empty modules.json"
      printf '{ "Modules": [] }\n' > "${MODULES_JSON}"
    fi
    chown "${PUID}:${PGID}" "${MODULES_JSON}" 2>/dev/null || true
    chmod u+rw,go+r "${MODULES_JSON}" 2>/dev/null || true
  fi
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
if [[ "${MODULES_FIX_CASE}" == "true" && -d "${MODULES_DIR}/WCCMMUD" ]]; then
  d="${MODULES_DIR}/WCCMMUD"
  [[ -f "${d}/WCCMMUD.EXE"  && ! -e "${d}/wccmmud.EXE"  ]] && ln -sf "WCCMMUD.EXE"  "${d}/wccmmud.EXE"  || true
  [[ -f "${d}/WCCMMUTL.EXE" && ! -e "${d}/wccmmutl.EXE" ]] && ln -sf "WCCMMUTL.EXE" "${d}/wccmmutl.EXE" || true
fi

# --- first-run DB init with SYSOP_PASSWORD -----------------------------------
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

# --- optional: auto-enable WCCMMUD in DB (OFF by default) --------------------
auto_enable_wccmmud() {
  local db="${CONFIG_ROOT}/mbbsemu.db"
  [[ "${AUTO_ENABLE_WCCMMUD}" == "true" ]] || return 0
  [[ -f "$db" ]] || { log "DB not found; skip auto-enable"; return 0; }
  command -v sqlite3 >/dev/null 2>&1 || { log "sqlite3 not available; skip auto-enable"; return 0; }

  # Try a few common table/column names; ignore errors.
  for tbl in Modules Module ModuleConfig ModuleConfiguration TbModules; do
    if sqlite3 "$db" ".tables" | tr ' ' '\n' | grep -qi "^$tbl$"; then
      local cols; cols=$(sqlite3 "$db" "PRAGMA table_info($tbl);" | awk -F'|' '{print tolower($2)}')
      local idcol encol
      idcol=$(echo "$cols" | grep -E '^(identifier|moduleid|id)$' | head -1 || true)
      encol=$(echo "$cols" | grep -E '^(enabled|is_enabled|active)$' | head -1 || true)
      if [[ -n "${idcol:-}" && -n "${encol:-}" ]]; then
        sqlite3 "$db" "UPDATE $tbl SET $encol=1 WHERE lower($idcol)='wccmmud';" || true
        log "Auto-enabled WCCMMUD in DB table '$tbl' ($idcol/$encol)"
        return 0
      fi
    fi
  done
  log "Could not auto-enable WCCMMUD (unknown DB schema) — enable once via /SYS ENABLE WCCMMUD"
}
auto_enable_wccmmud

# --- start -------------------------------------------------------------------
cd "${CONFIG_ROOT}"
log "Starting MBBSEmu (Telnet 0.0.0.0:23, Rlogin 0.0.0.0:513)"
if [[ "$(id -u)" -eq 0 ]]; then
  exec gosu "${PUID}:${PGID}" /app/MBBSEmu -S "${APP_JSON}" -C "${MODULES_JSON}"
else
  exec /app/MBBSEmu -S "${APP_JSON}" -C "${MODULES_JSON}"
fi
