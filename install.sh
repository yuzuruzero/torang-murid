#!/usr/bin/env bash
# =====================================================================
#  TORANG — PEMASANG MURID (SATU BARIS, tanpa mengetik apa pun)
#
#    bash <(curl -fsSL https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/install.sh)
#
#  Sekali jalan, murid dapat DUA-DUANYA:
#    1. monitor  -> karakter tetap (main + worker) muncul & pindah ruang
#    2. plugin   -> subagent yang lahir muncul INSTAN di Ruang Tamu
#
#  IP guru sudah DIPATRI di bawah. Kalau IP guru berubah, installer menyapu
#  subnet sendiri, jadi murid tetap tak perlu mengetik apa pun.
#
#  Boleh dioverride fasilitator (TIDAK pernah wajib):
#    TORANG_OFFICE_URL   paksa alamat office, mis. http://10.10.10.7:19000
#    TORANG_JOIN_KEY     paksa join key kelas
#    TORANG_BASE_URL     ambil berkas dari repo/hosting lain
#    TORANG_HOME         akar pemasangan (default $HOME) — dipakai saat menguji
# =====================================================================

# CATATAN: sengaja TIDAK memakai `set -e`. Plugin yang gagal tidak boleh
# menggagalkan pemasangan monitor; tiap langkah kritis diperiksa sendiri.
set -u

# --- nilai yang dipatri saat installer dibuat di PC guru ---------------
OFFICE_IP_DEFAULT="10.10.10.10"
OFFICE_PORT_DEFAULT="19000"
JOIN_KEY_DEFAULT="ocj_test"

BASE_URL="${TORANG_BASE_URL:-https://raw.githubusercontent.com/yuzuruzero/torang-murid/main}"
THOME="${TORANG_HOME:-$HOME}"
DIR="$THOME/.torang"
PLUGDIR="$THOME/.torang-plugin/torang-events"
MONDIR="${TORANG_CONFIG_DIR:-$THOME/.torang-monitor}"
PORT="$OFFICE_PORT_DEFAULT"

say()  { echo "[Torang] $*"; }
warn() { echo "[Torang] ! $*"; }
die()  { echo ""; echo "[Torang] BERHENTI: $*"; exit 1; }

command -v curl >/dev/null 2>&1 || die "'curl' tidak ada. Pasang dulu: sudo apt install -y curl"

echo ""
say "=============== PEMASANGAN TORANG (MURID) ==============="

# =====================================================================
# 1) CARI OFFICE GURU
#    urutan: env fasilitator -> IP dipatri -> sapu subnet
# =====================================================================
health_ok() { curl -fsS --max-time "${2:-1}" "$1/health" >/dev/null 2>&1; }

# subnet /24 milik PC ini. Di WSL, `hostname -I` memberi 172.x internal yang
# TIDAK berguna — yang benar adalah IP LAN Windows-nya, dibaca lewat ipconfig.
my_subnets() {
  cmd.exe /c 'ipconfig' 2>/dev/null | tr -d '\r' | awk '/IPv4/{print $NF}' \
    | grep -E '^(192\.168\.|10\.)' | sed -E 's/\.[0-9]+$//' | sort -u
  hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^(192\.168\.|10\.)' | sed -E 's/\.[0-9]+$//' | sort -u
}

# Sapu satu /24: paralel 64, timeout 1 detik per host, ambil penjawab pertama.
sweep_subnet() {
  seq 1 254 \
    | xargs -P 64 -I{} sh -c "curl -fsS --max-time 1 http://$1.{}:$PORT/health >/dev/null 2>&1 && echo $1.{}" 2>/dev/null \
    | head -1
}

OFFICE_URL=""
JOIN_KEY="${TORANG_JOIN_KEY:-$JOIN_KEY_DEFAULT}"

