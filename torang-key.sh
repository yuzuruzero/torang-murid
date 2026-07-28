#!/usr/bin/env bash
# =====================================================================
#  Torang — atur KEY kelas + BIKIN installer murid otomatis (FLEKSIBEL)
#  ---------------------------------------------------------------------
#  Sekali jalan, script ini:
#    1) set/ganti key kelas di join-keys.json (maxConcurrent besar, efek langsung),
#    2) SALIN monitor ke frontend office -> disajikan di /static/monitor-client.js,
#    3) BIKIN installer murid di office -> /static/murid.sh (IP + key sudah terisi),
#    4) BIKIN file murid.env (buat dibagikan kalau mau cara file),
#    5) CETAK perintah murid yang murid tinggal PASTE (tanpa ketik IP/key).
#
#  Pakai (di WSL PC guru):
#    bash torang-key.sh                 -> pakai key sekarang, cetak perintah murid
#    bash torang-key.sh kelas-7a        -> ganti key jadi kelas-7a
#    bash torang-key.sh ujian 150       -> key 'ujian' batas 150 koneksi
# =====================================================================
set -e
GDIR="$HOME/.torang-guru"
[ -f "$GDIR/config.env" ] && { set -a; . "$GDIR/config.env"; set +a; }
PORT="${TORANG_PORT:-19000}"
KEY="${1:-${TORANG_JOIN_KEY:-ocj_test}}"
MAX="${2:-${TORANG_MAXCONC:-100}}"
BASE_URL="${TORANG_BASE_URL:-https://raw.githubusercontent.com/yuzuruzero/torang-murid/main}"
mkdir -p "$GDIR"

# --- cari folder office (ada backend/app.py) ---
OFF="${TORANG_OFFICE_DIR:-}"
if [ -z "$OFF" ] || [ ! -f "$OFF/backend/app.py" ]; then
  for c in "$HOME/torang-office" \
           /mnt/d/projects/torangapp/torang-office \
           /mnt/d/projects/torangapp/Star-Office-UI \
           "$HOME/Star-Office-UI"; do
    [ -f "$c/backend/app.py" ] && { OFF="$c"; break; }
  done
fi
[ -n "$OFF" ] && [ -f "$OFF/backend/app.py" ] || {
  echo "[key] Office tak ketemu. Jalankan install-guru dulu, atau set TORANG_OFFICE_DIR=/path/office"; exit 1; }
JK="$OFF/join-keys.json"
FE="$OFF/frontend"

# --- 1) tulis/perbarui key di join-keys.json (key lama dipertahankan) ---
python3 - "$JK" "$KEY" "$MAX" <<'PY'
import json, sys, os
path, key, mx = sys.argv[1], sys.argv[2], int(sys.argv[3])
data = {"keys": []}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as f: data = json.load(f)
    except Exception: data = {"keys": []}
if not isinstance(data, dict) or "keys" not in data: data = {"keys": []}
keys = data["keys"]
it = next((k for k in keys if k.get("key") == key), None)
if it:
    it["reusable"] = True; it["maxConcurrent"] = mx; it.pop("expiresAt", None)
else:
    keys.append({"key": key, "used": False, "reusable": True, "maxConcurrent": mx,
                 "usedBy": None, "usedByAgentId": None, "usedAt": None})
data["keys"] = keys
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
os.replace(tmp, path)
print(f"[key] '{key}' siap (maxConcurrent={mx}, reusable)")
PY

# --- IP LAN guru (utamakan 192.168.*, lalu 10.*, terakhir 172.*=sering adapter WSL) ---
ALLIP="$(cmd.exe /c 'ipconfig' 2>/dev/null | tr -d '\r' | awk '/IPv4/{print $NF}' | grep -E '^(192\.168|10\.|172\.)')"
IP="$(echo "$ALLIP" | grep -E '^192\.168\.' | head -1)"
[ -z "$IP" ] && IP="$(echo "$ALLIP" | grep -E '^10\.' | head -1)"
[ -z "$IP" ] && IP="$(echo "$ALLIP" | grep -E '^172\.' | head -1)"
[ -z "$IP" ] && IP="IP-GURU"
OFFICE_URL="http://$IP:$PORT"

