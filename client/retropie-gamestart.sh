#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  BatoSync — retropie-gamestart.sh
#  RetroPie/EmulationStation calls all scripts in:
#    /opt/retropie/configs/all/emulationstation/scripts/
#  with: $1=event  $2=system  $3=emulator  $4=rom_path
#
#  Install: copy to the scripts directory above, e.g. as
#           batosync-gamestart.sh
#           chmod +x the file
# ─────────────────────────────────────────────────────────────

[[ "$1" != "game-start" ]] && exit 0

VERSION="1.0.0 (2026-06-29)"

SYSTEM="$2"
ROM_PATH="$4"
ROM_NAME=$(basename "$ROM_PATH")
ROM_NAME="${ROM_NAME%.*}"

for _conf in "/opt/retropie/configs/all/batosync.conf" \
             "$(dirname "$0")/batosync.conf" "$HOME/batosync.conf"; do
    [[ -f "$_conf" ]] && source "$_conf" && break
done

SYNC_SCRIPT=""
for _s in "/home/pi/RetroPie/scripts/batosync.sh" \
          "$(dirname "$0")/batosync.sh"; do
    [[ -x "$_s" ]] && SYNC_SCRIPT="$_s" && break
done
SYNC_SCRIPT="${SYNC_SCRIPT:-/home/pi/RetroPie/scripts/batosync.sh}"
LOG="${BATOSYNC_LOG:-/home/pi/RetroPie/logs/batosync.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

echo "" >> "$LOG"
echo "[GAME START] $(date '+%Y-%m-%d %H:%M:%S') — $SYSTEM / $ROM_NAME" >> "$LOG"

if [[ ! -x "$SYNC_SCRIPT" ]]; then
    echo "[GAME START] batosync.sh not found or not executable — skipping" >> "$LOG"
    exit 0
fi

if [[ -z "${BATOSYNC_SERVER:-}" ]]; then
    echo "[GAME START] BATOSYNC_SERVER not set — skipping" >> "$LOG"
    exit 0
fi

echo "[GAME START] Checking for newer saves on server..." >> "$LOG"
"$SYNC_SCRIPT" --pull --game "${SYSTEM}_${ROM_NAME}" > /dev/null 2>> "$LOG" || true
echo "[GAME START] Save check complete — launching game" >> "$LOG"

exit 0
