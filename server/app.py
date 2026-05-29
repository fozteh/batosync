import os
import json
import hashlib
import shutil
from datetime import datetime, timezone
from flask import Flask, request, jsonify, send_file, abort, render_template
from werkzeug.utils import secure_filename
import logging

VERSION = "2.0.0"

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SAVES_DIR = os.environ.get("SAVES_DIR", "/data/saves")
META_FILE = os.path.join(SAVES_DIR, "metadata.json")
MAX_BACKUPS = int(os.environ.get("MAX_BACKUPS", 3))
API_KEY = os.environ.get("API_KEY", "")

os.makedirs(SAVES_DIR, exist_ok=True)


def require_api_key(f):
    from functools import wraps

    @wraps(f)
    def decorated(*args, **kwargs):
        if API_KEY:
            key = request.headers.get("X-API-Key", "")
            if key != API_KEY:
                return jsonify({"error": "Unauthorized"}), 401
        return f(*args, **kwargs)

    return decorated


def load_metadata():
    if os.path.exists(META_FILE):
        with open(META_FILE, "r") as f:
            return json.load(f)
    return {}


def save_metadata(meta):
    with open(META_FILE, "w") as f:
        json.dump(meta, f, indent=2)



def get_save_dir(game_name):
    safe_name = secure_filename(game_name)
    path = os.path.join(SAVES_DIR, safe_name)
    os.makedirs(path, exist_ok=True)
    return path, safe_name


def file_checksum(filepath):
    h = hashlib.md5()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def days_since(iso_timestamp):
    """Return number of days since an ISO timestamp string, or None."""
    try:
        dt = datetime.fromisoformat(iso_timestamp)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        delta = datetime.now(timezone.utc) - dt
        return delta.days
    except Exception:
        return None


# ─────────────────────────── ROUTES ────────────────────────────

@app.route("/", methods=["GET"])
def dashboard():
    return render_template(
        "dashboard.html",
        version=VERSION,
        api_key=API_KEY,
        max_backups=MAX_BACKUPS,
    )


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "service": "BatoSync", "version": VERSION})


@app.route("/games", methods=["GET"])
@require_api_key
def list_games():
    meta = load_metadata()
    games = []
    for game, data in meta.items():
        latest = data["saves"][0] if data["saves"] else None
        age_days = days_since(latest["uploaded_at"]) if latest else None
        games.append({
            "game": game,
            "save_count": len(data["saves"]),
            "latest_saved_at": latest["saved_at"] if latest else None,
            "latest_uploaded_at": latest["uploaded_at"] if latest else None,
            "latest_device": latest["device"] if latest else None,
            "latest_checksum": latest["checksum"] if latest else None,
            "latest_size": latest.get("size") if latest else None,
            "age_days": age_days,
        })
    games.sort(key=lambda g: g["latest_uploaded_at"] or "", reverse=True)
    return jsonify({"games": games})


@app.route("/saves/<game_name>", methods=["GET"])
@require_api_key
def get_save_info(game_name):
    meta = load_metadata()
    safe_name = secure_filename(game_name)
    if safe_name not in meta:
        return jsonify({"error": "No saves found for this game"}), 404
    return jsonify({"game": safe_name, "saves": meta[safe_name]["saves"]})


@app.route("/saves/<game_name>/latest", methods=["GET"])
@require_api_key
def download_latest(game_name):
    meta = load_metadata()
    safe_name = secure_filename(game_name)
    if safe_name not in meta or not meta[safe_name]["saves"]:
        return jsonify({"error": "No saves found for this game"}), 404

    latest = meta[safe_name]["saves"][0]
    filepath = latest["filepath"]

    if not os.path.exists(filepath):
        return jsonify({"error": "Save file missing on server"}), 500

    return send_file(
        filepath,
        as_attachment=True,
        download_name=os.path.basename(filepath),
        mimetype="application/octet-stream",
    )


