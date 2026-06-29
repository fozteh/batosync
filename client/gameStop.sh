#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  BatoSync — gameStop.sh
#  Batocera calls all scripts in /userdata/system/scripts/ on
#  every game event. This script pushes the save when a game stops.
#
#  Install: copy to /userdata/system/scripts/gameStop.sh
#           chmod +x /userdata/system/scripts/gameStop.sh
#
#  Batocera passes these arguments:
#    $1 = event type (gameStart or gameStop)
#    $2 = system  (e.g. "snes", "nes", "psx")
#    $3 = emulator
#    $4 = core
#    $5 = rom path (full path)
# ─────────────────────────────────────────────────────────────

[[ "$1" != "gameStop" ]] && exit 0

VERSION="1.3.0 (2026-06-21)"

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
# batosync.sh writes its own log via tee — redirect stdout to /dev/null to avoid duplicates
"$SYNC_SCRIPT" --push --game "${SYSTEM}_${ROM_NAME}" > /dev/null 2>> "$LOG"

exit 0
