#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  BatoSync — gameStop.sh
#  Batocera calls this automatically after a game closes.
#  It pushes your fresh save up to the server.
#
#  Install: copy to /userdata/scripts/gameStop.sh
#           chmod +x /userdata/scripts/gameStop.sh
#
#  Batocera passes these arguments:
#    $1 = system  (e.g. "snes", "nes", "psx")
#    $2 = emulator
#    $3 = rom path
#    $4 = rom name (no extension)
# ─────────────────────────────────────────────────────────────

VERSION="1.2.0 (2026-05-29)"

SYSTEM="$1"
EMULATOR="$2"
ROM_PATH="$3"
ROM_NAME="$4"

# Load config from first location found
for _conf in "/userdata/system/batosync.conf" "/mnt/mmc/MUOS/batosync.conf" \
             "$(dirname "$(realpath "$0")")/batosync.conf" "$HOME/batosync.conf"; do
    [[ -f "$_conf" ]] && source "$_conf" && break
done

# Find sync script
SYNC_SCRIPT=""
for _s in "/userdata/scripts/batosync.sh" "/mnt/mmc/MUOS/bin/batosync.sh" \
          "$(dirname "$(realpath "$0")")/batosync.sh"; do
    [[ -x "$_s" ]] && SYNC_SCRIPT="$_s" && break
done
SYNC_SCRIPT="${SYNC_SCRIPT:-/userdata/scripts/batosync.sh}"
LOG="${BATOSYNC_LOG:-/userdata/system/logs/batosync.log}"

echo "" >> "$LOG"
echo "[GAME STOP]  $(date '+%Y-%m-%d %H:%M:%S') — $SYSTEM / $ROM_NAME" >> "$LOG"

if [[ ! -x "$SYNC_SCRIPT" ]]; then
    echo "[GAME STOP] batosync.sh not found or not executable — skipping" >> "$LOG"
    exit 0
fi

if [[ -z "${BATOSYNC_SERVER:-}" ]]; then
    echo "[GAME STOP] BATOSYNC_SERVER not set — skipping" >> "$LOG"
    exit 0
fi

# Brief delay — emulators sometimes write the save file a moment after closing
sleep 3

# Push the save for the game that just closed
"$SYNC_SCRIPT" --push --game "${SYSTEM}_${ROM_NAME}" >> "$LOG" 2>&1

exit 0
