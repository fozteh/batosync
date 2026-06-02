#!/bin/bash
# ─────────────────────────────────────────────────────────────────
#  BatoSync Client — syncs Batocera save files with a central
#  BatoSync Docker server.
#
#  Usage:
#    batosync.sh                  # sync ALL games (push + pull)
#    batosync.sh --push           # push local saves to server only
#    batosync.sh --pull           # pull latest saves from server
#    batosync.sh --dry-run        # show what would sync, no changes
#    batosync.sh --force          # override sanity check (e.g. intentional blank server)
#    batosync.sh --game "Zelda"   # sync a specific game only
#    batosync.sh --list           # list games on the server
#    batosync.sh --status         # show server save status
#
#  Place this file in /userdata/scripts/ on your Batocera device
#  and make it executable:  chmod +x /userdata/scripts/batosync.sh
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

VERSION="3.1.0 (2026-05-29)"

# ── Load config from first location found ─────────────────────────
for _conf in \
    "/userdata/system/batosync.conf" \
    "/mnt/mmc/MUOS/batosync.conf" \
    "$(dirname "$0")/batosync.conf" \
    "$HOME/batosync.conf"; do
    [[ -f "$_conf" ]] && source "$_conf" && break
done

# ── Configuration ─────────────────────────────────────────────────
SERVER_URL="${BATOSYNC_SERVER:-http://192.168.1.100:5000}"
API_KEY="${BATOSYNC_KEY:-change_me_to_a_secret_passphrase}"
SAVES_DIR="${BATOSYNC_SAVES:-/userdata/saves}"
DEVICE_NAME="${BATOSYNC_DEVICE:-$(hostname)}"
LOG_FILE="${BATOSYNC_LOG:-/userdata/system/logs/batosync.log}"
# Space-separated list of top-level save dirs to skip (e.g. "supermodel arcade")
EXCLUDE_DIRS="${BATOSYNC_EXCLUDE_DIRS:-}"
# Conflict behaviour: warn (push anyway with warning) | skip (keep server version)
CONFLICT_BEHAVIOR="${BATOSYNC_CONFLICT:-warn}"
# Where to store timestamped backups of local saves
BACKUP_BASE="${SAVES_DIR}/.batosync_backups"
BACKUP_KEEP=3   # number of full backups to retain
# File tracking last known server game count for sanity checks
STATE_FILE="${LOG_FILE%.log}.state"
# ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MODE="sync"
FILTER_GAME=""
DRY_RUN=false
FORCE=false

log() { echo -e "$1" | tee -a "$LOG_FILE"; }
info()    { log "${CYAN}[INFO]${NC}  $1"; }
success() { log "${GREEN}[OK]${NC}    $1"; }
warn()    { log "${YELLOW}[WARN]${NC}  $1"; }
error()   { log "${RED}[ERROR]${NC} $1"; }

mkdir -p "$(dirname "$LOG_FILE")"
log ""
log "════════════════════════════════════════"
log "  BatoSync v${VERSION}"
log "  $(date '+%Y-%m-%d %H:%M:%S')"
log "  Device : $DEVICE_NAME"
log "  Server : $SERVER_URL"
log "════════════════════════════════════════"

# ── Argument parsing ───────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --push)     MODE="push";    shift ;;
        --pull)     MODE="pull";    shift ;;
        --list)     MODE="list";    shift ;;
        --status)   MODE="status";  shift ;;
        --dry-run)  DRY_RUN=true;   shift ;;
        --force)    FORCE=true;     shift ;;
        --game)     FILTER_GAME="$2"; shift 2 ;;
        --help|-h)
            grep '^#  ' "$0" | sed 's/^#  //'
            exit 0
            ;;
        *) error "Unknown argument: $1"; exit 1 ;;
    esac
done

[[ "$DRY_RUN" == "true" ]] && warn "DRY-RUN mode — no files will be changed"

# ── Helpers ────────────────────────────────────────────────────────
api() {
    local method="$1" path="$2"
    shift 2
    curl -sS \
        -X "$method" \
        -H "X-API-Key: $API_KEY" \
        "$@" \
        "${SERVER_URL}${path}"
}

api_json() {
    api "$@" -H "Accept: application/json"
}

checksum() {
    md5sum "$1" | awk '{print $1}'
}

