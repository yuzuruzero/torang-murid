#!/usr/bin/env bash
# =====================================================================
#  TORANG -- PEMASANG OpenClaw + Hermes  (pintu Mac)  v1.0
#
#  Tugas berkas ini HANYA menyiapkan prasyarat khas Mac. Pemasangan yang
#  sebenarnya dikerjakan pasang-inti.sh -- file yang sama persis dengan
#  yang dipakai WSL dan VPS.
#
#  PAKAI (di Terminal):
#     cd <folder installer>
#     bash pasang-mac.sh
#
#  PILIHAN: apa pun yang diberikan di sini diteruskan ke pasang-inti.sh,
#  mis.  bash pasang-mac.sh --kering
#
#  CATATAN: bash bawaan macOS masih versi 3.2. Semua skrip di folder ini
#  ditulis supaya jalan di sana -- jangan menambahkan ${var,,},
#  declare -A, atau `timeout` tanpa pengganti.
# =====================================================================
set -uo pipefail

VERSI="1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR="$PWD"
INTI="$SCRIPT_DIR/pasang-inti.sh"
DISK_MIN_MB=4096

ok()   { printf '  [ OK ] %s\n' "$1"; }
bad()  { printf '  [GAGAL] %s\n' "$1"; }
warn() { printf '  [ ?  ] %s\n' "$1"; }
obat() { printf '         -> %s\n' "$1"; }
judul(){ printf '\n=== %s ===\n' "$1"; }
ada()  { command -v "$1" >/dev/null 2>&1; }

kecilkan() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

tanya() {
  local pertanyaan="$1" JWB=""
  if [ ! -t 0 ]; then printf '  (tidak ada terminal -- dianggap TIDAK)\n'; return 1; fi
  printf '%s (y = ya, lainnya = tidak): ' "$pertanyaan"
  read -r JWB || JWB=""
  JWB="${JWB//$'\r'/}"
  JWB="$(kecilkan "$JWB")"
  case "$JWB" in y|ya|yes) return 0 ;; *) return 1 ;; esac
}

echo ""
echo "======================================================"
echo " TORANG -- PEMASANG OpenClaw + Hermes (Mac)  v$VERSI"
echo " $(sw_vers -productName 2>/dev/null || echo macOS) $(sw_vers -productVersion 2>/dev/null)  ·  $(uname -m)"
echo "======================================================"

if [ "$(uname -s)" != "Darwin" ]; then
  bad "ini bukan Mac."
  obat "Di Windows  : klik kanan PASANG.bat > Run as Administrator"
  obat "Di Linux/VPS: bash pasang-inti.sh"
  exit 1
fi

if [ "$(id -u)" = "0" ]; then
  bad "jangan jalankan dengan sudo."
  obat "OpenClaw dan Hermes memasang diri ke folder rumahmu sendiri."
  obat "Dipasang sebagai root, hasilnya tidak bisa dipakai akunmu."
  exit 1
fi

GAGAL=0

# ---------------------------------------------------------------- 1
judul "[1] Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
  ok "Command Line Tools terpasang ($(xcode-select -p 2>/dev/null))"
else
  bad "Command Line Tools belum terpasang."
  obat "Ini paket dari Apple yang berisi git dan alat kompilasi."
  obat "Installer Hermes membutuhkannya (git wajib)."
  obat ""
  obat "Lakukan: jalankan perintah ini, lalu klik Install di kotak yang muncul:"
  obat "    xcode-select --install"
  obat "Tunggu sampai selesai (bisa belasan menit), lalu jalankan skrip ini lagi."
  if tanya "  Buka kotak pemasangannya sekarang?"; then
    xcode-select --install 2>/dev/null || true
    echo ""
    echo "  Kotak pemasangan sudah dibuka (kalau tidak muncul, berarti sedang"
    echo "  berjalan atau sudah terpasang). Jalankan skrip ini lagi setelah selesai."
  fi
  exit 1
fi

# ---------------------------------------------------------------- 2
judul "[2] Alat dasar"
for alat in curl git; do
  if ada "$alat"; then
    ok "$alat tersedia"
  else
    bad "'$alat' tidak ada."
    obat "Seharusnya ikut Command Line Tools. Coba pasang ulang:"
    obat "    xcode-select --install"
    GAGAL=1
  fi
done

# ---------------------------------------------------------------- 3
judul "[3] Homebrew (opsional)"
if ada brew; then
  ok "Homebrew tersedia ($(brew --version 2>/dev/null | head -1))"
else
  warn "Homebrew belum ada."
  obat "Ini TIDAK wajib: installer resmi OpenClaw memasang Homebrew sendiri"
  obat "kalau memang butuh (untuk Node atau Git)."
  obat "Kami sengaja TIDAK memasangnya diam-diam -- Homebrew mengubah"
  obat "banyak hal di Mac-mu dan itu harus keputusanmu."
  obat "Kalau mau memasang sendiri, perintah resminya ada di https://brew.sh"
fi

# ---------------------------------------------------------------- 4
judul "[4] Jaringan dan ruang disk"
if ada curl; then
  for u in https://openclaw.ai/install.sh https://hermes-agent.nousresearch.com/install.sh; do
    if curl -fsI --max-time 15 "$u" >/dev/null 2>&1; then
      ok "bisa menjangkau $u"
    else
      bad "TIDAK bisa menjangkau $u"
      obat "Kenapa biasanya: internet mati, atau ada proxy/VPN yang memblokir."
      obat "Pemasangan tidak akan dimulai -- belum ada yang berubah."
      GAGAL=1
    fi
  done
fi

RUANG="$(df -Pm "$HOME" 2>/dev/null | awk 'NR==2{print $4}')"
if [ -n "${RUANG:-}" ]; then
  case "$RUANG" in
    *[!0-9]*) warn "ruang disk tidak terbaca -- dilewati" ;;
    *)
      if [ "$RUANG" -lt "$DISK_MIN_MB" ]; then
        bad "ruang kosong ${RUANG} MB, butuh minimal ${DISK_MIN_MB} MB."
        obat "OpenClaw + Hermes + Chromium sekitar 3 GB, sisanya margin."
        GAGAL=1
      else
        ok "ruang disk cukup (${RUANG} MB)"
      fi ;;
  esac
fi

if [ "$GAGAL" != 0 ]; then
  echo ""
  echo "======================================================"
  echo "  BERHENTI -- prasyarat belum terpenuhi."
  echo "  Belum ada apa pun yang dipasang di Mac ini."
  echo "======================================================"
  exit 1
fi

# ---------------------------------------------------------------- 5
judul "[5] Menjalankan pemasang inti"
if [ ! -f "$INTI" ]; then
  bad "pasang-inti.sh tidak ada di $SCRIPT_DIR"
  obat "Kenapa biasanya: file ini disalin sendirian, tanpa file lain."
  obat "Lakukan: salin SATU FOLDER penuh, minimal berisi"
  obat "         pasang-mac.sh  pasang-inti.sh  verifikasi.sh"
  exit 1
fi

echo "  Catatan Mac: layanan latar belakang OpenClaw memakai LaunchAgent"
echo "  (bukan systemd). Itu wajar dan sudah diperhitungkan verifikasi."
echo ""

bash "$INTI" "$@"
exit $?
