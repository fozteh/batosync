#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  BatoSync — autostart.sh
#  Runs once at Batocera boot. Pulls all latest saves from the
#  server so the device is fully up to date before you play.
#
#  Install: copy to /userdata/system/autostart.sh
#           chmod +x /userdata/system/autostart.sh
#
#  NOTE: If you already have a custom autostart.sh, add the
#  lines between the markers to your existing file instead of
#  replacing it.
# ─────────────────────────────────────────────────────────────

VERSION="1.2.0 (2026-05-29)"

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

mkdir -p "$(dirname "$LOG")"

echo "" >> "$LOG"
echo "═══════════════════════════════════" >> "$LOG"
echo "[BOOT] $(date '+%Y-%m-%d %H:%M:%S') — Batocera starting" >> "$LOG"

if [[ ! -x "$SYNC_SCRIPT" ]]; then
    echo "[BOOT] batosync.sh not found — skipping boot sync" >> "$LOG"
    exit 0
fi

if [[ -z "${BATOSYNC_SERVER:-}" ]]; then
    echo "[BOOT] BATOSYNC_SERVER not set — skipping boot sync" >> "$LOG"
    exit 0
fi

echo "[BOOT] Waiting for network…" >> "$LOG"

# Wait for network (up to 30 seconds)
ATTEMPTS=0
until curl -sf --max-time 3 "${BATOSYNC_SERVER}/health" > /dev/null 2>&1; do
    sleep 3
    ATTEMPTS=$((ATTEMPTS + 1))
    if [[ $ATTEMPTS -ge 10 ]]; then
        echo "[BOOT] Server unreachable after 30s — skipping boot sync" >> "$LOG"
        exit 0
    fi
done

echo "[BOOT] Server reachable. Pulling latest saves…" >> "$LOG"

# Pull all saves in the background so EmulationStation loads without waiting
"$SYNC_SCRIPT" --pull >> "$LOG" 2>&1 &

echo "[BOOT] Pull started in background (PID $!)" >> "$LOG"

exit 0