if [ -n "${TORANG_OFFICE_URL:-}" ]; then
  OFFICE_URL="${TORANG_OFFICE_URL%/}"
  say "Memakai alamat office dari fasilitator: $OFFICE_URL"
else
  say "Menghubungi office guru di $OFFICE_IP_DEFAULT ..."
  if health_ok "http://$OFFICE_IP_DEFAULT:$PORT" 1; then
    OFFICE_URL="http://$OFFICE_IP_DEFAULT:$PORT"
    say "Tersambung."
  else
    warn "Tidak menjawab. IP guru mungkin berubah — mencari di jaringan ini ..."
    SUBS="$(my_subnets; echo "$OFFICE_IP_DEFAULT" | sed -E 's/\.[0-9]+$//')"
    for sub in $(echo "$SUBS" | sort -u); do
      say "  menyapu $sub.0/24 ..."
      HIT="$(sweep_subnet "$sub")"
      if [ -n "$HIT" ]; then
        OFFICE_URL="http://$HIT:$PORT"
        say "  KETEMU: office guru ada di $HIT"
        break
      fi
    done
  fi
fi

if [ -z "$OFFICE_URL" ]; then
  echo ""
  echo "  Tidak menemukan office guru di jaringan ini."
  echo ""
  echo "  Dua kemungkinan, tunjukkan pesan ini ke pengajar:"
  echo "    1. Office di komputer guru BELUM MENYALA."
  echo "    2. Komputer ini tidak satu jaringan dengan komputer guru"
  echo "       (mis. masih pakai hotspot/HP sendiri, bukan wifi kelas)."
  echo ""
  echo "  Kalau pengajar sudah tahu IP-nya, jalankan begini:"
  echo "    TORANG_OFFICE_URL=http://IP-GURU:$PORT bash <(curl -fsSL $BASE_URL/install.sh)"
  die "office guru tidak ditemukan."
fi

# =====================================================================
# 2) NAMA KARAKTER
#    Yang tampil: "<username> · <nama agent>".
#    Awalan diambil monitor lewat soLabelDefault(): username Ubuntu dulu,
#    lalu $USER/$USERNAME, dan nama device HANYA sebagai jalan terakhir.
#    Paruh kedua datang dari `openclaw agents list` — karena itu start.sh
#    TIDAK BOLEH lagi menyetel TORANG_AGENT_NAME=$(hostname): baris itu
#    membajak nama agent dan menimpanya dengan nama komputer.
# =====================================================================
detect_label() {
  local u
  u="$(id -un 2>/dev/null || true)"
  if [ -n "$u" ] && [ "$u" != "root" ]; then echo "$u"; return; fi
  u="${USER:-${USERNAME:-}}"
  if [ -n "$u" ] && [ "$u" != "root" ]; then echo "$u"; return; fi
  hostname
}
LABEL="$(detect_label)"
LABEL_IS_DEVICE=0
[ "$LABEL" = "$(hostname)" ] && LABEL_IS_DEVICE=1

# =====================================================================
# 3) MONITOR
# =====================================================================
mkdir -p "$DIR" || die "tidak bisa membuat folder $DIR"
say "Mengunduh monitor ..."
curl -fsSL "$BASE_URL/monitor-client.js" -o "$DIR/monitor-client.js" 2>/dev/null
[ -s "$DIR/monitor-client.js" ] || die "gagal mengunduh monitor-client.js. Cek koneksi internet."

cat > "$DIR/config.env" <<EOF
TORANG_TARGET=star-office
TORANG_SO_ROLE=student
TORANG_OFFICE_URL=$OFFICE_URL
TORANG_JOIN_KEY=$JOIN_KEY
# CLI OpenClaw bisa sangat lambat di PC kelas (terukur 37-91 dtk untuk
# 'agents list'). 90 dtk bawaan kadang tak cukup -> roster agent gagal terbaca.
TORANG_CLI_TIMEOUT_MS=120000
# Ruang aktivitas ditahan 2 menit. Default 25 dtk lebih pendek daripada waktu
# karakter berjalan antar-ruang di mesin lambat, jadi sinyal ruang kedaluwarsa
# di tengah jalan dan karakter berbalik arah tepat di depan pintu.
TORANG_ACTIVITY_LINGER_MS=120000
EOF

