# MBBSEmu (Docker)

Run **The MajorBBS Emulation Project (MBBSEmu)** in a clean, easy-to-update Docker image.  
This image fetches the **latest stable** MBBSEmu release at build time and keeps **all state in `/config`**, so upgrades are just a `docker pull`.

- **Image:** `ghcr.io/zab-01/mbbsemu:latest` (linux/amd64)  
- **Ports:** Telnet `23/tcp`, Rlogin `513/tcp`  
- **Data:** bind-mount your host folder → `/config`

> We do **not** ship proprietary game content. If you want to run MajorMUD or other modules, place their files under `/config/modules/<ModuleID>`. This image auto-detects MajorMUD (module id `WCCMMUD`) and loads it if present.

---

## Quick start (Docker CLI)

```bash
docker run -d   --name mbbsemu   -p 2323:23 \                   # map host 2323 → container 23 (Telnet)
  -p 513:513 \                   # Rlogin (optional)
  -e TZ="America/Chicago"   -e PUID=1000 -e PGID=1000 \    # your host user/group; Unraid commonly 99/100
  -e SYSOP_PASSWORD="change-me" \# first run only; creates /config/mbbsemu.db
  -e MUD_REG_NUMBER="00150015" \ # optional MajorMUD license (8 digits; leading zeros OK)
  -e MUD_ACTIVATION_CODE="XXXX" \# optional MajorMUD activation (replaces {DEMO} in WCCMMUD.MSG)
  -v "$PWD/config:/config"   --restart unless-stopped   ghcr.io/zab-01/mbbsemu:latest
```

Then connect: `telnet localhost 2323`

> On Unraid with macvlan/static IP you usually **don’t** need `-p`; just telnet to the container IP on port 23.

---

## Docker Compose

Create `compose.yaml` next to a `config/` folder:

```yaml
services:
  mbbsemu:
    image: ghcr.io/zab-01/mbbsemu:latest
    container_name: mbbsemu
    restart: unless-stopped
    ports:
      - "2323:23"     # Telnet
      - "513:513"     # Rlogin (optional)
    environment:
      TZ: America/Chicago
      PUID: "1000"          # Unraid: 99
      PGID: "1000"          # Unraid: 100
      SYSOP_PASSWORD: "change-me"  # first boot only
      # Optional MajorMUD licensing:
      # MUD_REG_NUMBER: "00150015"      # always written as a *string*, padded to 8 digits
      # MUD_ACTIVATION_CODE: "XXXXXXXX"
      # Optional behavior toggles (defaults shown):
      # MODULES_AUTODETECT: "true"      # if /config/modules/WCCMMUD exists & modules.json missing, auto-enable it
      # MODULES_FIX_CASE: "true"        # create lowercase symlinks for UPPERCASE files (Linux case-sensitivity)
      # MODULES_RELAX_PERMS: "true"     # chmod -R u+rwX,go+rX inside /config/modules so content is readable
      # MODULES_JSON_INLINE: '{"Modules":[]}'  # advanced: override modules.json completely via env
    volumes:
      - ./config:/config
```

Bring it up:

```bash
docker compose up -d
```

---

## What goes in `/config`?

Everything you care about:

```
/config
├─ appsettings.json      # main emulator settings (auto-created/updated)
├─ modules.json          # which modules to load (auto-created if missing)
├─ mbbsemu.db            # emulator database (created on first run when SYSOP_PASSWORD is provided)
├─ modules/
│  └─ WCCMMUD/           # MajorMUD files (example)
└─ logs/
```

### Modules

- Place each module in its **own subfolder** under `/config/modules`, e.g.:
  - `/config/modules/WCCMMUD` (MajorMUD)
  - `/config/modules/TSGARN` (Tele-Arena), etc.
- If `modules.json` is **missing**, the container will **auto-enable** MajorMUD **only** when it finds `/config/modules/WCCMMUD`.
- Linux is case-sensitive; this image **auto-creates lowercase symlinks** for uppercase DOS filenames (e.g., `WCCMMUTL.EXE` → `wccmmutl.EXE`) so MBBSEmu can find them.

You can explicitly control modules with `modules.json`:

```json
{
  "Modules": [
    { "Identifier": "WCCMMUD", "Path": "/config/modules/WCCMMUD" },
    { "Identifier": "TSGARN",  "Path": "/config/modules/TSGARN" }
  ]
}
```

Or override via env:

```yaml
environment:
  MODULES_JSON_INLINE: |
    {"Modules":[
      {"Identifier":"WCCMMUD","Path":"/config/modules/WCCMMUD"}
    ]}
```

---

## Environment variables

| Name | Required | Default | Purpose |
|---|---:|---|---|
| `TZ` | no | UTC | Container timezone (affects logs). |
| `PUID` | no | `1000` | Run as this user ID; match a host user. **Unraid:** `99`. |
| `PGID` | no | `1000` | Run as this group ID. **Unraid:** `100`. |
| `SYSOP_PASSWORD` | no | _(unset)_ | On first run **only**, if `/config/mbbsemu.db` doesn’t exist, initialize DB with this Sysop password. |
| `MUD_REG_NUMBER` | no | _(unset)_ | MajorMUD registration number. The entrypoint pads to 8 digits and writes JSON **as a string** to `Application.GSBL.BTURNO` in `/config/appsettings.json` (leading zeros preserved). |
| `MUD_ACTIVATION_CODE` | no | _(unset)_ | MajorMUD activation string. If `/config/modules/WCCMMUD/WCCMMUD.MSG` exists, `{DEMO}` is replaced with this value. |
| `MODULES_AUTODETECT` | no | `true` | If `modules.json` is missing, auto-enable `WCCMMUD` when its folder exists; otherwise start with no modules. |
| `MODULES_FIX_CASE` | no | `true` | Create lowercase symlinks for files in each module folder to avoid Linux case issues. |
| `MODULES_RELAX_PERMS` | no | `true` | Make module files readable (`u+rwX,go+rX`) inside `/config/modules`. |
| `MODULES_JSON_INLINE` | no | _(unset)_ | Provide a full JSON string to replace `/config/modules.json` at startup (advanced). |

---

## Networking

- **Telnet** listens on `0.0.0.0:23` inside the container.
- **Rlogin** listens on `0.0.0.0:513` (optional).  
  If you enable “per-module Rlogin ports” in `appsettings.json`, modules may also bind sequential ports starting at `514`.

Bridge example: `-p 2323:23` then `telnet localhost 2323`.  
Unraid/macvlan static IP: connect directly to container IP on port `23`.

---

## Upgrading

All state is in `/config`, so upgrades are trivial:

```bash
# docker compose
docker compose pull
docker compose up -d

# or plain docker
docker pull ghcr.io/zab-01/mbbsemu:latest
docker stop mbbsemu && docker rm mbbsemu
# re-run with the same flags/volume; existing /config is reused
```

---

## Troubleshooting

- **Telnet doesn’t open**  
  Check logs: `docker logs -f mbbsemu`.  
  On bridge, confirm `-p 2323:23`. On macvlan/static IP, connect to the container IP:23.

- **JSON “leading zero” error for GSBL.BTURNO**  
  Older files may store it as a number. This image writes it as a **padded string** from `MUD_REG_NUMBER`.  
  Remove `/config/appsettings.json` (it will be recreated) **or** set `MUD_REG_NUMBER` and restart.

- **MajorMUD file not found** (`wccmmutl.EXE` etc.)  
  Ensure the files are in `/config/modules/WCCMMUD`. This image relaxes perms and creates lowercase symlinks automatically.

- **Reset Sysop password**  
  Stop container, delete `/config/mbbsemu.db`, start again with `SYSOP_PASSWORD` set.

- **Rlogin loopback**  
  We default to `0.0.0.0`. If you see loopback in your old config, edit `/config/appsettings.json` and set:
  ```json
  "Rlogin": { "Enabled": true, "IP": "0.0.0.0", "Port": 513, "PortPerModule": false }
  ```

---

## Notes for Unraid

- Map `/mnt/user/appdata/mbbsemu/config` → `/config`.  
- Set `PUID=99`, `PGID=100`. The “uid outside UID_MIN” warning is normal.  
- On a VLAN/macvlan network (`br0.x`) with a static IP, skip port mappings and telnet directly to the container IP on port 23.

---

## What’s inside

- Base: `mcr.microsoft.com/dotnet/runtime-deps:8.0-bookworm-slim` (+ `libncursesw6` for Terminal UI)  
- Pulls **latest stable** MBBSEmu at build time  
- Runs from `/config` so generated files (e.g., `BBSGEN.DB`) persist  
- Drops privileges to `PUID:PGID` (via `gosu`)  
- Allows binding port 23 as non-root (`cap_net_bind_service`)

---

Questions or ideas? Open an issue or PR!
