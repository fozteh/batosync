#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  BatoSync — muos-content-load.sh
#  Called by MuOS just before a game launches. Pulls the latest
#  save from the server so you always start with fresh progress.
#
#  Install: /mnt/mmc/MUOS/hook/content-load.sh
#  (and patch launch.sh — see README Part 3)
#
#  MuOS passes: $1 = display name  (e.g. "Super Mario World")
#               $2 = core          (e.g. "lr-snes9x")
#               $3 = full ROM path (e.g. /mnt/mmc/roms/SNES/Super Mario World.sfc)
# ─────────────────────────────────────────────────────────────

NAME="${1:-}"
CORE="${2:-}"
ROM="${3:-}"

[ -z "$ROM" ] && exit 0

VERSION="1.0.0 (2026-06-29)"

# System = ROM parent directory name, lowercased to match Batocera convention
SYSTEM=$(basename "$(dirname "$ROM")" | tr '[:upper:]' '[:lower:]')
# Game key = filename without extension (consistent with Batocera)
ROM_NAME=$(basename "$ROM")
ROM_NAME="${ROM_NAME%.*}"

for _conf in "/mnt/mmc/MUOS/batosync.conf" "$HOME/batosync.conf"; do
    [[ -f "$_conf" ]] && source "$_conf" && break
done

SYNC_SCRIPT="/mnt/mmc/MUOS/bin/batosync.sh"
LOG="${BATOSYNC_LOG:-/mnt/mmc/MUOS/log/batosync.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

printf '\n' >> "$LOG"
printf '[GAME START] %s — %s / %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$SYSTEM" "$ROM_NAME" >> "$LOG"

if [ ! -x "$SYNC_SCRIPT" ]; then
    printf '[GAME START] batosync.sh not found or not executable — skipping\n' >> "$LOG"
    exit 0
fi

if [ -z "${BATOSYNC_SERVER:-}" ]; then
    printf '[GAME START] BATOSYNC_SERVER not set — skipping\n' >> "$LOG"
    exit 0
fi

printf '[GAME START] Checking for newer saves on server...\n' >> "$LOG"
"$SYNC_SCRIPT" --pull --game "${SYSTEM}_${ROM_NAME}" > /dev/null 2>> "$LOG" || true
printf '[GAME START] Save check complete — launching game\n' >> "$LOG"

exit 0
