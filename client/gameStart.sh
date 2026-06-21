#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  BatoSync — gameStart.sh
#  Batocera calls all scripts in /userdata/system/scripts/ on
#  every game event. This script pulls the latest save before
#  a game starts so you always have the most recent progress.
#
#  Install: copy to /userdata/system/scripts/gameStart.sh
#           chmod +x /userdata/system/scripts/gameStart.sh
#
#  Batocera passes these arguments:
#    $1 = event type (gameStart or gameStop)
#    $2 = system  (e.g. "snes", "nes", "psx")
#    $3 = emulator
#    $4 = core
#    $5 = rom path (full path)
# ─────────────────────────────────────────────────────────────

[[ "$1" != "gameStart" ]] && exit 0

VERSION="3.1.0 (2026-06-21)"

SYSTEM="$2"
EMULATOR="$3"
CORE="$4"
ROM_PATH="$5"
ROM_NAME=$(basename "$ROM_PATH")
ROM_NAME="${ROM_NAME%.*}"

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
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

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
# batosync.sh writes its own log via tee — redirect stdout to /dev/null to avoid duplicates
"$SYNC_SCRIPT" --pull --game "${SYSTEM}_${ROM_NAME}" > /dev/null 2>> "$LOG" || true
echo "[GAME START] Save check complete — launching game" >> "$LOG"

exit 0
