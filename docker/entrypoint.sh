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
  if ! getent group "${PGID}" >/dev/null 2>&1; then
    groupadd -g "${PGID}" mbbs 2>/dev/null || true
  fi
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

export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${RUNTIME_CACHE}"
export HOME="${CONFIG_ROOT}"

# -------- appsettings.json in /config --------
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

# force DB path to /config/mbbsemu.db if a release shipped a different value
sed -i 's#"File"[[:space:]]*:[[:space:]]*"[^"]*"#"File": "/config/mbbsemu.db"#g' "${APP_JSON}"

# -------- modules.json (default, or inline override) --------
if [[ -n "${MODULES_JSON_INLINE:-}" ]]; then
  printf "%s" "${MODULES_JSON_INLINE}" > "${MODULES_JSON}"
elif [[ ! -f "${MODULES_JSON}" ]]; then
  cat > "${MODULES_JSON}" <<EOF
{ "Modules": [ { "Identifier": "WCCMMUD", "Path": "${MODULES_DIR}/WCCMMUD" } ] }
EOF
fi
chown "${PUID}:${PGID}" "${MODULES_JSON}" || true

# -------- MajorMUD licensing (write BTURNO as *string*, pad to 8) --------
if [[ -n "${MUD_REG_NUMBER:-}" ]]; then
  # normalize to digits, then left-pad to 8 with zeros
  REG_RAW="$(printf "%s" "${MUD_REG_NUMBER}" | tr -cd '0-9')"
  REG_PAD="$(printf "%08d" "${REG_RAW:-0}")"
  if grep -q '"GSBL.BTURNO"' "${APP_JSON}"; then
    sed -E -i 's/"GSBL\.BTURNO":[^,}]+/"GSBL.BTURNO": "'"${REG_PAD}"'"/' "${APP_JSON}" || true
  else
    sed -E -i 's/("Application":[[:space:]]*\{)/\1\n    "GSBL.BTURNO": "'"${REG_PAD}"'",/' "${APP_JSON}" || true
  fi
fi

if [[ -n "${MUD_ACTIVATION_CODE:-}" ]]; then
  MSG="${MODULES_DIR}/WCCMMUD/WCCMMUD.MSG"
  if [[ -f "${MSG}" ]]; then
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

# -------- Launch from /config so any new files go to the volume --------
cd "${CONFIG_ROOT}"
if [[ "$(id -u)" -eq 0 ]]; then
  exec gosu "${PUID}:${PGID}" /app/MBBSEmu -S "${APP_JSON}" -C "${MODULES_JSON}"
else
  exec /app/MBBSEmu -S "${APP_JSON}" -C "${MODULES_JSON}"
fi
