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
AUTO_FETCH_WCCMMUD="${AUTO_FETCH_WCCMMUD:-true}"       # fetch module zip if missing
AUTO_ENABLE_WCCMMUD="${AUTO_ENABLE_WCCMMUD:-false}"    # best-effort DB flip on

# Default licensing (can be overridden by env)
MUD_REG_NUMBER="${MUD_REG_NUMBER:-12345678}"
MUD_ACTIVATION_CODE="${MUD_ACTIVATION_CODE:-dlhbdfhjlnp}"       # MajorMUD
MUD_PLUS_ACTIVATION_CODE="${MUD_PLUS_ACTIVATION_CODE:-XVDXBUATGZ}"  # MajorMUD Plus

# Add-on codes for reg 12345678 (1..9). Override with env MUD_ADDON_n to customize.
declare -A ADDON
ADDON[1]="${MUD_ADDON_1:-EWCTEUBYUWZZTVWY}"
ADDON[2]="${MUD_ADDON_2:-EWTUEVBYXX}"
ADDON[3]="${MUD_ADDON_3:-FVXYFUUZTZ}"
ADDON[4]="${MUD_ADDON_4:-UVZZFUFUVX}"
ADDON[5]="${MUD_ADDON_5:-FVYXEVAWZU}"
ADDON[6]="${MUD_ADDON_6:-BUWZEVGYYW}"
ADDON[7]="${MUD_ADDON_7:-FUXZFVGWUY}"
ADDON[8]="${MUD_ADDON_8:-ETUUEVGYTZ}"
ADDON[9]="${MUD_ADDON_9:-EVTVEVGYZT}"

# Host UID/GID (Unraid commonly 99/100)
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
# ensure directory traversal works for mounted /config on Unraid perms
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
    if ! grep -q '"Account"' "${APP_JSON}"; then
      sed -E -i 's/^\{/\{\n  "Account": { "DefaultKeys": ["DEMO","NORMAL","USER","PAYING"] },/' "${APP_JSON}" || true
    else
      grep -q '"PAYING"' "${APP_JSON}" || sed -E -i 's/("DefaultKeys"[[:space:]]*:[[:space:]]*\[[^]]*)\]/\1,"PAYING"]/' "${APP_JSON}" || true
    fi
  fi
  log 'Ensured Account.DefaultKeys contains "PAYING"'
}
ensure_paying_key

