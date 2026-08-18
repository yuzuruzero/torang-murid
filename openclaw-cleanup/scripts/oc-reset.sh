#!/usr/bin/env bash
# =====================================================================
#  OPENCLAW-CLEANUP -- RESET KE FRESH INSTALL  v1.2
#
#  Urutan kerja:
#    1. BACKUP config & credential penting -> ~/openclaw-backup-<tanggal>/
#       (kalau backup GAGAL, TIDAK ADA yang dihapus -- berhenti)
#    2. Stop service + hapus semua state/config/cache OpenClaw & Hermes
#       (memakai mesin oc-uninstall.sh; folder backup DILINDUNGI pagar)
#    3. Install ulang OpenClaw & Hermes versi terbaru (installer resmi)
#    4. Setup awal gateway; sisanya (onboarding, API key, Telegram)
#       interaktif -- dilaporkan sebagai langkah lanjutan
#
#  Torang Event TIDAK ikut di-reset kecuali --dengan-torang.
#
#  PAKAI:
#    bash oc-reset.sh --dry-run    # lihat rencana lengkap dulu
#    bash oc-reset.sh              # interaktif (konfirmasi y/ya)
#    bash oc-reset.sh -y           # tanpa tanya -- HANYA setelah pengguna
#                                  # memberi konfirmasi eksplisit di percakapan
#  PILIHAN:
#    --dry-run | -n      rencana saja
#    -y | --yes          tanpa prompt internal
#    --sudo              teruskan ke mesin uninstall (unit sistem, /etc, dll)
#    --dengan-torang     ikut cabut Torang Event (monitor+plugin) saat bersih-bersih
#    --arsip             arsipkan workspace/sesi murid dulu (teruskan ke uninstall)
#    --tanpa-install     backup + bersihkan saja, JANGAN install ulang
#    --bantuan | -h      bantuan
#
#  KELUAR: 0 = selesai | 1 = gagal/batal (tidak ada yang dihapus bila backup
#          gagal) | 2 = pembersihan menyisakan jejak (install DIBATALKAN)
# =====================================================================
set -uo pipefail

VERSI="1.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
URL_OC="https://openclaw.ai/install.sh"
URL_HM="https://hermes-agent.nousresearch.com/install.sh"

KERING=0; PAKSA=0; PAKAI_SUDO=0; DENGAN_TORANG=0; ARSIP=0; TANPA_INSTALL=0
for a in "$@"; do
  case "$a" in
    --dry-run|--kering|-n) KERING=1 ;;
    -y|--yes|--paksa)      PAKSA=1 ;;
    --sudo)                PAKAI_SUDO=1 ;;
    --dengan-torang)       DENGAN_TORANG=1 ;;
    --arsip)               ARSIP=1 ;;
    --tanpa-install)       TANPA_INSTALL=1 ;;
    --bantuan|-h|--help)   sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Pilihan tak dikenal: $a  (pakai --bantuan)"; exit 1 ;;
  esac
done

[ -n "${HOME:-}" ] || { echo "GAGAL: \$HOME kosong. Batal."; exit 1; }
[ -d "$HOME" ]     || { echo "GAGAL: \$HOME bukan folder. Batal."; exit 1; }
if [ "$(id -u)" = "0" ]; then
  echo "GAGAL: jangan jalankan sebagai root/sudo. Jalankan sebagai user biasa."
  exit 1
fi
[ -f "$SCRIPT_DIR/oc-uninstall.sh" ] || { echo "GAGAL: oc-uninstall.sh tidak ditemukan di $SCRIPT_DIR"; exit 1; }

OC_STATE="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
CAP="$(date +%Y%m%d-%H%M%S)"
BK="$HOME/openclaw-backup-$CAP"
LOG="/tmp/oc-reset-$CAP.log"
: > "$LOG"
say()  { printf '%s\n' "$*" | tee -a "$LOG"; }
judul(){ say ""; say "=== $* ==="; }
ada()  { command -v "$1" >/dev/null 2>&1; }