# --- 2) sajikan monitor lewat office: frontend/monitor-client.js -> /static/monitor-client.js ---
if [ -d "$FE" ]; then
  MON_SRC=""
  for c in "$GDIR/monitor-client.js" "$OFF/monitor-client.js" "$OFF/frontend/monitor-client.js"; do
    [ -f "$c" ] && { MON_SRC="$c"; break; }
  done
  [ -n "$MON_SRC" ] && cp "$MON_SRC" "$FE/monitor-client.js" 2>/dev/null || true

  # --- 3) installer murid: office menyajikan /static/murid.sh (IP + key sudah terisi) ---
  {
    echo "#!/usr/bin/env bash"
    echo "# Installer MURID Torang - IP & key sudah otomatis. Cukup jalankan, tak perlu ketik apa pun."
    echo "OFFICE_URL='$OFFICE_URL'"
    echo "JOIN_KEY='$KEY'"
    cat <<'MURIDEOF'
set -e
command -v node >/dev/null 2>&1 || { echo "[Torang] 'node' tak ada. Pasang OpenClaw dulu di WSL ini."; exit 1; }
DIR="$HOME/.torang"; mkdir -p "$DIR"
echo "[Torang] Menyambung ke office $OFFICE_URL ..."
# unduh monitor dari OFFICE (tak perlu GitHub / tak kena cache CDN)
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$OFFICE_URL/static/monitor-client.js?t=$(date +%s)" -o "$DIR/monitor-client.js"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$DIR/monitor-client.js" "$OFFICE_URL/static/monitor-client.js"
else echo "[Torang] Butuh curl/wget."; exit 1; fi
[ -s "$DIR/monitor-client.js" ] || { echo "[Torang] Gagal unduh monitor dari office. Pastikan office guru menyala & PC ini sejaringan WiFi."; exit 1; }
printf 'TORANG_TARGET=star-office\nTORANG_SO_ROLE=student\nTORANG_OFFICE_URL=%s\nTORANG_JOIN_KEY=%s\n' "$OFFICE_URL" "$JOIN_KEY" > "$DIR/config.env"
cat > "$DIR/start.sh" <<'INNER'
#!/usr/bin/env bash
set -a; . "$HOME/.torang/config.env"; set +a
while true; do node "$HOME/.torang/monitor-client.js" || true; sleep 5; done
INNER
chmod +x "$DIR/start.sh"
HOOK='pgrep -f "$HOME/.torang/start.sh" >/dev/null 2>&1 || (nohup "$HOME/.torang/start.sh" >>"$HOME/.torang/monitor.log" 2>&1 &)'
grep -q "torang/start.sh" "$HOME/.bashrc" 2>/dev/null || { echo ""; echo "# Torang monitor auto-start"; echo "$HOOK"; } >> "$HOME/.bashrc"
pkill -f "$HOME/.torang/monitor-client.js" >/dev/null 2>&1 || true
sleep 1
nohup "$DIR/start.sh" >>"$DIR/monitor.log" 2>&1 &
sleep 2
echo "[Torang] Selesai! Karaktermu akan muncul di office guru dalam beberapa detik."
MURIDEOF
  } > "$FE/murid.sh"
  chmod +x "$FE/murid.sh" 2>/dev/null || true
fi

# --- 4) file .env buat dibagikan (cara file) ---
printf 'TORANG_TARGET=star-office\nTORANG_SO_ROLE=student\nTORANG_OFFICE_URL=%s\nTORANG_JOIN_KEY=%s\n' "$OFFICE_URL" "$KEY" > "$GDIR/murid.env"

# --- 5) cetak perintah murid ---
echo ""
echo "=================================================================="
echo "  CARA PALING GAMPANG — murid cukup PASTE 1 baris ini di WSL:"
echo "------------------------------------------------------------------"
echo "  bash <(curl -fsSL $OFFICE_URL/static/murid.sh)"
echo "------------------------------------------------------------------"
echo "  (IP & key sudah otomatis. Tak perlu ketik apa pun selain baris di atas.)"
echo "=================================================================="
echo "  Office aktif : $OFFICE_URL   (key: $KEY, maxConcurrent: $MAX)"
[ -n "$ALLIP" ] && echo "  Semua IP PC ini: $(echo $ALLIP | tr '\n' ' ')  <- kalau murid tak konek, ganti IP di URL"
echo "  File .env (kalau mau cara file): $GDIR/murid.env"
echo "  Ganti key kapan pun: bash torang-key.sh <key-baru>"
echo "=================================================================="