@app.route("/saves/<game_name>/check", methods=["GET"])
@require_api_key
def check_save(game_name):
    client_checksum = request.args.get("checksum", "")
    meta = load_metadata()
    safe_name = secure_filename(game_name)

    if safe_name not in meta or not meta[safe_name]["saves"]:
        return jsonify({"status": "no_server_save", "up_to_date": False})

    latest = meta[safe_name]["saves"][0]
    server_checksum = latest["checksum"]

    if client_checksum == server_checksum:
        return jsonify({
            "status": "up_to_date",
            "up_to_date": True,
            "server_save": latest,
        })
    else:
        return jsonify({
            "status": "outdated",
            "up_to_date": False,
            "server_save": latest,
            "client_checksum": client_checksum,
        })


@app.route("/saves/<game_name>", methods=["POST"])
@require_api_key
def upload_save(game_name):
    if "file" not in request.files:
        return jsonify({"error": "No file provided"}), 400

    device = request.form.get("device", "unknown")
    client_saved_at = request.form.get("saved_at", datetime.utcnow().isoformat())
    original_path = request.form.get("original_path", "")

    uploaded = request.files["file"]
    if uploaded.filename == "":
        return jsonify({"error": "Empty filename"}), 400

    save_dir, safe_name = get_save_dir(game_name)
    original_filename = secure_filename(uploaded.filename)

    ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    stored_filename = f"{ts}_{original_filename}"
    stored_path = os.path.join(save_dir, stored_filename)

    uploaded.save(stored_path)
    checksum = file_checksum(stored_path)
    size = os.path.getsize(stored_path)

    meta = load_metadata()
    if safe_name not in meta:
        meta[safe_name] = {"saves": []}

    existing_checksums = [s["checksum"] for s in meta[safe_name]["saves"]]
    if checksum in existing_checksums:
        os.remove(stored_path)
        logger.info(f"Duplicate save ignored for {safe_name} from {device}")
        return jsonify({
            "status": "duplicate",
            "message": "Identical save already exists on server",
            "checksum": checksum,
        })

    new_save = {
        "filename": stored_filename,
        "original_filename": original_filename,
        "original_path": original_path,
        "filepath": stored_path,
        "device": device,
        "saved_at": client_saved_at,
        "uploaded_at": datetime.utcnow().isoformat(),
        "checksum": checksum,
        "size": size,
    }

    meta[safe_name]["saves"].insert(0, new_save)
    evicted = meta[safe_name]["saves"][MAX_BACKUPS:]
    meta[safe_name]["saves"] = meta[safe_name]["saves"][:MAX_BACKUPS]

    for old_save in evicted:
        try:
            if os.path.exists(old_save["filepath"]):
                os.remove(old_save["filepath"])
        except Exception as e:
            logger.warning(f"Could not remove old save: {e}")

    save_metadata(meta)
    logger.info(f"Saved {safe_name} from {device} — {checksum[:8]}")

    return jsonify({
        "status": "saved",
        "game": safe_name,
        "checksum": checksum,
        "size": size,
        "device": device,
        "backups_kept": len(meta[safe_name]["saves"]),
    })


@app.route("/saves/<game_name>/<int:index>", methods=["GET"])
@require_api_key
def download_backup(game_name, index):
    meta = load_metadata()
    safe_name = secure_filename(game_name)
    if safe_name not in meta:
        return jsonify({"error": "No saves found"}), 404

    saves = meta[safe_name]["saves"]
    if index >= len(saves):
        return jsonify({"error": f"No backup at index {index}"}), 404

    filepath = saves[index]["filepath"]
    if not os.path.exists(filepath):
        return jsonify({"error": "Backup file missing"}), 500

    return send_file(
        filepath,
        as_attachment=True,
        download_name=os.path.basename(filepath),
        mimetype="application/octet-stream",
    )


@app.route("/devices", methods=["GET"])
@require_api_key
def list_devices():
    meta = load_metadata()
    device_map = {}
    for data in meta.values():
        for save in data["saves"]:
            dev = save.get("device", "unknown")
            ts = save.get("uploaded_at")
            if dev not in device_map or (ts and ts > device_map[dev]["last_seen"]):
                device_map[dev] = {"last_seen": ts}
    return jsonify({"devices": [{"name": k, **v} for k, v in device_map.items()]})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
