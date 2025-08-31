MBBSEmu (Docker)

Run The MajorBBS Emulation Project (MBBSEmu) in a clean, easy-to-update Docker image.
This image pulls the latest stable MBBSEmu release at build time and keeps all state in /config so upgrades are just a docker pull.

Image: ghcr.io/zab-01/mbbsemu:latest (amd64)

Ports: Telnet 23/tcp, Rlogin 513/tcp

Data: bind-mount your host folder → /config

We do not ship proprietary game content. If you want to run MajorMUD (or other modules), drop their files into /config/modules/<ModuleID> on the host. This image will auto-detect MajorMUD (module id WCCMMUD) and load it if present.

Quick start (Docker CLI)
docker run -d \
  --name mbbsemu \
  -p 2323:23 \                   # map host 2323 → container 23 (telnet)
  -p 513:513 \                   # rlogin (optional)
  -e TZ="America/Chicago" \
  -e PUID=1000 -e PGID=1000 \    # use your host user/group; Unraid = 99/100
  -e SYSOP_PASSWORD="change-me" \# first run only; initializes /config/mbbsemu.db
  -e MUD_REG_NUMBER="00150015" \ # optional MajorMUD license (8 digits, leading zeros ok)
  -e MUD_ACTIVATION_CODE="XXXX" \# optional MajorMUD activation (replaces {DEMO} in WCCMMUD.MSG)
  -v "$PWD/config:/config" \
  --restart unless-stopped \
  ghcr.io/zab-01/mbbsemu:latest


Then connect: telnet localhost 2323

If you’re on Unraid/macvlan with a static container IP, you usually don’t need -p—just telnet to the container’s IP on port 23.

docker-compose

Create compose.yaml next to a config/ folder:

services:
  mbbsemu:
    image: ghcr.io/zab-01/mbbsemu:latest
    container_name: mbbsemu
    restart: unless-stopped
    ports:
      - "2323:23"       # telnet
      - "513:513"       # rlogin (optional)
    environment:
      TZ: America/Chicago
      PUID: "1000"        # Unraid typically 99
      PGID: "1000"        # Unraid typically 100
      SYSOP_PASSWORD: "change-me"    # only used on first boot to create /config/mbbsemu.db
      # Optional MajorMUD license pieces:
      # MUD_REG_NUMBER: "00150015"    # always written as a *string*, padded to 8 digits
      # MUD_ACTIVATION_CODE: "XXXXXXXX"
      # Optional behavior toggles (defaults shown):
      # MODULES_AUTODETECT: "true"    # if /config/modules/WCCMMUD exists & modules.json missing, auto-enable it
      # MODULES_FIX_CASE: "true"      # create lowercase symlinks for UPPERCASE files (Linux case-sensitivity)
      # MODULES_RELAX_PERMS: "true"   # chmod -R u+rwX,go+rX inside /config/modules so content is readable
      # MODULES_JSON_INLINE: '{"Modules":[]}'  # advanced: override modules.json completely via env
    volumes:
      - ./config:/config


Bring it up:

docker compose up -d

What goes in /config?

Everything you care about:

/config
├─ appsettings.json      # main emulator settings (auto-created on first run if missing)
├─ modules.json          # which modules to load (auto-created; see below)
├─ mbbsemu.db            # emulator database (created when SYSOP_PASSWORD is provided on first run)
├─ modules/              # your module content lives here
│  └─ WCCMMUD/           # MajorMUD files (example)
└─ logs/                 # runtime logs

Modules

Place each module in its own subfolder under /config/modules, e.g.:

/config/modules/WCCMMUD (MajorMUD)

/config/modules/TSGARN (Tele-Arena), etc.

If modules.json is missing, the container will auto-enable MajorMUD when it finds /config/modules/WCCMMUD.

Linux is case-sensitive; this image auto-creates lowercase symlinks for uppercase DOS filenames (e.g., WCCMMUTL.EXE → wccmmutl.EXE) so MBBSEmu can find them.

You can also explicitly control modules with modules.json:

{
  "Modules": [
    { "Identifier": "WCCMMUD", "Path": "/config/modules/WCCMMUD" },
    { "Identifier": "TSGARN",  "Path": "/config/modules/TSGARN" }
  ]
}


