#!/usr/bin/env bash
# =====================================================================
#  Torang — atur / ganti KEY kelas (FLEKSIBEL, efek LANGSUNG)
#  ---------------------------------------------------------------------
#  Office membaca join-keys.json tiap kali ada yang join, jadi ganti key
#  TAK perlu restart office. Script ini:
#    1) set/ganti key kelas (key lama tetap valid — bisa banyak key),
#    2) set maxConcurrent besar (default 100) biar 4-10 murid muat,
#    3) cetak PERINTAH MURID siap-tempel (sudah isi IP guru + key).
#
#  Pakai (di WSL PC guru):
#    bash torang-key.sh <key> [maxConcurrent]
#    contoh:  bash torang-key.sh kelas-7a
#             bash torang-key.sh ujian-mtk 150
#    tanpa argumen -> pakai key dari config (atau ocj_test) & cetak perintah murid.
# =====================================================================
set -e
GDIR="$HOME/.torang-guru"
[ -f "$GDIR/config.env" ] && { set -a; . "$GDIR/config.env"; set +a; }
PORT="${TORANG_PORT:-19000}"
KEY="${1:-${TORANG_JOIN_KEY:-ocj_test}}"
MAX="${2:-${TORANG_MAXCONC:-100}}"

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

# --- tulis/perbarui key di join-keys.json (key lama dipertahankan) ---
python3 - "$JK" "$KEY" "$MAX" <<'PY'
import json, sys, os
path, key, mx = sys.argv[1], sys.argv[2], int(sys.argv[3])
data = {"keys": []}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        data = {"keys": []}
if not isinstance(data, dict) or "keys" not in data:
    data = {"keys": []}
keys = data["keys"]
item = next((k for k in keys if k.get("key") == key), None)
if item:
    item["reusable"] = True
    item["maxConcurrent"] = mx
    item.pop("expiresAt", None)
else:
    keys.append({"key": key, "used": False, "reusable": True, "maxConcurrent": mx,
                 "usedBy": None, "usedByAgentId": None, "usedAt": None})
data["keys"] = keys
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
os.replace(tmp, path)
print(f"[key] OK -> '{key}'  (maxConcurrent={mx}, reusable, tanpa kedaluwarsa)")
print(f"[key] Total key aktif di office: {len(keys)}  ->  {[k.get('key') for k in keys]}")
PY

# --- IP LAN guru untuk murid (utamakan 192.168.*, lalu 10.*, terakhir 172.*=sering adapter WSL) ---
ALLIP="$(cmd.exe /c 'ipconfig' 2>/dev/null | tr -d '\r' | awk '/IPv4/{print $NF}' | grep -E '^(192\.168|10\.|172\.)')"
IP="$(echo "$ALLIP" | grep -E '^192\.168\.' | head -1)"
[ -z "$IP" ] && IP="$(echo "$ALLIP" | grep -E '^10\.' | head -1)"
[ -z "$IP" ] && IP="$(echo "$ALLIP" | grep -E '^172\.' | head -1)"
[ -z "$IP" ] && IP="IP-GURU"

echo ""
echo "=================================================================="
echo "  Perintah untuk MURID (tempel di WSL mereka):"
echo "------------------------------------------------------------------"
echo "  TORANG_OFFICE_URL=http://$IP:$PORT TORANG_JOIN_KEY=$KEY \\"
echo "  bash <(curl -fsSL https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/install.sh)"
echo "=================================================================="
echo "  Office aktif      : http://$IP:$PORT   (key: $KEY)"
[ -n "$ALLIP" ] && echo "  Semua IP PC ini   : $(echo $ALLIP | tr '\n' ' ')  <- kalau murid tak konek, coba IP lain"
echo "  Ganti key kapan pun: bash torang-key.sh <key-baru>   (langsung berlaku, tanpa restart)"
echo "=================================================================="