# Returns 0 (true) if the game_name should be excluded
is_excluded() {
    [[ -z "$EXCLUDE_DIRS" ]] && return 1
    local top_dir="${1%%_*}"
    for excl in $EXCLUDE_DIRS; do
        [[ "$top_dir" == "$excl" ]] && return 0
    done
    return 1
}

# Shared find pipeline for save files
# grep exits 1 when no files match the filter (e.g. fresh device with only .txt files)
# || true prevents set -euo pipefail from killing the script in that case
find_saves() {
    find "$SAVES_DIR" -type f \
        ! -name "*.batosync_backup" \
        ! -path "*/.batosync_backups/*" \
        | grep -viE '\.(png|jpg|jpeg|gif|bmp|webp|tif|tiff|svg|mp4|mkv|avi|mov|mp3|ogg|flac|wav|xml|txt|nfo|pdf)$' \
        || true
}

# ── Sanity check: abort if server looks empty vs last known state ──
sanity_check() {
    local server_count last_count=0
    server_count=$(api_json GET /games 2>/dev/null | python3 -c "
import json,sys
data=json.load(sys.stdin)
print(len(data.get('games',[])))
" 2>/dev/null) || server_count=0

    [[ -f "$STATE_FILE" ]] && last_count=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
    last_count=${last_count:-0}

    # Update stored count
    echo "$server_count" > "$STATE_FILE" 2>/dev/null || true

    # Warn if server count dropped to less than half of what we last saw
    # and we previously had a meaningful number of saves
    if [[ $last_count -gt 10 && $server_count -lt $(( last_count / 2 )) ]]; then
        warn "⚠ Server game count dropped from $last_count to $server_count"
        if [[ "$FORCE" != "true" ]]; then
            error "Pull aborted — server may be blank or misconfigured."
            error "If intentional, re-run with --force to override."
            return 1
        fi
        warn "Proceeding anyway (--force)"
    fi
    return 0
}

# ── Timestamped backup of all local saves ─────────────────────────
backup_saves() {
    [[ "$DRY_RUN" == "true" ]] && return 0
    local ts backup_path
    ts=$(date +%Y%m%d_%H%M%S)
    backup_path="${BACKUP_BASE}/${ts}"
    mkdir -p "$backup_path"
    info "Backing up local saves to $backup_path ..."
    find "$SAVES_DIR" -maxdepth 1 -mindepth 1 \
        ! -name ".batosync_backups" \
        ! -name "*.batosync_backup" | while read -r item; do
        cp -a "$item" "$backup_path/" 2>/dev/null || true
    done
    # Prune oldest backups beyond BACKUP_KEEP
    local count
    count=$(ls -1 "$BACKUP_BASE" 2>/dev/null | wc -l)
    if [[ $count -gt $BACKUP_KEEP ]]; then
        ls -1t "$BACKUP_BASE" | tail -n +$(( BACKUP_KEEP + 1 )) | while read -r old; do
            rm -rf "${BACKUP_BASE:?}/${old}"
        done
    fi
    success "Backup complete (keeping last $BACKUP_KEEP)"
}

# Check server is reachable
if ! curl -sf --max-time 5 "${SERVER_URL}/health" > /dev/null 2>&1; then
    error "Cannot reach BatoSync server at ${SERVER_URL}"
    error "Check the server is running and the IP/port is correct."
    exit 1
fi
success "Server reachable"

# ── List games on server ───────────────────────────────────────────
if [[ "$MODE" == "list" ]]; then
    info "Games stored on server:"
    api_json GET /games | python3 -c "
import json, sys
data = json.load(sys.stdin)
games = sorted(data.get('games', []), key=lambda g: g['game'].lower())
if not games:
    print('  (no games saved yet)')
else:
    for g in games:
        print(f\"  {g['game']:<50} last saved: {g['latest_saved_at'][:19] if g['latest_saved_at'] else 'N/A'}  device: {g['latest_device']}\")
"
    exit 0
fi

# ── Status check ───────────────────────────────────────────────────
if [[ "$MODE" == "status" ]]; then
    info "Comparing local saves with server..."
    find_saves | \
    while IFS= read -r local_file; do
        rel="${local_file#$SAVES_DIR/}"
        game_dir=$(dirname "$rel")
        filename=$(basename "$local_file")
        game_name="${game_dir//\//_}_${filename}"
        is_excluded "$game_name" && continue

        cs=$(checksum "$local_file")
        encoded_game=$(python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "$game_name")
        result=$(api_json GET "/saves/${encoded_game}/check?checksum=$cs" 2>/dev/null || echo '{"status":"error"}')
        status=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status','?'))" 2>/dev/null)

        case "$status" in
            up_to_date)    success "$game_name — up to date" ;;
            outdated)      warn    "$game_name — server has newer save" ;;
            no_server_save)warn    "$game_name — not yet on server" ;;
            *)             error   "$game_name — status unknown" ;;
        esac
    done
    exit 0
