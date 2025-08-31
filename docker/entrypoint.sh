#!/usr/bin/env bash
set -euo pipefail

CONFIG_ROOT="${CONFIG_ROOT:-/config}"
APP_JSON_SRC="/app/appsettings.json"
APP_JSON="${CONFIG_ROOT}/appsettings.json"
MODULES_JSON="${CONFIG_ROOT}/modules.json"
MODULES_DIR="${CONFIG_ROOT}/modules"
RUNTIME_CACHE="${CONFIG_ROOT}/.net"

# -------- PUID / PGID handling (drop privileges) --------
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

if [[ "$(id -u)" -eq 0 ]]; then
  # group
  if ! getent group "${PGID}" >/dev/null 2>&1; then
    groupadd -g "${PGID}" mbbs 2>/dev/null || true
  fi
  # user with requested uid/gid; set home to /config
  if id -u mbbs >/dev/null 2>&1; then
    usermod -o -u "${PUID}" -g "${PGID}" -d "${CONFIG_ROOT}" mbbs || true
  else
    useradd -o -u "${PUID}" -g "${PGID}" -M -d "${CONFIG_ROOT}" -s /usr/sbin/nologin mbbs || true
  fi
fi

mkdir -p "${MODULES_DIR}" "${CONFIG_ROOT}/logs" "${RUNTIME_CACHE}"
chown -R "${PUID}:${PGID}" "${CONFIG_ROOT}" || true

# ensure .NET bundle cache points at a writable dir
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${RUNTIME_CACHE}"
export HOME="${CONFIG_ROOT}"

# -------- Create appsettings.json in /config (never write to /app) --------
if [[ ! -f "${APP_JSON}" ]]; then
  if [[ -f "${APP_JSON_SRC}" ]]; then
    install -o "${PUID}" -g "${PGID}" -m 0644 "${APP_JSON_SRC}" "${APP_JSON}"
  else
    cat > "${APP_JSON}" <<'JSON'
{
  "Application": {
    "BBSName": "MBBSEmu BBS",
    "MaxNodes": 100,
    "LogLevel": "Information",
    "DoLoginRoutine": true
  },
  "Telnet": { "Enabled": true, "IP": "0.0.0.0", "Port": 23, "Heartbeat": false },
  "Rlogin": { "Enabled": false, "IP": "0.0.0.0", "Port": 513, "PortPerModule": false },
  "Database": { "File": "/config/mbbsemu.db" }
}
JSON
    chown "${PUID}:${PGID}" "${APP_JSON}"
  fi
fi

# force DB path to /config/mbbsemu.db if release shipped a different value
sed -i 's#"File"[[:space:]]*:[[:space:]]*"[^"]*"#"File": "/config/mbbsemu.db"#g' "${APP_JSON}"

# -------- modules.json (default) --------
if [[ -n "${MODULES_JSON_INLINE:-}" ]]; then
  printf "%s" "${MODULES_JSON_INLINE}" > "${MODULES_JSON}"
elif [[ ! -f "${MODULES_JSON}" ]]; then
  cat > "${MODULES_JSON}" <<EOF
{ "Modules": [ { "Identifier": "WCCMMUD", "Path": "${MODULES_DIR}/WCCMMUD" } ] }
EOF
fi
chown "${PUID}:${PGID}" "${MODULES_JSON}" || true

# -------- MajorMUD licensing (optional) --------
if [[ -n "${MUD_REG_NUMBER:-}" ]]; then
  if grep -q '"GSBL.BTURNO"' "${APP_JSON}"; then
    sed -E -i 's/"GSBL\.BTURNO":[^0-9]*[0-9]*/"GSBL.BTURNO": '"${MUD_REG_NUMBER}"'/' "${APP_JSON}" || true
  else
    sed -E -i 's/("Application":[[:space:]]*\{)/\1\n    "GSBL.BTURNO": '"${MUD_REG_NUMBER}"',/' "${APP_JSON}" || true
  fi
fi

if [[ -n "${MUD_ACTIVATION_CODE:-}" ]]; then
  MSG="${MODULES_DIR}/WCCMMUD/WCCMMUD.MSG"
  if [[ -f "${MSG}" ]]; then
    # replace only the placeholder token if present
    sed -i "s/{DEMO}/${MUD_ACTIVATION_CODE}/" "${MSG}" || true
  fi
fi

# -------- First-run DB init directly in /config (as unprivileged) --------
if [[ ! -f "${CONFIG_ROOT}/mbbsemu.db" && -n "${SYSOP_PASSWORD:-}" ]]; then
  if [[ "$(id -u)" -eq 0 ]]; then
    gosu "${PUID}:${PGID}" bash -lc "(cd '${CONFIG_ROOT}' && /app/MBBSEmu -DBRESET '${SYSOP_PASSWORD}')"
  else
    (cd "${CONFIG_ROOT}" && /app/MBBSEmu -DBRESET "${SYSOP_PASSWORD}")
  fi
fi

# -------- Launch as the unprivileged user --------
if [[ "$(id -u)" -eq 0 ]]; then
  exec gosu "${PUID}:${PGID}" /app/MBBSEmu -C "${MODULES_JSON}"
else
  exec /app/MBBSEmu -C "${MODULES_JSON}"
fi
