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

VERSION="1.2.0 (2026-05-29)"

SYSTEM="$1"
EMULATOR="$2"
ROM_PATH="$3"
ROM_NAME="$4"

SYNC_SCRIPT="/userdata/scripts/batosync.sh"
LOG="/userdata/system/logs/batosync.log"

# Source config if it exists
[[ -f /userdata/system/batosync.conf ]] && source /userdata/system/batosync.conf

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

# Pull only (we don't push at game start — the game hasn't run yet)
# Run in background so it doesn't delay the game launch
"$SYNC_SCRIPT" --pull --game "${SYSTEM}_${ROM_NAME}" >> "$LOG" 2>&1 &

exit 0