fi

# ── Push local saves to server ─────────────────────────────────────
push_saves() {
    info "Pushing local saves to server..."
    local pushed=0 skipped=0 conflicts=0

    while IFS= read -r local_file; do
        rel="${local_file#$SAVES_DIR/}"
        game_dir=$(dirname "$rel")
        filename=$(basename "$local_file")
        game_name="${game_dir//\//_}_${filename}"

        if [[ -n "$FILTER_GAME" && "$game_name" != *"$FILTER_GAME"* ]]; then
            continue
        fi

        if is_excluded "$game_name"; then
            info "  Excluded: $game_name"
            continue
        fi

        file_mtime=$(python3 -c "import sys,os,datetime; print(datetime.datetime.utcfromtimestamp(os.path.getmtime(sys.argv[1])).isoformat())" "$local_file" 2>/dev/null) \
            || file_mtime=$(date -u +%Y-%m-%dT%H:%M:%S)

        local_cs=$(checksum "$local_file")
        encoded_game=$(python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "$game_name")

        check=$(api_json GET "/saves/${encoded_game}/check?checksum=${local_cs}" 2>/dev/null || echo '{}')
        up_to_date=$(echo "$check" | python3 -c "import json,sys; print(json.load(sys.stdin).get('up_to_date', False))" 2>/dev/null || echo 'False')

        if [[ "$up_to_date" == "True" ]]; then
            info "  Skipping $game_name (already on server)"
            ((skipped++)) || true
            continue
        fi

        # Conflict detection — server has a save from a different device
        server_device=$(echo "$check" | python3 -c "
import json,sys
d=json.load(sys.stdin)
s=d.get('server_save')
print(s['device'] if s else '')
" 2>/dev/null || echo '')

        if [[ -n "$server_device" && "$server_device" != "$DEVICE_NAME" ]]; then
            ((conflicts++)) || true
            if [[ "$CONFLICT_BEHAVIOR" == "skip" ]]; then
                warn "  ⚠ CONFLICT (skipped): $game_name — server has save from '$server_device', keeping server version"
                ((skipped++)) || true
                continue
            else
                warn "  ⚠ CONFLICT: $game_name — overwriting '$server_device' save with yours"
            fi
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            info "  [DRY-RUN] Would push: $game_name/$filename"
            continue
        fi

        info "  Pushing $game_name/$filename ..."
        result=$(api POST "/saves/${encoded_game}" \
            -F "file=@\"${local_file}\"" \
            -F "device=${DEVICE_NAME}" \
            -F "saved_at=${file_mtime}" \
            -F "original_path=${rel}" \
            2>/dev/null) || result='{"status":"error","message":"curl failed"}'

        status=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status','error'))" 2>/dev/null || echo 'error')
        case "$status" in
            saved)     success "  ✓ $game_name/$filename uploaded"; ((pushed++)) || true ;;
            duplicate) info    "  = $game_name/$filename already on server"; ((skipped++)) || true ;;
            *)         error   "  ✗ Failed to push $game_name/$filename: $result" ;;
        esac

    done < <(find_saves)

    if [[ $conflicts -gt 0 ]]; then
        warn "Push complete — uploaded: $pushed, skipped: $skipped, conflicts: $conflicts"
    else
        success "Push complete — uploaded: $pushed, skipped: $skipped"
    fi
}

