#!/usr/bin/env bash
# =====================================================================
#  TORANG - Pemasang Monitor Murid (versi hosting / curl|bash)
#  Pasang di WSL (setelah OpenClaw):
#    curl -fsSL https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/install.sh | bash
#  atau via server sendiri:
#    curl -fsSL https://torang.ai/murid/install.sh | bash
# =====================================================================
set -e

# --- URL tempat monitor-client.js berada. GANTI sesuai repo/hosting-mu ---
BASE_URL="${TORANG_BASE_URL:-https://raw.githubusercontent.com/yuzuruzero/torang-murid/main}"
# --- office guru & join key (boleh dioverride lewat env saat pasang) ---
OFFICE_URL="${TORANG_OFFICE_URL:-http://192.168.18.12:19000}"
JOIN_KEY="${TORANG_JOIN_KEY:-ocj_test}"

DIR="$HOME/.torang"
mkdir -p "$DIR"
echo "[Torang] Memasang monitor murid -> office $OFFICE_URL"

fetch() {
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2";
  elif command -v wget >/dev/null 2>&1; then wget -qO "$2" "$1";
  else echo "[Torang] Butuh 'curl' atau 'wget'."; exit 1; fi
}

echo "[Torang] Mengunduh monitor dari $BASE_URL ..."
fetch "$BASE_URL/monitor-client.js" "$DIR/monitor-client.js"
if [ ! -s "$DIR/monitor-client.js" ]; then
  echo "[Torang] GAGAL mengunduh monitor. Cek BASE_URL / koneksi internet."; exit 1
fi

# ---- konfigurasi ----
cat > "$DIR/config.env" <<EOF
TORANG_TARGET=star-office
TORANG_SO_ROLE=student
TORANG_OFFICE_URL=$OFFICE_URL
TORANG_JOIN_KEY=$JOIN_KEY
EOF

# ---- launcher: auto-reconnect, nama = nama komputer ----
cat > "$DIR/start.sh" <<'EOF'
#!/usr/bin/env bash
set -a; . "$HOME/.torang/config.env"; set +a
export TORANG_AGENT_NAME="$(hostname)"
while true; do
  node "$HOME/.torang/monitor-client.js" || true
  sleep 5
done
EOF
chmod +x "$DIR/start.sh"

# ---- auto-start tiap buka WSL (idempoten) ----
HOOK='pgrep -f "$HOME/.torang/start.sh" >/dev/null 2>&1 || (nohup "$HOME/.torang/start.sh" >>"$HOME/.torang/monitor.log" 2>&1 &)'
if ! grep -q "torang/start.sh" "$HOME/.bashrc" 2>/dev/null; then
  { echo ""; echo "# Torang monitor (auto-start saat buka WSL)"; echo "$HOOK"; } >> "$HOME/.bashrc"
fi

command -v node >/dev/null 2>&1 || echo "[Torang] PERINGATAN: 'node' tak ada di WSL ini - pastikan Node/OpenClaw terpasang."

# ---- jalankan sekarang ----
pkill -f "$HOME/.torang/start.sh" >/dev/null 2>&1 || true
pkill -f "$HOME/.torang/monitor-client.js" >/dev/null 2>&1 || true
sleep 1
nohup "$DIR/start.sh" >>"$DIR/monitor.log" 2>&1 &
sleep 2
echo "[Torang] Selesai. Monitor jalan di latar & auto-start tiap buka WSL."
echo "[Torang] Agen PC ini muncul di office guru: $OFFICE_URL"
echo "[Torang] Log: $DIR/monitor.log   |  Berhenti: pkill -f torang/start.sh ; pkill -f monitor-client.js"