# start.sh — TANPA TORANG_AGENT_NAME (lihat bagian 2).
cat > "$DIR/start.sh" <<EOF
#!/usr/bin/env bash
set -a; . "$DIR/config.env"; set +a
# [TORANG] KUNCI TUNGGAL — satu loop start.sh per path, titik.
# Tanpa ini, tiap terminal WSL yang dibuka saat monitor sedang dalam jeda
# restart 5 detik akan menyalakan loop tambahan. Di PC guru sempat terkumpul
# enam loop sekaligus, masing-masing membangunkan Node tiap 5 detik.
exec 9>"$DIR/start.lock" 2>/dev/null || true
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || { echo "[Torang] loop lain sudah memegang kunci — keluar."; exit 0; }
fi
while true; do
  node "$DIR/monitor-client.js" || true
  sleep 5
done
EOF
chmod +x "$DIR/start.sh"

# auto-start tiap buka WSL (idempoten — hanya ditulis sekali)
if [ -w "$THOME/.bashrc" ] || [ ! -e "$THOME/.bashrc" ]; then
  HOOK="pgrep -f \"$DIR/start.sh\" >/dev/null 2>&1 || (nohup \"$DIR/start.sh\" >>\"$DIR/monitor.log\" 2>&1 &)"
  if ! grep -q "torang/start.sh" "$THOME/.bashrc" 2>/dev/null; then
    { echo ""; echo "# Torang monitor (auto-start saat buka WSL)"; echo "$HOOK"; } >> "$THOME/.bashrc"
  fi
fi

command -v node >/dev/null 2>&1 || warn "'node' tak ada di WSL ini — pasang Node/OpenClaw dulu, monitor belum bisa jalan."

# client_id LAMA JANGAN DISENTUH: itu yang bikin murid dapat karakter yang SAMA
# setiap kali memasang ulang / hari berikutnya.
KARAKTER_LAMA=0
[ -s "$MONDIR/client_id" ] && KARAKTER_LAMA=1

# hanya matikan monitor MILIK MURID (jangan sentuh proses lain di PC ini)
pkill -f "$DIR/start.sh"        >/dev/null 2>&1 || true
pkill -f "$DIR/monitor-client.js" >/dev/null 2>&1 || true
sleep 1
nohup "$DIR/start.sh" >>"$DIR/monitor.log" 2>&1 &
say "Monitor jalan di latar."

# =====================================================================
# 4) PLUGIN torang-events  (WAJIB di filesystem Linux, jangan /mnt/)
#    Gagal di sini TIDAK menggagalkan pemasangan monitor.
# =====================================================================
PLUGIN_OK=0
PLUGIN_PESAN=""
OC=""
for c in openclaw "$HOME/.npm-global/bin/openclaw" /usr/local/bin/openclaw; do
  command -v "$c" >/dev/null 2>&1 && { OC="$c"; break; }
done

if [ -z "$OC" ]; then
  PLUGIN_PESAN="OpenClaw belum terpasang di WSL ini"