# ── Pull latest saves from server ─────────────────────────────────
pull_saves() {
    info "Pulling latest saves from server..."
    local pulled=0 skipped=0

    # Sanity check — aborts if server looks blank vs last known state
    sanity_check || return 1

    # Full backup only on non-game-specific pulls (not during game launch)
    if [[ -z "$FILTER_GAME" ]]; then
        backup_saves
    fi

    games_json=$(api_json GET /games 2>/dev/null || echo '{}')
    games=$(echo "$games_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
games = data.get('games', [])
for g in games:
    print(g['game'])
" 2>/dev/null || true)

    if [[ -z "$games" ]]; then
        warn "No games found on server — nothing to pull"
        return
    fi

    set +e  # disable exit-on-error for individual game failures
    while IFS= read -r game_name; do
        [[ -z "$game_name" ]] && continue

        if [[ -n "$FILTER_GAME" && "$game_name" != *"$FILTER_GAME"* ]]; then
            continue
        fi

        is_excluded "$game_name" && continue

        encoded_game=$(python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "$game_name") || continue

        save_info=$(api_json GET "/saves/${encoded_game}" 2>/dev/null) || true
        server_cs=$(echo "$save_info" | python3 -c "
import json, sys
data = json.load(sys.stdin)
saves = data.get('saves', [])
print(saves[0]['checksum'] if saves else '')
" 2>/dev/null) || true

        [[ -z "$server_cs" ]] && continue

        # Prefer exact original_path lookup — faster and avoids false matches
        orig_path_check=$(echo "$save_info" | python3 -c "
import json, sys
data = json.load(sys.stdin)
saves = data.get('saves', [])
print(saves[0].get('original_path','') if saves else '')
" 2>/dev/null) || true

        if [[ -n "$orig_path_check" && -f "${SAVES_DIR}/${orig_path_check}" ]]; then
            local_file="${SAVES_DIR}/${orig_path_check}"
        else
            local_file=$(find_saves | while IFS= read -r f; do
                rel="${f#$SAVES_DIR/}"
                gdir=$(dirname "$rel")
                gfname=$(basename "$f")
                gname="${gdir//\//_}_${gfname%.*}"
                [[ "$gname" == "$game_name" ]] && echo "$f" && break
            done)
        fi

        if [[ -n "$local_file" ]]; then
            local_cs=$(checksum "$local_file")
            if [[ "$local_cs" == "$server_cs" ]]; then
                info "  = $game_name already up to date"
                ((skipped++)) || true
                continue
            fi
            if [[ "$DRY_RUN" == "true" ]]; then
                info "  [DRY-RUN] Would update: $game_name"
                continue
            fi
            cp "$local_file" "${local_file}.batosync_backup"
            info "  ↓ Downloading newer save for $game_name..."
            api GET "/saves/${encoded_game}/latest" -o "$local_file" 2>/dev/null || true
            success "  ✓ $game_name updated"
        else
            if [[ "$DRY_RUN" == "true" ]]; then
                info "  [DRY-RUN] Would download new: $game_name"
                continue
            fi
            orig_path=$(echo "$save_info" | python3 -c "
import json, sys
data = json.load(sys.stdin)
saves = data.get('saves', [])
print(saves[0].get('original_path','') if saves else '')
" 2>/dev/null) || true
            orig_fname=$(echo "$save_info" | python3 -c "
import json, sys
data = json.load(sys.stdin)
saves = data.get('saves', [])
print(saves[0].get('original_filename','save.srm') if saves else 'save.srm')
" 2>/dev/null) || orig_fname="save.srm"
            if [[ -n "$orig_path" ]]; then
                # Use exact original path recorded at push time
                dest_file="${SAVES_DIR}/${orig_path}"
            else
                # Fallback for saves pushed before original_path was recorded:
                # use system dir + original filename
                system_dir="${game_name%%_*}"
                dest_file="${SAVES_DIR}/${system_dir}/${orig_fname}"
            fi
            dest_dir="$(dirname "$dest_file")"
            mkdir -p "$dest_dir"
            info "  ↓ Downloading $game_name to $dest_file..."
            api GET "/saves/${encoded_game}/latest" -o "$dest_file" 2>/dev/null || { error "  ✗ Failed to download $game_name"; continue; }
            success "  ✓ $game_name downloaded (new on this device)"
        fi
        ((pulled++)) || true

    done <<< "$games"

    set -e  # restore exit-on-error
    success "Pull complete — downloaded: $pulled, already current: $skipped"
}

# ── Run selected mode ──────────────────────────────────────────────
case "$MODE" in
    push) push_saves ;;
    pull) pull_saves ;;
    sync)
        push_saves
        echo ""
        pull_saves
        ;;
esac

log ""
log "BatoSync finished — $(date '+%Y-%m-%d %H:%M:%S')"
