#!/usr/bin/env bash
# =====================================================================
#  TORANG - Pasang plugin "torang-events" (HATCH INSTAN / Cara B)
#  Jalankan di WSL yang ada OpenClaw:
#    curl -fsSL https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/install-plugin-torang.sh | bash
#
#  Efek: subagent yang BARU LAHIR langsung muncul di office (Ruang Tamu) tanpa
#  menunggu polling. Cocok untuk demo ("agent langsung lahir di office").
#
#  Prasyarat: OpenClaw terpasang; monitor Torang sudah dipasang (biar ada
#  ~/.torang/config.env berisi OFFICE_URL + JOIN_KEY). Kalau belum, sertakan env:
#    TORANG_OFFICE_URL=http://IP-GURU:19000 TORANG_JOIN_KEY=ocj_test bash <(curl ...)
#
#  CATATAN PENTING: plugin WAJIB di filesystem Linux (BUKAN /mnt/d — world-writable
#  -> diblok OpenClaw). Installer ini menaruhnya di ~/.torang-plugin/.
# =====================================================================
set -e
BASE_URL="${TORANG_BASE_URL:-https://raw.githubusercontent.com/yuzuruzero/torang-murid/main}"
DIR="$HOME/.torang-plugin/torang-events"
say(){ echo "[torang-plugin] $*"; }
die(){ echo "[torang-plugin] GAGAL: $*" >&2; exit 1; }

command -v openclaw >/dev/null 2>&1 || die "'openclaw' tak ada di PATH. Jalankan di WSL yang ada OpenClaw."
mkdir -p "$DIR"

# --- ambil file plugin: utamakan lokal (star-office-tools), kalau tak ada -> unduh ---
SRC_LOCAL=""
for c in \
  "$(dirname "$0")/torang-events" \
  "/mnt/d/torang/torangapp/torangapp/star-office-tools/torang-events" \
  "$(pwd)/torang-events" ; do
  [ -f "$c/index.ts" ] && { SRC_LOCAL="$c"; break; }
done
for f in package.json openclaw.plugin.json index.ts; do
  if [ -n "$SRC_LOCAL" ]; then
    cp "$SRC_LOCAL/$f" "$DIR/$f"
  else
    curl -fsSL "$BASE_URL/torang-events/$f" -o "$DIR/$f" || die "gagal ambil $f (cek repo torang-murid punya folder torang-events/)."
  fi
  [ -s "$DIR/$f" ] || die "$f kosong."
done
say "File plugin siap di $DIR"

# --- pastikan config office ada (plugin baca ~/.torang/config.env dst) ---
if [ ! -f "$HOME/.torang/config.env" ] && [ ! -f "$HOME/.torang-guru/config.env" ]; then
  printf 'TORANG_OFFICE_URL=%s\nTORANG_JOIN_KEY=%s\n' \
    "${TORANG_OFFICE_URL:-http://127.0.0.1:19000}" "${TORANG_JOIN_KEY:-ocj_test}" > "$HOME/.torang-events.env"
  say "Config office belum ada -> ditulis ke ~/.torang-events.env (${TORANG_OFFICE_URL:-http://127.0.0.1:19000})"
fi

# --- pasang + aktifkan + restart gateway ---
say "plugins install --link ..."
openclaw plugins install --link "$DIR" 2>&1 | tail -3 || say "(mungkin sudah terpasang, lanjut)"
say "plugins enable torang-events ..."
openclaw plugins enable torang-events 2>&1 | tail -2 || true
say "gateway restart ..."
if ! openclaw gateway restart 2>&1 | tail -3; then
  say "PERINGATAN: gateway restart gagal. Restart manual: 'openclaw gateway restart' (atau 'openclaw gateway run')."
fi

echo ""
say "=================== SELESAI ==================="
say "Verifikasi hook terdaftar:"
say "  openclaw plugins inspect torang-events --runtime --json"
say "  openclaw plugins doctor"
say "Uji: suruh OpenClaw delegasi tugas ke subagent -> karakter '(temp)' muncul"
say "     INSTAN di Ruang Tamu, pindah ke Web/Data/CS saat pakai tool, keluar saat selesai."
say "Lihat log plugin di log Gateway (baris '[torang-events] ...')."
say "Nonaktifkan: openclaw plugins disable torang-events && openclaw gateway restart"
say "==============================================="