say "OPENCLAW-CLEANUP -- RESET KE FRESH INSTALL v$VERSI"
say "waktu : $(date '+%Y-%m-%d %H:%M:%S')   user: $(id -un)   HOME: $HOME"
say "backup: $BK"
say "log   : $LOG"
[ "$KERING" = 1 ] && say ">>> MODE DRY-RUN -- tidak ada yang dihapus/diinstal <<<"

# ---------- konfirmasi internal ----------
if [ "$KERING" = 0 ] && [ "$PAKSA" = 0 ]; then
  if [ ! -t 0 ]; then
    say "GAGAL: stdin bukan terminal. Jalankan --dry-run dulu, minta persetujuan"
    say "       pengguna, baru ulangi dengan -y."
    exit 1
  fi
  say ""
  say "Ini akan MENGHAPUS state/config OpenClaw & Hermes (setelah backup),"
  say "lalu memasang ulang versi terbaru."
  printf 'Lanjut reset? (y = lanjut, lainnya batal): '
  read -r JWB
  JWB="${JWB//$'\r'/}"   # buang CR: tty aneh/paste Windows mengirim jawaban+CR
  JWB="${JWB,,}"         # huruf kecil semua: y/Y/ya/YA sama saja
  case "$JWB" in y|ya|yes) ;; *) say "Dibatalkan. Tidak ada yang diubah."; exit 1 ;; esac
fi

# =====================================================================
#  TAHAP 1 -- PRA-CEK JARINGAN (sebelum menghapus apa pun!)
# =====================================================================
judul "TAHAP 1/4 -- pra-cek"
if [ "$TANPA_INSTALL" = 0 ]; then
  if ada curl; then
    NET_OK=1
    for u in "$URL_OC" "$URL_HM"; do
      if curl -fsI --max-time 10 "$u" >/dev/null 2>&1; then
        say "  bisa menjangkau $u"
      else
        say "  TIDAK bisa menjangkau $u"
        NET_OK=0
      fi
    done
    if [ "$NET_OK" = 0 ] && [ "$KERING" = 0 ]; then
      say "  GAGAL: installer tidak terjangkau. TIDAK ADA yang dihapus."
      say "  Cek jaringan/proxy dulu, atau pakai --tanpa-install untuk backup+bersih saja."
      exit 1
    fi
  else
    say "  GAGAL: curl tidak ada -- install ulang tak mungkin. TIDAK ADA yang dihapus."
    exit 1
  fi
else
  say "  --tanpa-install: lewati cek jaringan (tidak akan install ulang)"
fi

# =====================================================================
#  TAHAP 2 -- BACKUP  (gagal backup = berhenti TOTAL, tidak ada yang dihapus)
# =====================================================================
judul "TAHAP 2/4 -- backup config & credential -> $BK"
BK_GAGAL=0; BK_ADA=0

simpan() {  # $1 = sumber, $2 = tujuan relatif di dalam backup
  local src="$1" dst="$BK/$2"
  [ -e "$src" ] || return 0
  BK_ADA=1
  if [ "$KERING" = 1 ]; then say "  [dry-run] backup: $src -> $2"; return 0; fi
  mkdir -p "$(dirname "$dst")" 2>>"$LOG" || { say "  GAGAL mkdir untuk $2"; BK_GAGAL=1; return 1; }
  if cp -a "$src" "$dst" 2>>"$LOG"; then say "  backup: $src"
  else say "  GAGAL backup: $src"; BK_GAGAL=1; fi
}

# OpenClaw: config utama + credential + identitas (sesi & workspace TIDAK --
# itu urusan --arsip)
simpan "$OC_STATE/openclaw.json"  "openclaw/openclaw.json"
simpan "$OC_STATE/credentials"    "openclaw/credentials"
simpan "$OC_STATE/identity"       "openclaw/identity"
simpan "$OC_STATE/devices"        "openclaw/devices"
if [ -d "$OC_STATE/agents" ]; then
  BK_ADA=1
  if [ "$KERING" = 1 ]; then
    say "  [dry-run] backup: $OC_STATE/agents (tanpa sessions) -> openclaw/agents.tgz"
  else
    mkdir -p "$BK/openclaw" 2>>"$LOG"
    if tar -C "$OC_STATE" --exclude='agents/*/sessions' -czf "$BK/openclaw/agents.tgz" agents 2>>"$LOG"; then
      say "  backup: $OC_STATE/agents (tanpa sessions) -> agents.tgz"
    else
      say "  GAGAL backup agents/"; BK_GAGAL=1
    fi
  fi
