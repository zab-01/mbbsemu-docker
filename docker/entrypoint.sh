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
# ensure the directory itself is traversable/readable
chmod u+rwx,go+rx "${CONFIG_ROOT}" 2>/dev/null || true
if [[ "$(id -u)" -eq 0 ]]; then
  chown -R "${PUID}:${PGID}" "${CONFIG_ROOT}" || true
fi

# .NET single-file cache in /config
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

# --- ensure Account.DefaultKeys includes "PAYING" -----------------------------
ensure_paying_key() {
  if command -v jq >/dev/null 2>&1; then
    tmp="$(mktemp)"
    jq '
      (.Account //= {}) |
      (.Account.DefaultKeys //= ["DEMO","NORMAL","USER"]) |
      (.Account.DefaultKeys |= ( . + ["PAYING"] | unique))
    ' "${APP_JSON}" > "${tmp}" && mv "${tmp}" "${APP_JSON}"
  else
    # minimal non-jq fallback: inject Account if missing, and ensure PAYING appears once
    if ! grep -q '"Account"' "${APP_JSON}"; then
      sed -E -i 's/^\{/\{\n  "Account": { "DefaultKeys": ["DEMO","NORMAL","USER","PAYING"] },/' "${APP_JSON}" || true
    else
      grep -q '"PAYING"' "${APP_JSON}" || sed -E -i 's/("DefaultKeys"[[:space:]]*:[[:space:]]*\[[^]]*)\]/\1,"PAYING"]/' "${APP_JSON}" || true
    fi
  fi
  log 'Ensured Account.DefaultKeys contains "PAYING"'
}
ensure_paying_key

# --- licensing (GSBL.BTURNO as STRING at TOP-LEVEL) --------------------------
if [[ -n "${MUD_REG_NUMBER:-}" ]]; then
  REG_RAW="$(printf "%s" "${MUD_REG_NUMBER}" | tr -cd '0-9')"
  REG_PAD="$(printf "%08d" "${REG_RAW:-0}")"
  if command -v jq >/dev/null 2>&1; then
    tmp="$(mktemp)"
    jq --arg reg "${REG_PAD}" '.["GSBL.BTURNO"]=$reg' "${APP_JSON}" > "${tmp}" && mv "${tmp}" "${APP_JSON}"
  else
    # fallback: if key exists anywhere, replace; else insert near top as top-level key
    if grep -q '"GSBL.BTURNO"' "${APP_JSON}"; then
      sed -E -i 's/"GSBL\.BTURNO":[^,}]+/"GSBL.BTURNO": "'"${REG_PAD}"'"/' "${APP_JSON}" || true
    else
      sed -E -i '0,/\{/{s/\{/\{\n  "GSBL.BTURNO": "'"${REG_PAD}"'",/}' "${APP_JSON}" || true
    fi
  fi
  log "Applied GSBL.BTURNO=${REG_PAD} from env"
fi

# --- safer activation patch (replace WHOLE LINE) -----------------------------
if [[ -n "${MUD_ACTIVATION_CODE:-}" ]]; then
  MSG="${MODULES_DIR}/WCCMMUD/WCCMMUD.MSG"
  if [[ -f "${MSG}" ]]; then
    safe=$(printf "%s" "${MUD_ACTIVATION_CODE}" | sed -e 's/[&/]/\\&/g')
    sed -E -i "s/^ACTIVATE \{[^}]*\}.*/ACTIVATE {${safe}}/" "${MSG}" || true
    log "Injected MajorMUD activation code (ACTIVATE line)"
  fi
else
  MSG="${MODULES_DIR}/WCCMMUD/WCCMMUD.MSG"
  [[ -f "${MSG}" ]] && sed -E -i 's/^ACTIVATE \{[^}]*\}.*/ACTIVATE {DEMO}/' "${MSG}" || true
fi

# --- modules.json (auto-add WCCMMUD if present) ------------------------------
if [[ -n "${MODULES_JSON_INLINE:-}" ]]; then
  printf "%s" "${MODULES_JSON_INLINE}" > "${MODULES_JSON}"
elif [[ ! -f "${MODULES_JSON}" && "${MODULES_AUTODETECT}" == "true" ]]; then
  if [[ -d "${MODULES_DIR}/WCCMMUD" ]]; then
    log "Auto-adding WCCMMUD to modules.json"
    printf '{ "Modules": [ { "Identifier": "WCCMMUD", "Path": "/config/modules/WCCMMUD" } ] }\n' > "${MODULES_JSON}"
  else
    printf '{ "Modules": [] }\n' > "${MODULES_JSON}"
  fi
fi
chown "${PUID}:${PGID}" "${MODULES_JSON}" 2>/dev/null || true

# --- normalize perms on top-level config files -------------------------------
for f in "${APP_JSON}" "${MODULES_JSON}" "${CONFIG_ROOT}/mbbsemu.db"; do
  [ -e "$f" ] && chmod u+rw,go+r "$f" 2>/dev/null || true
done

# --- perms and lowercase shims for modules -----------------------------------
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

# --- start -------------------------------------------------------------------
cd "${CONFIG_ROOT}"
log "Starting MBBSEmu (Telnet 0.0.0.0:23, Rlogin 0.0.0.0:513)"
if [[ "$(id -u)" -eq 0 ]]; then
  exec gosu "${PUID}:${PGID}" /app/MBBSEmu -S "${APP_JSON}" -C "${MODULES_JSON}"
else
  exec /app/MBBSEmu -S "${APP_JSON}" -C "${MODULES_JSON}"
fi