else
  case "$PLUGDIR" in
    /mnt/*) PLUGIN_PESAN="folder plugin ada di /mnt (dilarang OpenClaw)" ;;
    *)
      say "Memasang plugin torang-events ..."
      mkdir -p "$PLUGDIR"
      GAGAL=0
      for f in index.ts package.json openclaw.plugin.json; do
        curl -fsSL "$BASE_URL/torang-events/$f" -o "$PLUGDIR/$f" 2>/dev/null
        [ -s "$PLUGDIR/$f" ] || GAGAL=1
      done
      if [ "$GAGAL" = "1" ]; then
        PLUGIN_PESAN="gagal mengunduh berkas plugin"
      else
        "$OC" plugins install --link "$PLUGDIR" >/dev/null 2>&1 || true
        "$OC" plugins enable torang-events   >/dev/null 2>&1 || true
        if "$OC" gateway restart >/dev/null 2>&1; then
          PLUGIN_OK=1
        else
          PLUGIN_PESAN="gateway gagal di-restart"
        fi
      fi
      ;;
  esac
fi

# =====================================================================
# 5) SWAKRITERIA — benar-benar coba masuk kantor
# =====================================================================
UJI_ID="uji-$(date +%s)-$$"
RESP="$(curl -fsS --max-time 8 -X POST "$OFFICE_URL/join-agent" \
  -H 'Content-Type: application/json' \
  -d "{\"client_id\":\"$UJI_ID\",\"joinKey\":\"$JOIN_KEY\",\"name\":\"$LABEL · uji pemasangan\",\"state\":\"idle\",\"detail\":\"uji\",\"room\":\"tamu\"}" 2>/dev/null)"
MASUK=0
case "$RESP" in *'"ok": true'*|*'"ok":true'*) MASUK=1 ;; esac
# bersihkan karakter uji supaya tidak menumpuk di layar depan
AID="$(printf '%s' "$RESP" | sed -n 's/.*"agentId"[: ]*"\([^"]*\)".*/\1/p')"
[ -n "$AID" ] && curl -fsS --max-time 5 -X POST "$OFFICE_URL/leave-agent" \
  -H 'Content-Type: application/json' -d "{\"agentId\":\"$AID\",\"joinKey\":\"$JOIN_KEY\"}" >/dev/null 2>&1

# =====================================================================
# 6) LAPORAN
# =====================================================================
echo ""
echo "==========================================================="
if [ "$MASUK" = "1" ]; then
  echo "  BERHASIL — lihat layar depan, karakter kamu sudah masuk kantor."
  echo "  Namamu muncul sebagai:  $LABEL · <nama agent>"
else
  echo "  BELUM BERHASIL."
  echo ""
  echo "  Lapor ke pengajar, sebutkan persis ini:"
  echo "    - alamat office : $OFFICE_URL"
  echo "    - join key      : $JOIN_KEY"
  if [ -n "$RESP" ]; then
    echo "    - jawaban office: $RESP"
  else
    echo "    - jawaban office: (kosong / tidak menjawab)"
  fi
fi
echo "==========================================================="
echo ""
echo "  Untuk fasilitator:"
echo "    office   : $OFFICE_URL"
echo "    join key : $JOIN_KEY"
echo "    awalan   : $LABEL"
if [ "$PLUGIN_OK" = "1" ]; then
  echo "    plugin   : terpasang & gateway di-restart"
else
  echo "    plugin   : DILEWATI — $PLUGIN_PESAN"
  echo "               pasang OpenClaw dulu, lalu ulangi baris yang sama:"
  echo "               bash <(curl -fsSL $BASE_URL/install.sh)"
fi
if [ "$KARAKTER_LAMA" = "1" ]; then
  echo "    karakter : memakai client_id lama (karakter tetap sama seperti sebelumnya)"
else
  echo "    karakter : client_id baru dibuat pada monitor jalan pertama"
fi
if [ "$LABEL_IS_DEVICE" = "1" ]; then
  echo ""
  warn "Awalan nama memakai NAMA DEVICE ('$LABEL'), bukan username."
  warn "Biasanya karena WSL ini dipakai sebagai root. Buat user biasa,"
  warn "atau setel TORANG_LABEL=<nama murid> di $DIR/config.env."
fi
echo ""
echo "  Log     : $DIR/monitor.log"
echo "  Berhenti: pkill -f '$DIR/start.sh' ; pkill -f '$DIR/monitor-client.js'"
echo ""
