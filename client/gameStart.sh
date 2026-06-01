#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  BatoSync — gameStart.sh
#  Batocera calls this automatically just before launching a game.
#  It pulls the latest save from the server so you always start
#  with the most recent progress.
#
#  Install: copy to /userdata/scripts/gameStart.sh
#           chmod +x /userdata/scripts/gameStart.sh
#
#  Batocera passes these arguments:
#    $1 = system  (e.g. "snes", "nes", "psx")
#    $2 = emulator
#    $3 = rom path
#    $4 = rom name (no extension)
# ─────────────────────────────────────────────────────────────

VERSION="3.0.0 (2026-05-29)"

SYSTEM="$1"
EMULATOR="$2"
ROM_PATH="$3"
ROM_NAME="$4"

# Load config from first location found
for _conf in "/userdata/system/batosync.conf" "/mnt/mmc/MUOS/batosync.conf" \
             "$(dirname "$0")/batosync.conf" "$HOME/batosync.conf"; do
    [[ -f "$_conf" ]] && source "$_conf" && break
done

# Find sync script
SYNC_SCRIPT=""
for _s in "/userdata/scripts/batosync.sh" "/mnt/mmc/MUOS/bin/batosync.sh" \
          "$(dirname "$0")/batosync.sh"; do
    [[ -x "$_s" ]] && SYNC_SCRIPT="$_s" && break
done
SYNC_SCRIPT="${SYNC_SCRIPT:-/userdata/scripts/batosync.sh}"
LOG="${BATOSYNC_LOG:-/userdata/system/logs/batosync.log}"

echo "" >> "$LOG"
echo "[GAME START] $(date '+%Y-%m-%d %H:%M:%S') — $SYSTEM / $ROM_NAME" >> "$LOG"

# Only proceed if the sync script exists and server is configured
if [[ ! -x "$SYNC_SCRIPT" ]]; then
    echo "[GAME START] batosync.sh not found or not executable — skipping" >> "$LOG"
    exit 0
fi

if [[ -z "${BATOSYNC_SERVER:-}" ]]; then
    echo "[GAME START] BATOSYNC_SERVER not set — skipping" >> "$LOG"
    exit 0
fi

# Smart pull: check server checksums against local files for this game.
# Only downloads if server has something newer — launches immediately if already in sync.
# Runs synchronously so the game starts with the correct save already on disk.
echo "[GAME START] Checking for newer saves on server..." >> "$LOG"
"$SYNC_SCRIPT" --pull --game "${SYSTEM}_${ROM_NAME}" >> "$LOG" 2>&1 || true
echo "[GAME START] Save check complete — launching game" >> "$LOG"

exit 0