fi

# Hermes: file config di akar ~/.hermes + memories (teks kecil)
for f in "$HOME/.hermes"/*.json "$HOME/.hermes"/*.env "$HOME/.hermes/.env" \
         "$HOME/.hermes"/*.yaml "$HOME/.hermes"/*.toml; do
  [ -e "$f" ] || continue
  simpan "$f" "hermes/$(basename "$f")"
done
simpan "$HOME/.hermes/memories"  "hermes/memories"

# Torang: config kecil yang bikin karakter murid tetap sama
simpan "$HOME/.torang/config.env"          "torang/config.env"
simpan "$HOME/.torang-monitor/config.json" "torang/monitor-config.json"
simpan "$HOME/.torang-monitor/client_id"   "torang/client_id"
simpan "$HOME/.torang-events.env"          "torang/torang-events.env"

# snapshot rc & npmrc (referensi, bukan untuk restore mentah)
simpan "$HOME/.npmrc"  "rc/npmrc"
simpan "$HOME/.bashrc" "rc/bashrc"

if [ "$BK_ADA" = 0 ]; then
  say "  (tidak ada config lama yang perlu di-backup -- box ini tampak kosong)"
fi
if [ "$KERING" = 0 ] && [ "$BK_ADA" = 1 ]; then
  if [ "$BK_GAGAL" = 1 ]; then
    say ""
    say "GAGAL: backup tidak lengkap. TIDAK ADA YANG DIHAPUS. Berhenti."
    exit 1
  fi
  {
    echo "openclaw-cleanup reset -- manifest backup"
    echo "tanggal : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "user    : $(id -un)@$(hostname 2>/dev/null || echo '?')"
    echo "openclaw: $(command -v openclaw >/dev/null 2>&1 && timeout 30 openclaw --version 2>/dev/null | head -1 || echo 'tidak terdeteksi')"
    echo ""
    echo "isi:"
    (cd "$BK" && find . -type f | sort)
  } > "$BK/MANIFEST.txt" 2>>"$LOG"
  say "  manifest: $BK/MANIFEST.txt"
fi

# =====================================================================
#  TAHAP 3 -- STOP + BERSIHKAN (mesin oc-uninstall.sh)
# =====================================================================
judul "TAHAP 3/4 -- stop service & bersihkan state lama"
ARGS="-y"
[ "$KERING" = 1 ]        && ARGS="$ARGS --dry-run"
[ "$PAKAI_SUDO" = 1 ]    && ARGS="$ARGS --sudo"
[ "$ARSIP" = 1 ]         && ARGS="$ARGS --arsip"
[ "$DENGAN_TORANG" = 0 ] && ARGS="$ARGS --sisakan-torang"
say "  menjalankan: oc-uninstall.sh $ARGS"
bash "$SCRIPT_DIR/oc-uninstall.sh" $ARGS
RC=$?
if [ "$RC" = 2 ] && [ "$KERING" = 0 ]; then
  say ""
  say "BERHENTI: pembersihan menyisakan jejak (exit 2)."
  say "Memasang di atas sisa lama = sumber gateway error / token mismatch."
  say "Selesaikan baris 'MASIH ADA' (biasanya perlu --sudo), lalu jalankan reset lagi."
  say "Backup aman di: $BK"
  exit 2
elif [ "$RC" != 0 ] && [ "$KERING" = 0 ]; then
  say "BERHENTI: mesin uninstall gagal (exit $RC). Backup aman di: $BK"
  exit 1
fi

# =====================================================================
#  TAHAP 4 -- INSTALL ULANG + SETUP AWAL
# =====================================================================
if [ "$TANPA_INSTALL" = 1 ]; then
  judul "TAHAP 4/4 -- install ulang DILEWATI (--tanpa-install)"
  say "  Sistem kini bersih. Backup: $BK"
  exit 0
fi

judul "TAHAP 4/4 -- install ulang OpenClaw & Hermes terbaru"
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

if [ "$KERING" = 1 ]; then
  say "  [dry-run] curl -fsSL $URL_OC | bash"
  say "  [dry-run] openclaw gateway install --force   (hindari unit/entrypoint basi)"
  say "  [dry-run] curl -fsSL $URL_HM | bash"
  say "  [dry-run] cd ~/.hermes/hermes-agent && uv pip install -e \".[web,pty]\""
  say ""
  say "Mode dry-run selesai. Backup & penghapusan juga hanya rencana."
  exit 0
fi

say "  memasang OpenClaw ..."
if curl -fsSL "$URL_OC" | bash >>"$LOG" 2>&1; then
  say "  installer OpenClaw selesai"
else
  say "  GAGAL: installer OpenClaw error (lihat $LOG). Backup aman di: $BK"
  exit 1
fi
hash -r 2>/dev/null || true
if ada openclaw; then
  say "  openclaw terpasang: $(timeout 60 openclaw --version 2>/dev/null | head -1 || echo 'versi tak terbaca')"
  # --force supaya unit systemd baru menunjuk entrypoint BARU (doctor --fix
  # tidak memperbaiki entrypoint basi -- pelajaran lama).
  say "  openclaw gateway install --force"
  timeout 120 openclaw gateway install --force >>"$LOG" 2>&1 \
    || say "  (gateway install belum jalan -- biasanya baru bisa setelah onboarding)"
else
  say "  PERINGATAN: 'openclaw' belum terlihat di PATH shell ini."
  say "  Buka terminal baru lalu cek 'openclaw --version'."
fi

say "  memasang Hermes ..."
if curl -fsSL "$URL_HM" | bash >>"$LOG" 2>&1; then
  say "  installer Hermes selesai"
else
  say "  GAGAL: installer Hermes error (lihat $LOG). OpenClaw sudah terpasang."
  say "  Backup aman di: $BK"
  exit 1
fi
if [ -d "$HOME/.hermes/hermes-agent" ]; then
  UV="$(command -v uv 2>/dev/null || echo "$HOME/.local/bin/uv")"
  if [ -x "$UV" ]; then
    say "  uv pip install -e \".[web,pty]\" (di ~/.hermes/hermes-agent)"
    (cd "$HOME/.hermes/hermes-agent" && timeout 600 "$UV" pip install -e ".[web,pty]") >>"$LOG" 2>&1 \
      && say "  dependensi web/pty Hermes terpasang" \
      || say "  PERINGATAN: uv pip install gagal -- jalankan manual nanti."
  else
    say "  PERINGATAN: 'uv' tidak ditemukan -- jalankan manual:"
    say "    cd ~/.hermes/hermes-agent && uv pip install -e \".[web,pty]\""
  fi
fi

say ""
say "======================================================"
say "  RESET SELESAI -- kondisi seperti instalasi baru."
say "  BACKUP LAMA : $BK"
say "  (openclaw.json lama berisi token gateway LAMA -- jangan"
say "   di-restore mentah-mentah; ambil hanya nilai yang perlu,"
say "   mis. API key / bot token, supaya tidak kena 'gateway"
say "   token mismatch'.)"
say ""
say "  LANGKAH LANJUTAN (interaktif, tak bisa otomatis):"
say "  1. openclaw onboard --auth-choice openai-api-key"
say "     (pilih INSTALL GATEWAY SERVICE NOW -> YES, mode NODE)"
say "  2. Telegram: openclaw config set channels.telegram.enabled true"
say "     + botToken + dmPolicy=pairing, lalu: openclaw gateway restart"
say "  3. Pairing : openclaw pairing approve telegram <kode>"
say "  4. Monitor Torang (kalau perlu): installer torang-murid."
say "======================================================"
say "Log: $LOG"
exit 0
