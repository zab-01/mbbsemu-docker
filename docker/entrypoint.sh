#!/usr/bin/env bash
set -euo pipefail

CONFIG_ROOT="${CONFIG_ROOT:-/config}"
APP_JSON_SRC="/app/appsettings.json"
APP_JSON="${CONFIG_ROOT}/appsettings.json"
MODULES_JSON="${CONFIG_ROOT}/modules.json"
MODULES_DIR="${CONFIG_ROOT}/modules"

mkdir -p "${MODULES_DIR}" "${CONFIG_ROOT}/logs"

# --- Create appsettings.json in /config (never copy back into /app) ---
if [[ ! -f "${APP_JSON}" ]]; then
  if [[ -f "${APP_JSON_SRC}" ]]; then
    install -m 0644 "${APP_JSON_SRC}" "${APP_JSON}"
  else
    # Fallback default if release doesn't ship one
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
  fi
fi

# Force DB path to /config/mbbsemu.db (handle any shipped variants)
sed -i "s#\"File\"[[:space:]]*:[[:space:]]*\"[^\"]*\"#\"File\": \"/config/mbbsemu.db\"#g" "${APP_JSON}"

# --- Modules config ---
if [[ -n "${MODULES_JSON_INLINE:-}" ]]; then
  printf "%s" "${MODULES_JSON_INLINE}" > "${MODULES_JSON}"
elif [[ ! -f "${MODULES_JSON}" ]]; then
  cat > "${MODULES_JSON}" <<EOF
{ "Modules": [ { "Identifier": "WCCMMUD", "Path": "${MODULES_DIR}/WCCMMUD" } ] }
EOF
fi

# --- MajorMUD licensing (optional) ---
if [[ -n "${MUD_REG_NUMBER:-}" ]]; then
  # update GSBL.BTURNO in appsettings.json (simple replace/add)
  if grep -q '"GSBL.BTURNO"' "${APP_JSON}"; then
    sed -E -i 's/"GSBL\.BTURNO":[^0-9]*[0-9]*/"GSBL.BTURNO": '"${MUD_REG_NUMBER}"'/' "${APP_JSON}" || true
  else
    # insert into Application section if missing
    sed -E -i 's/("Application":[[:space:]]*\{)/\1\n    "GSBL.BTURNO": '"${MUD_REG_NUMBER}"',/' "${APP_JSON}" || true
  fi
fi

if [[ -n "${MUD_ACTIVATION_CODE:-}" ]]; then
  MSG="${MODULES_DIR}/WCCMMUD/WCCMMUD.MSG"
  if [[ -f "${MSG}" ]]; then
    sed -i "s/{DEMO}/${MUD_ACTIVATION_CODE}/" "${MSG}" || true
  fi
fi

# --- First-run DB init: create directly in /config ---
if [[ ! -f "${CONFIG_ROOT}/mbbsemu.db" && -n "${SYSOP_PASSWORD:-}" ]]; then
  ( cd "${CONFIG_ROOT}" && /app/MBBSEmu -DBRESET "${SYSOP_PASSWORD}" ) || true
fi

# --- Run ---
exec /app/MBBSEmu -C "${MODULES_JSON}"