Or override via env on the fly:

environment:
  MODULES_JSON_INLINE: |
    {"Modules":[
      {"Identifier":"WCCMMUD","Path":"/config/modules/WCCMMUD"}
    ]}

Environment variables
Name	Required	Default	Purpose
TZ	no	UTC	Container timezone (affects logs).
PUID	no	1000	Run as this user ID; use your host user. Unraid: 99.
PGID	no	1000	Run as this group ID. Unraid: 100.
SYSOP_PASSWORD	no	(unset)	On first run only, if /config/mbbsemu.db doesn’t exist, initialize the DB with this Sysop password.
MUD_REG_NUMBER	no	(unset)	MajorMUD registration number. The entrypoint pads to 8 digits and writes JSON as a string to Application.GSBL.BTURNO in /config/appsettings.json. Leading zeros are preserved.
MUD_ACTIVATION_CODE	no	(unset)	MajorMUD activation string. If /config/modules/WCCMMUD/WCCMMUD.MSG exists, {DEMO} will be replaced with this value.
MODULES_AUTODETECT	no	true	If modules.json is missing, auto-enable WCCMMUD when its folder exists; otherwise start with no modules.
MODULES_FIX_CASE	no	true	Create lowercase symlinks for files in each module folder to avoid Linux case issues.
MODULES_RELAX_PERMS	no	true	Make module files readable (u+rwX,go+rX) inside /config/modules.
MODULES_JSON_INLINE	no	(unset)	Provide a full JSON string to replace /config/modules.json at startup (advanced).
Networking

Telnet listens on 0.0.0.0:23 inside the container.

Rlogin listens on 0.0.0.0:513 (optional).
If you enable “per-module Rlogin ports” in appsettings.json, modules may also bind sequential ports starting at 514.

Typical mappings:

Bridge mode: map to non-privileged host ports, e.g. 2323:23.

Macvlan/static IP (Unraid): no mapping needed; connect directly to the container IP on port 23.

Upgrading

All state is in /config, so upgrades are trivial:

# docker compose
docker compose pull
docker compose up -d

# or plain docker
docker pull ghcr.io/zab-01/mbbsemu:latest
docker stop mbbsemu && docker rm mbbsemu
# re-run with same flags/volume and it will pick up existing /config

Troubleshooting

Telnet doesn’t open:
Check logs: docker logs -f mbbsemu.
On bridge, confirm you mapped -p 2323:23. On Unraid/macvlan, connect to the container IP on port 23.

JSON error (leading zero / GSBL.BTURNO):
Old files may have GSBL.BTURNO as a number. This image writes it as a padded string.
Delete /config/appsettings.json (it will be recreated) or set MUD_REG_NUMBER and restart.

MajorMUD won’t load / “file not found”:
Ensure the files are under /config/modules/WCCMMUD.
The image auto-creates lowercase symlinks for WCCMMUTL.EXE, WCCMMUD.EXE, etc., and relaxes perms so the runtime can read them.
If you want to disable modules temporarily: set MODULES_JSON_INLINE={"Modules":[]}.

Reset Sysop password:
Stop container, delete /config/mbbsemu.db, start again with SYSOP_PASSWORD set.

GHCR access:
The package is public. If you ever make it private, login once on the host:
docker login ghcr.io -u <github-user> -p <PAT with read:packages>.

Notes for Unraid users

Map /mnt/user/appdata/mbbsemu/config → /config.

Set PUID=99, PGID=100. The “uid outside UID_MIN” warning is normal on Unraid.

If you attach to a VLAN/macvlan network (e.g., br0.x with static IP), skip port mappings and telnet to the container IP on port 23.

What’s inside the image?

Base: mcr.microsoft.com/dotnet/runtime-deps:8.0-bookworm-slim (+ libncursesw6 for Terminal UI)

Pulls latest stable MBBSEmu at build time

Runs from /config so all generated files (e.g., BBSGEN.DB) persist

Drops privileges to PUID:PGID (via gosu)

Allows binding port 23 as non-root (cap_net_bind_service)

Questions or ideas? Open an issue or PR!
