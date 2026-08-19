#!/usr/bin/env bash
# =====================================================================
#  TORANG -- PINTU SATU-BARIS  (Mac / VPS Linux / di dalam WSL)  v1.0
#
#  PAKAI:
#    bash <(curl -fsSL https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/openclaw-installer/pasang.sh)
#
#  Ini BUKAN pemasangnya. Ini hanya penunjuk arah: ia mendeteksi sistem
#  operasi, mengunduh berkas yang tepat KE FILE, mencatatnya, lalu
#  menjalankannya.
#
#  Kenapa unduh ke file dulu, bukan `curl | bash` langsung: kalau ada
#  yang gagal, isi skrip + URL + ukuran + sidik jari SHA-256 tersimpan di
#  disk dan tercatat di log, jadi bisa diperiksa tanpa mengulang.
#
#  Berkas diunduh ke:  ~/.torang-installer/
#  Log:                ~/.torang-installer/log-unduh.txt
#
#  PILIHAN: apa pun yang kamu berikan di sini diteruskan apa adanya ke
#  pemasang, misalnya:
#    bash <(curl -fsSL .../pasang.sh) --kering
#
#  Khusus untuk Windows, JANGAN pakai berkas ini. Pakai salah satu:
#    - unduh ZIP repo, lalu klik kanan PASANG.bat > Run as Administrator
#    - atau di PowerShell:
#      irm https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/openclaw-installer/bootstrap.ps1 | iex
# =====================================================================
set -uo pipefail

VERSI="1.0"
BASE_URL="${TORANG_BASE_URL:-https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/openclaw-installer}"
RUMAH="${TORANG_INSTALLER_DIR:-$HOME/.torang-installer}"
LOG="$RUMAH/log-unduh.txt"

ok()   { printf '  [ OK ] %s\n' "$1" | tee -a "$LOG"; }
bad()  { printf '  [GAGAL] %s\n' "$1" | tee -a "$LOG"; }
say()  { printf '%s\n' "$*" | tee -a "$LOG"; }
ada()  { command -v "$1" >/dev/null 2>&1; }

sidik_jari() {
  if   ada sha256sum; then sha256sum "$1" 2>/dev/null | awk '{print $1}'
  elif ada shasum;    then shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  else echo "(tidak ada alat sha256)"; fi
}

echo ""
echo "======================================================"
echo " TORANG -- pengambil pemasang OpenClaw + Hermes  v$VERSI"
echo "======================================================"

# ---------- pengaman dasar ----------
[ -n "${HOME:-}" ] || { echo "GAGAL: \$HOME kosong. Batal demi keamanan."; exit 1; }

if [ "$(id -u)" = "0" ]; then
  echo ""
  echo "GAGAL: jangan jalankan sebagai root/sudo."
  echo "  Kenapa : OpenClaw dan Hermes memasang diri ke HOME milik user."
  echo "  Lakukan: jalankan sebagai user biasa. Di VPS yang hanya punya"
  echo "           root: adduser namamu, lalu su - namamu."
  exit 1
fi

if ! ada curl; then
  echo ""
  echo "GAGAL: 'curl' tidak ada, padahal itu yang dipakai mengunduh."
  echo "  Ubuntu/WSL: sudo apt install -y curl"
  echo "  Mac       : xcode-select --install"
  exit 1
fi

mkdir -p "$RUMAH" 2>/dev/null || { echo "GAGAL: tidak bisa membuat $RUMAH"; exit 1; }
: >> "$LOG" 2>/dev/null || { echo "GAGAL: tidak bisa menulis $LOG"; exit 1; }

say ""
say "--- $(date '+%Y-%m-%d %H:%M:%S') ---"
say "sumber : $BASE_URL"
say "tujuan : $RUMAH"

# ---------- deteksi sistem ----------
SISTEM="$(uname -s 2>/dev/null || echo '?')"
case "$SISTEM" in
  Darwin) PINTU="mac" ;;
  Linux)
    if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
      PINTU="wsl"
    else
      PINTU="linux"
    fi ;;
  MINGW*|MSYS*|CYGWIN*)
    echo ""
    echo "GAGAL: ini terlihat seperti Git Bash di Windows."
    echo "  Pemasang kami memasang OpenClaw + Hermes DI DALAM WSL,"
    echo "  bukan di Windows langsung."
    echo "  Lakukan, di PowerShell:"
    echo "    irm $BASE_URL/bootstrap.ps1 | iex"
    exit 1 ;;
  *)
    echo ""
    echo "GAGAL: sistem '$SISTEM' belum didukung."
    echo "  Yang didukung: macOS, Linux (VPS), dan Ubuntu di dalam WSL."
    exit 1 ;;
esac
say "sistem : $SISTEM -> pintu '$PINTU'"

# ---------- daftar berkas yang perlu diunduh ----------
# verifikasi.sh WAJIB ikut: pasang-inti.sh memanggilnya sebagai tetangga.
BERKAS="pasang-inti.sh verifikasi.sh"
[ "$PINTU" = "mac" ] && BERKAS="$BERKAS pasang-mac.sh"

say ""
GAGAL_UNDUH=0
for b in $BERKAS; do
  url="$BASE_URL/$b"
  tujuan="$RUMAH/$b"
  printf '  mengunduh %s ... ' "$b"
  if curl -fsSL --proto '=https' --tlsv1.2 --max-time 120 "$url" -o "$tujuan.baru"; then
    if [ -s "$tujuan.baru" ]; then
      mv -f "$tujuan.baru" "$tujuan"
      ukuran="$(wc -c < "$tujuan" 2>/dev/null | tr -d ' ')"
      sidik="$(sidik_jari "$tujuan")"
      echo "OK"
      printf '[unduh] %s url=%s size=%s sha256=%s\n' "$b" "$url" "${ukuran:-?}" "$sidik" >> "$LOG"
      say "    $b  ${ukuran:-?} bita  sha256 ${sidik}"
    else
      echo "GAGAL (berkas kosong)"
      rm -f "$tujuan.baru"
      GAGAL_UNDUH=1
    fi
  else
    echo "GAGAL"
    rm -f "$tujuan.baru"
    GAGAL_UNDUH=1
  fi
done

if [ "$GAGAL_UNDUH" = 1 ]; then
  say ""
  bad "sebagian berkas gagal diunduh."
  say "  Kenapa biasanya: internet terputus, atau proxy/firewall sekolah"
  say "                   memblokir raw.githubusercontent.com."
  say "  Belum ada apa pun yang dipasang di komputer ini."
  say ""
  say "  Jalur cadangan: buka https://github.com/yuzuruzero/torang-murid"
  say "  klik Code > Download ZIP, ekstrak, masuk folder openclaw-installer,"
  say "  lalu jalankan langsung: bash pasang-inti.sh"
  exit 1
fi

say ""
ok "semua berkas siap di $RUMAH"

# ---------- jalankan ----------
case "$PINTU" in
  mac)
    say "menjalankan pasang-mac.sh"
    say ""
    bash "$RUMAH/pasang-mac.sh" "$@"
    exit $? ;;
  wsl|linux)
    [ "$PINTU" = "wsl" ] && say "terdeteksi di dalam WSL -- ini tempat yang benar"
    say "menjalankan pasang-inti.sh"
    say ""
    bash "$RUMAH/pasang-inti.sh" "$@"
    exit $? ;;
esac