# --- licensing (GSBL.BTURNO as STRING) ---------------------------------------
if [[ -n "${MUD_REG_NUMBER:-}" ]]; then
  # strip non-digits; pad to 8 in base-10 (avoid octal)
  REG_RAW="$(printf "%s" "${MUD_REG_NUMBER}" | tr -cd '0-9')"
  if [[ -z "${REG_RAW}" ]]; then REG_RAW="0"; fi
  REG_PAD="$(printf "%08d" "$((10#${REG_RAW}))")"
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

# --- fetch MajorMUD module if missing ----------------------------------------
maybe_fetch_wccmmud() {
  local d="${MODULES_DIR}/WCCMMUD"
  [[ "${AUTO_FETCH_WCCMMUD}" != "true" ]] && return 0
  [[ -d "${d}" ]] && return 0
  log "WCCMMUD not found; fetching module package…"
  mkdir -p "${d}"
  local tmp=/tmp/WCCMMUD.zip
  if curl -fsSL -o "$tmp" "https://download.mbbsemu.com/modules/WCCMMUD/WCCMMUD_MBBSEmu.zip"; then
    unzip -oqq "$tmp" -d "${d}"
    rm -f "$tmp"
    chown -R "${PUID}:${PGID}" "${d}" || true
    log "Fetched WCCMMUD into ${d}"
  else
    log "WARN: could not download WCCMMUD package (continuing)"
  fi
}
maybe_fetch_wccmmud

# --- activation line patches (MMUD & Plus) -----------------------------------
patch_activation() {
  local msg
  # MajorMUD (WCCMMUD.MSG)
  msg="${MODULES_DIR}/WCCMMUD/WCCMMUD.MSG"
  if [[ -f "${msg}" ]]; then
    local safe; safe=$(printf "%s" "${MUD_ACTIVATION_CODE}" | sed -e 's/[&/]/\\&/g')
    sed -E -i "s/^ACTIVATE \{[^}]*\}.*/ACTIVATE {${safe}}/" "${msg}" || true
    log "Patched WCCMMUD activation"
  fi
  # MajorMUD Plus (WCCMMPLS.MSG)
  msg="${MODULES_DIR}/WCCMMUD/WCCMMPLS.MSG"
  if [[ -f "${msg}" ]]; then
    local safe; safe=$(printf "%s" "${MUD_PLUS_ACTIVATION_CODE}" | sed -e 's/[&/]/\\&/g')
    sed -E -i "s/^ACTIVATE \{[^}]*\}.*/ACTIVATE {${safe}}/" "${msg}" || true
    log "Patched WCCMMPLS activation"
  fi
}
patch_activation

# --- write WCCADDON.SYS (1..9) if missing or empty ---------------------------
write_addon_sys() {
  local f="${MODULES_DIR}/WCCMMUD/WCCADDON.SYS"
  [[ -d "${MODULES_DIR}/WCCMMUD" ]] || return 0
  if [[ ! -s "${f}" ]]; then
    {
      echo "1:${ADDON[1]}"
      echo "2:${ADDON[2]}"
      echo "3:${ADDON[3]}"
      echo "4:${ADDON[4]}"
      echo "5:${ADDON[5]}"
      echo "6:${ADDON[6]}"
      echo "7:${ADDON[7]}"
      echo "8:${ADDON[8]}"
      echo "9:${ADDON[9]}"
    } > "${f}"
    chown "${PUID}:${PGID}" "${f}" || true
    chmod 0644 "${f}" || true
    log "Wrote WCCADDON.SYS with add-on keys"
  fi
}
write_addon_sys

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

# --- best-effort: enable WCCMMUD + grant WCCSYSOP to sysop -------------------
db_tweak() {
  local db="${CONFIG_ROOT}/mbbsemu.db"
  [[ -f "$db" ]] || return 0
  command -v sqlite3 >/dev/null 2>&1 || { log "sqlite3 not available; skip DB tweaks"; return 0; }

  # enable module where schema known
  for tbl in Modules Module ModuleConfig ModuleConfiguration TbModules; do
    if sqlite3 "$db" ".tables" | tr ' ' '\n' | grep -qi "^$tbl$"; then
      local cols; cols=$(sqlite3 "$db" "PRAGMA table_info($tbl);" | awk -F'|' '{print tolower($2)}')
      local idcol encol
      idcol=$(echo "$cols" | grep -E '^(identifier|moduleid|id)$' | head -1 || true)
      encol=$(echo "$cols" | grep -E '^(enabled|is_enabled|active)$' | head -1 || true)
      if [[ -n "${idcol:-}" && -n "${encol:-}" ]]; then
        sqlite3 "$db" "UPDATE $tbl SET $encol=1 WHERE lower($idcol)='wccmmud';" >/dev/null 2>&1 && \
          log "DB: enabled WCCMMUD in $tbl"
        break
      fi
    fi
  done

  # grant WCCSYSOP key to sysop if tables present
  if sqlite3 "$db" ".tables" | grep -qiE "(Accounts|AccountKeys)"; then
    local acct_table acct_id_col name_col keys_table key_user_col key_col
    acct_table=$(sqlite3 "$db" ".tables" | tr ' ' '\n' | grep -E '^Accounts$|^Account$' | head -1)
    keys_table=$(sqlite3 "$db" ".tables" | tr ' ' '\n' | grep -E '^AccountKeys$|^AccountKey$' | head -1)
    if [[ -n "$acct_table" && -n "$keys_table" ]]; then
      acct_id_col=$(sqlite3 "$db" "PRAGMA table_info($acct_table);" | awk -F'|' '{print $2}' | grep -Ei '^Id|^AccountId|^AccountID' | head -1)
      name_col=$(sqlite3 "$db" "PRAGMA table_info($acct_table);" | awk -F'|' '{print $2}' | grep -Ei '^Name|^Username|^UserName' | head -1)
      key_user_col=$(sqlite3 "$db" "PRAGMA table_info($keys_table);" | awk -F'|' '{print $2}' | grep -Ei '^AccountId|^AccountID|^UserId|^UserID' | head -1)
      key_col=$(sqlite3 "$db" "PRAGMA table_info($keys_table);" | awk -F'|' '{print $2}' | grep -Ei '^Key|^KeyName' | head -1)
      if [[ -n "$acct_id_col" && -n "$name_col" && -n "$key_user_col" && -n "$key_col" ]]; then
        local sid
        sid=$(sqlite3 "$db" "SELECT $acct_id_col FROM $acct_table WHERE lower($name_col)='sysop' LIMIT 1;")
        if [[ -n "$sid" ]]; then
          local has
          has=$(sqlite3 "$db" "SELECT 1 FROM $keys_table WHERE $key_user_col=$sid AND upper($key_col)='WCCSYSOP' LIMIT 1;")
          if [[ -z "$has" ]]; then
            sqlite3 "$db" "INSERT INTO $keys_table($key_user_col,$key_col) VALUES($sid,'WCCSYSOP');" >/dev/null 2>&1 && \
              log "DB: granted WCCSYSOP to sysop"
          fi
        fi
      fi
    fi
  fi
}
db_tweak

# --- start -------------------------------------------------------------------
cd "${CONFIG_ROOT}"
log "Starting MBBSEmu (Telnet 0.0.0.0:23, Rlogin 0.0.0.0:513)"
if [[ "$(id -u)" -eq 0 ]]; then
  exec gosu "${PUID}:${PGID}" /app/MBBSEmu -S "${APP_JSON}" -C "${MODULES_JSON}"
else
  exec /app/MBBSEmu -S "${APP_JSON}" -C "${MODULES_JSON}"
fi
