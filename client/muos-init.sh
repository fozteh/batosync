#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  BatoSync — muos-init.sh
#  Runs once at MuOS boot. Pulls all latest saves from the
#  server so the device is fully up to date before you play.
#
#  Install: copy to /mnt/mmc/MUOS/init/batosync.sh
#           chmod +x /mnt/mmc/MUOS/init/batosync.sh
#
#  All scripts in /mnt/mmc/MUOS/init/ run automatically at boot.
# ─────────────────────────────────────────────────────────────

VERSION="1.0.0 (2026-06-29)"

for _conf in "/mnt/mmc/MUOS/batosync.conf" "$HOME/batosync.conf"; do
    [[ -f "$_conf" ]] && source "$_conf" && break
done


SYNC_SCRIPT="/mnt/mmc/MUOS/bin/batosync.sh"
LOG="${BATOSYNC_LOG:-/mnt/mmc/MUOS/log/batosync.log}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

echo "" >> "$LOG"
echo "═══════════════════════════════════" >> "$LOG"
echo "[BOOT] $(date '+%Y-%m-%d %H:%M:%S') — MuOS starting" >> "$LOG"

if [[ ! -x "$SYNC_SCRIPT" ]]; then
    echo "[BOOT] batosync.sh not found — skipping boot sync" >> "$LOG"
    exit 0
fi

if [[ -z "${BATOSYNC_SERVER:-}" ]]; then
    echo "[BOOT] BATOSYNC_SERVER not set — skipping boot sync" >> "$LOG"
    exit 0
fi

echo "[BOOT] Waiting for network..." >> "$LOG"

ATTEMPTS=0
until curl -sf --max-time 3 "${BATOSYNC_SERVER}/health" > /dev/null 2>&1; do
    sleep 3
    ATTEMPTS=$((ATTEMPTS + 1))
    if [[ $ATTEMPTS -ge 10 ]]; then
        echo "[BOOT] Server unreachable after 30s — skipping boot sync" >> "$LOG"
        exit 0
    fi
done

echo "[BOOT] Server reachable. Pulling latest saves..." >> "$LOG"
"$SYNC_SCRIPT" --pull >> "$LOG" 2>&1 &
echo "[BOOT] Pull started in background (PID $!)" >> "$LOG"

exit 0
