#!/usr/bin/env bash
set -euo pipefail

: "${BBS_NAME:=MBBSEmu BBS}"
: "${TELNET_ENABLED:=true}"
: "${TELNET_IP:=0.0.0.0}"
: "${TELNET_PORT:=23}"
: "${TELNET_HEARTBEAT:=false}"
: "${RLOGIN_ENABLED:=false}"
: "${RLOGIN_IP:=0.0.0.0}"
: "${RLOGIN_PORT:=513}"
: "${RLOGIN_PER_MODULE:=false}"
: "${MAX_NODES:=100}"
: "${LOG_LEVEL:=Information}"
: "${DB_FILE:=/mbbsemu/config/mbbsemu.db}"
: "${MODULES_DIR:=/mbbsemu/config/modules}"
: "${MODULES_JSON:=/mbbsemu/config/modules.json}"
: "${APPSETTINGS_JSON:=/mbbsemu/config/appsettings.json}"
: "${ALLOW_LOCAL_LOGIN_ROUTINE:=true}"

mkdir -p /mbbsemu/config /mbbsemu/logs "${MODULES_DIR}"

if [[ -n "${MODULES_JSON_INLINE:-}" ]]; then
  echo "${MODULES_JSON_INLINE}" > "${MODULES_JSON}"
elif [[ ! -f "${MODULES_JSON}" && -n "${MODULES:-}" ]]; then
  {
    echo '{ "Modules": ['
    IFS=',' read -ra PAIRS <<< "${MODULES}"
    for i in "${!PAIRS[@]}"; do
      IFS=':' read -r ID PATH <<< "${PAIRS[$i]}"
      printf '  { "Identifier": "%s", "Path": "%s" }%s\n' \
        "$ID" "$PATH" $([[ $i -lt $((${#PAIRS[@]}-1)) ]] && echo ',' )
    done
    echo '] }'
  } > "${MODULES_JSON}"
fi

if [[ -n "${MMUD_LICENSE_KEY:-}" || -n "${MMUD_LICENSE_B64:-}" ]]; then
  mkdir -p /mbbsemu/config/licenses
fi
[[ -n "${MMUD_LICENSE_KEY:-}" ]] && echo -n "${MMUD_LICENSE_KEY}" > /mbbsemu/config/licenses/majormud.key
[[ -n "${MMUD_LICENSE_B64:-}" ]] && echo "${MMUD_LICENSE_B64}" | base64 -d > /mbbsemu/config/licenses/majormud.lic

if [[ ! -f "${APPSETTINGS_JSON}" ]]; then
  cat > "${APPSETTINGS_JSON}" <<JSON
{
  "Application": {
    "BBSName": "${BBS_NAME}",
    "MaxNodes": ${MAX_NODES},
    "LogLevel": "${LOG_LEVEL}",
    "DoLoginRoutine": ${ALLOW_LOCAL_LOGIN_ROUTINE}
  },
  "Telnet": {
    "Enabled": ${TELNET_ENABLED},
    "IP": "${TELNET_IP}",
    "Port": ${TELNET_PORT},
    "Heartbeat": ${TELNET_HEARTBEAT}
  },
  "Rlogin": {
    "Enabled": ${RLOGIN_ENABLED},
    "IP": "${RLOGIN_IP}",
    "Port": ${RLOGIN_PORT},
    "PortPerModule": ${RLOGIN_PER_MODULE}
  },
  "Database": {
    "File": "${DB_FILE}"
  }
}
JSON
fi

if [[ ! -x /app/MBBSEmu && "${USE_RELEASE_TARBALL:-false}" == "true" ]]; then
  /bin/bash /app/download-release.sh
fi

exec /app/MBBSEmu -C "${MODULES_JSON}"
