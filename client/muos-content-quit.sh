#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  BatoSync — muos-content-quit.sh
#  Called by MuOS after a game exits. Pushes the save up to
#  the server.
#
#  Install: /mnt/mmc/MUOS/hook/content-quit.sh
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

SYSTEM=$(basename "$(dirname "$ROM")" | tr '[:upper:]' '[:lower:]')
ROM_NAME=$(basename "$ROM")
ROM_NAME="${ROM_NAME%.*}"

for _conf in "/mnt/mmc/MUOS/batosync.conf" "$HOME/batosync.conf"; do
    [[ -f "$_conf" ]] && source "$_conf" && break
done

SYNC_SCRIPT="/mnt/mmc/MUOS/bin/batosync.sh"
LOG="${BATOSYNC_LOG:-/mnt/mmc/MUOS/log/batosync.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

printf '\n' >> "$LOG"
printf '[GAME STOP]  %s — %s / %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$SYSTEM" "$ROM_NAME" >> "$LOG"

if [ ! -x "$SYNC_SCRIPT" ]; then
    printf '[GAME STOP] batosync.sh not found or not executable — skipping\n' >> "$LOG"
    exit 0
fi

if [ -z "${BATOSYNC_SERVER:-}" ]; then
    printf '[GAME STOP] BATOSYNC_SERVER not set — skipping\n' >> "$LOG"
    exit 0
fi

# Brief wait — MuOS runs sync in the background after the emulator exits;
# this gives the filesystem a moment to flush save writes before we push
sleep 3

"$SYNC_SCRIPT" --push --game "${SYSTEM}_${ROM_NAME}" > /dev/null 2>> "$LOG"

exit 0
