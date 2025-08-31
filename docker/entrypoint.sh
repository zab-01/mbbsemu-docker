#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[init] $*"; }

CONFIG_ROOT="${CONFIG_ROOT:-/config}"
APP_JSON_SRC="/app/appsettings.json"
APP_JSON="${CONFIG_ROOT}/appsettings.json"
MODULES_JSON="${CONFIG_ROOT}/modules.json"
MODULES_DIR="${CONFIG_ROOT}/modules"
RUNTIME_CACHE="${CONFIG_ROOT}/.net"

# Behavior toggles (default ON for 'pull & play')
MODULES_AUTODETECT="${MODULES_AUTODETECT:-true}"
MODULES_FIX_CASE="${MODULES_FIX_CASE:-true}"
MODULES_RELAX_PERMS="${MODULES_RELAX_PERMS:-true}"

# -------- PUID / PGID & user --------
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

if [[ "$(id -u)" -eq 0 ]]; then
  getent group "${PGID}" >/dev/null 2>&1 || groupadd -g "${PGID}" mbbs || true
  if id -u mbbs >/dev/null 2>&1; then
    usermod -o -u "${PUID}" -g "${PGID}" -d "${CONFIG_ROOT}" mbbs || true
  else
    useradd -o -u "${PUID}" -g "${PGID}" -M -d "${CONFIG_ROOT}" -s /usr/sbin/nologin mbbs || true
  fi
fi

mkdir -p "${MODULES_DIR}" "${CONFIG_ROOT}/logs" "${RUNTIME_CACHE}"
if [[ "$(id -u)" -eq 0 ]]; then
  chown -R "${PUID}:${PGID}" "${CONFIG_ROOT}" || true
fi

# .NET single-file bundle cache under /config
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${RUNTIME_CACHE}"
export HOME="${CONFIG_ROOT}"

# -------- appsettings.json in /config --------
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
  "Rlogin": { "Enabled": true, "IP": "0.0.0.0", "Port": 513, "PortPerModule": false },
  "Database": { "File": "/config/mbbsemu.db" }
}
JSON
    chown "${PUID}:${PGID}" "${APP_JSON}"
  fi
fi

# Force DB path to /config/mbbsemu.db (some releases differ)
sed -i 's#"File"[[:space:]]*:[[:space:]]*"[^"]*"#"File": "/config/mbbsemu.db"#g' "${APP_JSON}" || true

# -------- Apply MajorMUD license (env -> JSON string) --------
if [[ -n "${MUD_REG_NUMBER:-}" ]]; then
  REG_RAW="$(printf "%s" "${MUD_REG_NUMBER}" | tr -cd '0-9')"
  REG_PAD="$(printf "%08d" "${REG_RAW:-0}")"
  if grep -q '"GSBL.BTURNO"' "${APP_JSON}"; then
    sed -E -i 's/"GSBL\.BTURNO":[^,}]+/"GSBL.BTURNO": "'"${REG_PAD}"'"/' "${APP_JSON}" || true
  else
    sed -E -i 's/("Application":[[:space:]]*\{)/\1\n    "GSBL.BTURNO": "'"${REG_PAD}"'",/' "${APP_JSON}" || true
  fi
  log "Applied GSBL.BTURNO=${REG_PAD} from env"
fi

# Optional message-file activation code
if [[ -n "${MUD_ACTIVATION_CODE:-}" ]]; then
  MSG="${MODULES_DIR}/WCCMMUD/WCCMMUD.MSG"
  if [[ -f "${MSG}" ]]; then
    sed -i "s/{DEMO}/${MUD_ACTIVATION_CODE}/" "${MSG}" || true
    log "Injected MajorMUD activation code"
  fi
fi

# -------- Build modules.json if missing (auto-detect) --------
if [[ -n "${MODULES_JSON_INLINE:-}" ]]; then
  printf "%s" "${MODULES_JSON_INLINE}" > "${MODULES_JSON}"
elif [[ ! -f "${MODULES_JSON}" && "${MODULES_AUTODETECT}" == "true" ]]; then
  mm_dir="${MODULES_DIR}/WCCMMUD"
  if [[ -d "${mm_dir}" ]]; then
    log "Auto-enabling WCCMMUD at ${mm_dir}"
    {
      echo '{ "Modules": ['
      echo '  { "Identifier": "WCCMMUD", "Path": "'"${mm_dir}"'" }'
      echo '] }'
    } > "${MODULES_JSON}"
  else
    log "No modules detected; starting with none"
    echo '{ "Modules": [] }' > "${MODULES_JSON}"
  fi
fi
chown "${PUID}:${PGID}" "${MODULES_JSON}" 2>/dev/null || true

# -------- Make module files readable & fix Linux case sensitivity --------
if [[ -d "${MODULES_DIR}" ]]; then
  if [[ "${MODULES_RELAX_PERMS}" == "true" ]]; then
    log "Relaxing permissions under ${MODULES_DIR}"
    chmod -R u+rwX,go+rX "${MODULES_DIR}" || true
  fi
  if [[ "${MODULES_FIX_CASE}" == "true" ]]; then
    # iterate each module directory, create lowercase symlinks for UPPERCASE files
    for d in "${MODULES_DIR}"/*/ ; do
      [[ -d "$d" ]] || continue
      for f in "$d"* ; do
        [[ -e "$f" ]] || continue
        base="$(basename "$f")"
        lower="${base,,}"                # bash lowercase
        if [[ "$base" != "$lower" && ! -e "$d$lower" ]]; then
          ln -s "$base" "$d$lower" 2>/dev/null || true
        fi
      done
    done
  fi
fi

# -------- First-run DB init directly in /config (as unprivileged) --------
if [[ ! -f "${CONFIG_ROOT}/mbbsemu.db" && -n "${SYSOP_PASSWORD:-}" ]]; then
  log "Initializing database with provided SYSOP_PASSWORD"
  if [[ "$(id -u)" -eq 0 ]]; then
    gosu "${PUID}:${PGID}" bash -lc "(cd '${CONFIG_ROOT}' && /app/MBBSEmu -DBRESET '${SYSOP_PASSWORD}')"
  else
    (cd "${CONFIG_ROOT}" && /app/MBBSEmu -DBRESET "${SYSOP_PASSWORD}")
  fi
fi

# -------- Launch from /config --------
cd "${CONFIG_ROOT}"
log "Starting MBBSEmu (Telnet 0.0.0.0:23, Rlogin 0.0.0.0:513)"
if [[ "$(id -u)" -eq 0 ]]; then
  exec gosu "${PUID}:${PGID}" /app/MBBSEmu -S "${APP_JSON}" -C "${MODULES_JSON}"
else
  exec /app/MBBSEmu -S "${APP_JSON}" -C "${MODULES_JSON}"
fi
