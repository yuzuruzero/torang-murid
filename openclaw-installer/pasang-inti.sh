#!/usr/bin/env bash
# =====================================================================
#  TORANG -- INSTALLER-ORKESTRATOR OpenClaw + Hermes  (INTI)  v1.0
#
#  Ini OTAK-nya. Semua logika pemasangan ada di sini, dan file yang SAMA
#  dipakai oleh ketiga pintu:
#     - Windows : dipanggil pasang.ps1 lewat  wsl -d <distro> -- bash ...
#     - Mac     : dipanggil pasang-mac.sh
#     - VPS     : dijalankan langsung
#
#  Kita ORKESTRATOR, bukan installer dari nol: kita cek prasyarat,
#  menjalankan installer RESMI, memverifikasi, dan menawarkan rollback
#  bila gagal. Logika yang sudah dikerjakan installer resmi tidak ditulis
#  ulang di sini.
#
#  URUTAN (jangan diubah -- lihat RANCANGAN.md §5):
#     0 pra-cek  ->  1 potret awal  ->  2 pasang OpenClaw
#     3 VERIFIKASI OpenClaw (wajib lulus)  ->  4 pasang Hermes
#     5 hash -r + VERIFIKASI OpenClaw ULANG (anti-pembajakan npm)
#     6 hermes claw migrate (best-effort)  ->  7 verifikasi akhir
#     8 laporan + LANGKAH BERIKUTNYA
#
#  Kenapa OpenClaw dulu: installer Hermes memasang Node privat di
#  ~/.hermes/node dan menautkan ~/.local/bin/{node,npm,npx} ke sana.
#  Kalau Hermes duluan, npm bisa jadi milik Hermes sebelum OpenClaw
#  sempat dipasang lewat npm.
#
#  PAKAI:
#    bash pasang-inti.sh                # interaktif (konfirmasi y/ya)
#    bash pasang-inti.sh --kering       # rencana saja, tidak memasang
#    bash pasang-inti.sh -y             # tanpa tanya (HANYA setelah
#                                       # pengguna setuju secara sadar)
#
#  PILIHAN:
#    --kering | --dry-run | -n   tampilkan rencana, jangan pasang apa pun
#    -y | --yes                  tanpa prompt
#    --tanpa-hermes              pasang OpenClaw saja
#    --tanpa-openclaw            pasang Hermes saja (jarang; untuk perbaikan)
#    --tanpa-browser             teruskan --skip-browser ke installer Hermes
#                                (hemat ~1 GB Chromium; untuk PC kelas)
#    --versi-openclaw <versi>    pin versi OpenClaw (lihat RANCANGAN.md §8.1)
#    --npm-langsung              pasang OpenClaw lewat npm langsung, bukan
#                                lewat install.sh (jalur alternatif resmi)
#    --bantuan | -h              bantuan
#
#  KELUAR: 0 = selesai | 1 = gagal/batal | 2 = terpasang tapi verifikasi
#          menemukan kekurangan
#
#  Semua yang dijalankan dicatat ke log-pasang.txt di folder skrip ini.
# =====================================================================
set -uo pipefail

VERSI="1.0"

# Nama skrip sendiri -- dipakai supaya kita tidak pernah salah mengenali
# proses/berkas milik sendiri sebagai temuan.
SELF_PAT='pasang-inti|pasang-mac|verifikasi\.sh|openclaw-installer'

URL_OC="https://openclaw.ai/install.sh"
URL_HM="https://hermes-agent.nousresearch.com/install.sh"
URL_UNINSTALL="https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/openclaw-cleanup/scripts/oc-uninstall.sh"

DISK_MIN_MB=4096      # 3 GB terukur di lapangan + 1 GB margin (RANCANGAN §2.2 CEK 4)

# ---------- pilihan ----------
KERING=0; PAKSA=0
TANPA_HERMES=0; TANPA_OPENCLAW=0; TANPA_BROWSER=0
PIN_OC=""; NPM_LANGSUNG=0

usage() { sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --kering|--dry-run|-n)  KERING=1 ;;
    -y|--yes|--paksa)       PAKSA=1 ;;
    --tanpa-hermes)         TANPA_HERMES=1 ;;
    --tanpa-openclaw)       TANPA_OPENCLAW=1 ;;
    --tanpa-browser)        TANPA_BROWSER=1 ;;
    --npm-langsung)         NPM_LANGSUNG=1 ;;
    --versi-openclaw)       shift; PIN_OC="${1:-}"
                            [ -n "$PIN_OC" ] || { echo "GAGAL: --versi-openclaw butuh nilai."; exit 1; } ;;
    --bantuan|-h|--help)    usage; exit 0 ;;
    *) echo "Pilihan tak dikenal: $1  (pakai --bantuan)"; exit 1 ;;
  esac
  shift
done

# =====================================================================
#  PENGAMAN DASAR -- sebelum apa pun disentuh
# =====================================================================
[ -n "${HOME:-}" ] || { echo "GAGAL: \$HOME kosong. Batal demi keamanan."; exit 1; }
[ -d "$HOME" ]     || { echo "GAGAL: \$HOME ($HOME) bukan folder. Batal."; exit 1; }

if [ "$(id -u)" = "0" ]; then
  echo ""
  echo "GAGAL: jangan jalankan sebagai root/sudo."
  echo "  Kenapa : OpenClaw dan Hermes memasang diri ke HOME milik user."
  echo "           Dipasang sebagai root, hasilnya tidak bisa dipakai user"
  echo "           biasa dan perkakas pembersih kami menolak menyentuhnya."
  echo "  Lakukan: keluar dari root, jalankan lagi sebagai user biasa."
  echo "           Di VPS yang hanya punya root: buat user dulu"
  echo "           (adduser namamu), lalu masuk sebagai user itu."
  exit 1
fi

if [ "$KERING" = 0 ] && [ "$PAKSA" = 0 ] && [ ! -t 0 ]; then
  echo ""
  echo "GAGAL: skrip ini butuh terminal untuk bertanya, tapi tidak menemukannya."
  echo "  Lakukan: jalankan --kering dulu untuk melihat rencananya, lalu"
  echo "           ulangi dengan -y kalau memang sudah setuju."
  exit 1
fi

# ---------- lokasi & log ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR="$PWD"
LOG="$SCRIPT_DIR/log-pasang.txt"
if ! : >> "$LOG" 2>/dev/null; then
  LOG="$HOME/log-pasang-torang.txt"
  : >> "$LOG" 2>/dev/null || { echo "GAGAL: tidak bisa menulis log di mana pun."; exit 1; }
fi

CAP="$(date +%Y%m%d-%H%M%S)"
TMPDIR_KITA="$(mktemp -d "${TMPDIR:-/tmp}/torang-pasang-XXXXXX")" || {
  echo "GAGAL: tidak bisa membuat folder sementara."; exit 1; }

bersih_bersih() { [ -n "${TMPDIR_KITA:-}" ] && [ -d "$TMPDIR_KITA" ] && rm -rf "$TMPDIR_KITA"; }
trap bersih_bersih EXIT

# =====================================================================
#  ALAT BANTU
# =====================================================================
# Keluaran SELALU ke layar DAN log. Jangan pernah `| tee -a "$LOG" >/dev/null`
# -- itu bikin layar kosong padahal user butuh melihat daftarnya.
say()   { printf '%s\n' "$*" | tee -a "$LOG"; }
judul() { say ""; say "=== $* ==="; }
ok()    { say "  [ OK ] $*"; }
warn()  { say "  [ ?  ] $*"; }
bad()   { say "  [GAGAL] $*"; }
obat()  { say "         -> $*"; }
catat() { printf '%s\n' "$*" >> "$LOG"; }   # hanya ke log (detail teknis)

ada() { command -v "$1" >/dev/null 2>&1; }

# huruf kecil semua -- pakai tr, BUKAN ${v,,}: bash 3.2 bawaan macOS
# tidak mengenal ${v,,} dan skripnya akan mati di baris itu.
kecilkan() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Konfirmasi: y/ya, besar-kecil bebas, CR dibuang.
# CR wajib dibuang -- tty aneh dan paste dari Windows mengirim jawaban+CR,
# sehingga "y" terbaca sebagai "y\r" dan tidak pernah cocok.
tanya() {
  local pertanyaan="$1" JWB=""
  if [ "$PAKSA" = 1 ]; then say "  [-y] $pertanyaan -> ya"; return 0; fi
  if [ ! -t 0 ]; then say "  (tidak ada terminal -- dianggap TIDAK)"; return 1; fi
  printf '%s (y = ya, lainnya = tidak): ' "$pertanyaan"
  read -r JWB || JWB=""
  JWB="${JWB//$'\r'/}"
  JWB="$(kecilkan "$JWB")"
  catat "[tanya] $pertanyaan -> '$JWB'"
  case "$JWB" in y|ya|yes) return 0 ;; *) return 1 ;; esac
}

# `timeout` tidak ada di macOS bawaan -- jangan diandalkan buta.
batas_waktu() {
  local detik="$1"; shift
  if ada timeout; then timeout "$detik" "$@"; else "$@"; fi
}

# sha256sum (Linux) vs shasum -a 256 (macOS)
sidik_jari() {
  local f="$1"
  if   ada sha256sum; then sha256sum "$f" 2>/dev/null | awk '{print $1}'
  elif ada shasum;    then shasum -a 256 "$f" 2>/dev/null | awk '{print $1}'
  else echo "(tidak ada alat sha256 di mesin ini)"; fi
}

# Jalankan perintah, salin keluarannya ke log, kembalikan kode keluarnya.
jalankan() {
  catat "----- \$ $* -----"
  if [ "$KERING" = 1 ]; then say "  [kering] $*"; return 0; fi
  "$@" >> "$LOG" 2>&1
  local rc=$?
  catat "----- selesai (kode $rc) -----"
  return $rc
}

ekor_log() {
  local n="${1:-30}"
  say ""
  say "  --- $n baris terakhir log ---"
  tail -n "$n" "$LOG" 2>/dev/null | sed 's/^/  | /'
  say "  --- selengkapnya di: $LOG ---"
}

# =====================================================================
#  DETEKSI LINGKUNGAN
# =====================================================================
LINGKUNGAN="linux"      # linux | wsl | mac
deteksi_lingkungan() {
  case "$(uname -s 2>/dev/null || echo '?')" in
    Darwin) LINGKUNGAN="mac" ;;
    Linux)
      if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
        LINGKUNGAN="wsl"
      else
        LINGKUNGAN="linux"
      fi ;;
    *) LINGKUNGAN="linux" ;;
  esac
}

# Versi npm menentukan bentuk perintah pemasangan global.
# Sejak npm 11.16 lifecycle script diblokir kecuali diizinkan eksplisit.
# Kembali: 0 = butuh --allow-scripts, 1 = tidak butuh, 2 = tidak terbaca.
npm_butuh_allow_scripts() {
  local v may min
  ada npm || return 2
  v="$(npm --version 2>/dev/null | tr -d '\r')"
  case "$v" in
    ''|*[!0-9.]*) return 2 ;;
  esac
  may="${v%%.*}"
  min="${v#*.}"; min="${min%%.*}"
  case "$may$min" in *[!0-9]*) return 2 ;; esac
  [ "$may" -gt 11 ] && return 0
  [ "$may" -eq 11 ] && [ "$min" -ge 16 ] && return 0
  return 1
}

# =====================================================================
#  TAHAP 0 -- PRA-CEK  (belum ada apa pun yang diubah)
# =====================================================================
pra_cek() {
  judul "TAHAP 0/8 -- pra-cek"
  local gagal=0

  say "  lingkungan : $LINGKUNGAN   user: $(id -un)   HOME: $HOME"
  say "  log        : $LOG"
  [ "$KERING" = 1 ] && say "  >>> MODE KERING -- tidak ada yang dipasang <<<"

  if ! ada curl; then
    bad "'curl' tidak ada. Installer resmi kedua produk butuh curl."
    obat "Ubuntu/WSL: sudo apt install -y curl xz-utils"
    obat "Mac       : ikut Command Line Tools (xcode-select --install)"
    gagal=1
  else
    ok "curl tersedia"
  fi

  # Prasyarat khusus installer Hermes (dari dokumentasi resmi):
  # git wajib; di Linux juga curl + xz-utils (Node diunduh sebagai .tar.xz).
  if ! ada git; then
    warn "'git' belum ada -- installer Hermes membutuhkannya."
    obat "Ubuntu/WSL: sudo apt install -y git"
    obat "Instalasi tetap bisa dicoba: installer OpenClaw memasang git bila perlu."
  else
    ok "git tersedia"
  fi
  if [ "$LINGKUNGAN" != "mac" ] && ! ada xz && ! ada unxz; then
    warn "'xz' belum ada -- installer Hermes mengunduh Node sebagai .tar.xz."
    obat "Ubuntu/WSL: sudo apt install -y xz-utils"
  fi

  # --- disk ---
  local ruang
  ruang="$(df -Pm "$HOME" 2>/dev/null | awk 'NR==2{print $4}')"
  if [ -n "${ruang:-}" ]; then
    case "$ruang" in
      *[!0-9]*) warn "ruang disk tidak terbaca -- lewati cek ini" ;;
      *)
        if [ "$ruang" -lt "$DISK_MIN_MB" ]; then
          bad "ruang disk tersisa ${ruang} MB, butuh minimal ${DISK_MIN_MB} MB."
          obat "OpenClaw + Hermes + Chromium sekitar 3 GB, sisanya margin."
          obat "Kosongkan dulu. Lebih baik berhenti sekarang daripada gagal"
          obat "di tengah pemasangan dan meninggalkan sistem setengah jadi."
          gagal=1
        else
          ok "ruang disk cukup (${ruang} MB)"
        fi ;;
    esac
  else
    warn "ruang disk tidak bisa dibaca -- lanjut, tapi awasi sendiri"
  fi

  # --- jaringan ---
  if ada curl; then
    local u
    for u in "$URL_OC" "$URL_HM"; do
      if curl -fsI --max-time 15 "$u" >/dev/null 2>&1; then
        ok "bisa menjangkau $u"
      else
        bad "TIDAK bisa menjangkau $u"
        obat "Kemungkinan besar: internet mati, atau proxy/firewall sekolah"
        obat "memblokir alamat ini."
        obat "Instalasi TIDAK dimulai -- belum ada satu pun yang diunduh."
        gagal=1
      fi
    done
  fi

  if [ "$gagal" = 1 ]; then
    say ""
    bad "PRA-CEK GAGAL. Tidak ada yang diubah di komputer ini."
    return 1
  fi
  ok "pra-cek lulus"
  return 0
}

# =====================================================================
#  TAHAP 1 -- POTRET AWAL
# =====================================================================
VERIFIKATOR="$SCRIPT_DIR/verifikasi.sh"

potret_awal() {
  judul "TAHAP 1/8 -- potret keadaan sekarang"
  if [ -f "$VERIFIKATOR" ]; then
    bash "$VERIFIKATOR" --potret 2>&1 | tee -a "$LOG"
    local rc=${PIPESTATUS[0]}
    if [ "$rc" = 0 ]; then
      say ""
      warn "OpenClaw dan Hermes sudah terpasang dan lolos pemeriksaan."
      obat "Menjalankan ulang installer aman (tidak menggandakan apa pun),"
      obat "tapi biasanya tidak perlu."
      if ! tanya "  Tetap lanjutkan pemasangan?"; then
        say "  Dihentikan atas permintaan. Tidak ada yang diubah."
        return 1
      fi
    fi
  else
    warn "verifikasi.sh tidak ada di $SCRIPT_DIR -- potret awal dilewati."
    obat "Pemasangan tetap jalan, tapi verifikasinya jadi seadanya."
  fi
  return 0
}

# =====================================================================
#  UNDUH INSTALLER RESMI KE FILE  (BUKAN curl | bash)
# =====================================================================
# Kenapa tidak `curl | bash`: kalau installer resmi gagal di tengah, dengan
# pipe kita tidak punya apa pun untuk diperiksa. Dengan file, isi skrip +
# URL + ukuran + sidik jari SHA-256 ada di disk dan tercatat di log, jadi
# laporan masalah dari lapangan bisa didiagnosis tanpa mengulang instalasi.
unduh_installer() {
  local url="$1" tujuan="$2" nama="$3"
  say "  mengunduh installer resmi $nama ..."
  say "    dari : $url"
  if [ "$KERING" = 1 ]; then
    say "    [kering] tidak diunduh"
    return 0
  fi
  if ! curl -fsSL --proto '=https' --tlsv1.2 --max-time 120 "$url" -o "$tujuan"; then
    bad "gagal mengunduh installer $nama."
    obat "Kemungkinan besar: koneksi putus di tengah, atau proxy sekolah."
    obat "Belum ada yang dipasang. Coba lagi setelah jaringan stabil."
    return 1
  fi
  local ukuran sidik
  ukuran="$(wc -c < "$tujuan" 2>/dev/null | tr -d ' ')"
  sidik="$(sidik_jari "$tujuan")"
  say "    ke   : $tujuan"
  say "    besar: ${ukuran:-?} bita"
  say "    sha256: $sidik"
  catat "[unduh] $nama url=$url size=${ukuran:-?} sha256=$sidik"
  if [ ! -s "$tujuan" ]; then
    bad "berkas installer $nama kosong -- unduhan tidak utuh."
    return 1
  fi
  return 0
}

# =====================================================================
#  TAHAP 2 -- PASANG OPENCLAW
# =====================================================================
pasang_openclaw() {
  judul "TAHAP 2/8 -- pasang OpenClaw"

  # Catat situasi npm apa pun jalurnya -- ini yang paling sering jadi
  # biang kegagalan diam-diam.
  local npm_v="(tidak ada)"
  ada npm && npm_v="$(npm --version 2>/dev/null | tr -d '\r')"
  say "  npm di mesin ini: $npm_v"
  npm_butuh_allow_scripts
  case $? in
    0) say "  npm >= 11.16 -> pemasangan global butuh --allow-scripts=openclaw" ;;
    1) say "  npm <= 11.15 -> pemasangan global TANPA flag tambahan" ;;
    2) say "  versi npm tidak terbaca -- installer resmi akan menanganinya sendiri" ;;
  esac

  if [ "$NPM_LANGSUNG" = 1 ]; then
    pasang_openclaw_npm; return $?
  fi

  local f="$TMPDIR_KITA/openclaw-install.sh"
  unduh_installer "$URL_OC" "$f" "OpenClaw" || return 1

  # --no-onboard : onboarding TIDAK dijalankan di dalam skrip (keputusan
  #                d.4) -- itu interaktif dan minta kunci API.
  # --no-prompt  : jangan bertanya di tengah; kita yang mengurus dialog.
  # --verify     : installer resmi memeriksa hasilnya sendiri.
  local args="--no-onboard --no-prompt --verify"
  [ -n "$PIN_OC" ] && args="$args --version $PIN_OC"
  say "  menjalankan: bash <installer-openclaw> $args"

  if [ "$KERING" = 1 ]; then
    say "  [kering] installer OpenClaw tidak dijalankan"
    return 0
  fi

  # shellcheck disable=SC2086
  if jalankan bash "$f" $args; then
    ok "installer OpenClaw selesai"
    return 0
  fi
  bad "installer OpenClaw berhenti dengan error."
  obat "Apa yang gagal: skrip resmi OpenClaw tidak selesai."
  obat "Kenapa biasanya: Node gagal dipasang, npm memblokir script paket,"
  obat "                 atau unduhan paket terputus."
  ekor_log 30
  return 1
}

# Jalur alternatif RESMI (docs.openclaw.ai/install): npm global langsung.
# Dipakai kalau install.sh bermasalah, atau saat ingin pin versi tanpa
# bergantung pada installer.
pasang_openclaw_npm() {
  say "  jalur npm langsung dipilih (--npm-langsung)"
  if ! ada npm; then
    bad "npm tidak ada -- jalur ini tidak bisa dipakai."
    obat "Pakai jalur biasa (tanpa --npm-langsung): installer resmi"
    obat "memasang Node + npm sendiri bila belum ada."
    return 1
  fi
  local paket="openclaw@${PIN_OC:-latest}"
  npm_butuh_allow_scripts
  local butuh=$?
  if [ "$butuh" = 2 ]; then
    bad "versi npm tidak terbaca."
    obat "Kenapa penting: bentuk perintahnya berbeda untuk npm >= 11.16."
    obat "Menebak di sini bisa membuat OpenClaw 'terpasang' tapi tidak jalan."
    obat "Perbaiki npm dulu (npm --version harus keluar angka), lalu ulangi."
    return 1
  fi
  if [ "$butuh" = 0 ]; then
    say "  menjalankan: npm install -g $paket --allow-scripts=openclaw"
    jalankan npm install -g "$paket" --allow-scripts=openclaw || {
      bad "npm gagal memasang $paket"; ekor_log 30; return 1; }
  else
    say "  menjalankan: npm install -g $paket"
    jalankan npm install -g "$paket" || {
      bad "npm gagal memasang $paket"; ekor_log 30; return 1; }
  fi
  ok "OpenClaw terpasang lewat npm"
  return 0
}

# =====================================================================
#  VERIFIKASI OPENCLAW  (dipakai DUA KALI: tahap 3 dan tahap 5)
# =====================================================================
verifikasi_openclaw() {
  local babak="$1"   # "pertama" | "ulang"
  local gagal=0

  [ "$KERING" = 1 ] && { say "  [kering] verifikasi dilewati"; return 0; }

  # `command -v -a` BUKAN opsi yang sah -- `type -aP` yang mendaftar
  # SEMUA biner senama di PATH.
  local biner
  biner="$(type -aP openclaw 2>/dev/null | tr '\n' ' ')"
  if [ -z "$biner" ]; then
    bad "biner 'openclaw' tidak ditemukan di PATH."
    obat "Kalau installer bilang sukses, ini hampir selalu soal PATH."
    obat "Coba: buka terminal baru, lalu jalankan 'openclaw --version'."
    gagal=1
  else
    ok "openclaw ada di: $biner"
    # Instalasi sisi WINDOWS terlihat dari WSL karena PATH diwariskan.
    # Itu bukan instalasi kita dan tidak bisa diurus dari WSL.
    if printf '%s' "$biner" | grep -q '/mnt/'; then
      bad "ada 'openclaw' yang berasal dari sisi WINDOWS (path /mnt/...)."
      obat "Kenapa masalah: PATH WSL mewarisi PATH Windows, jadi yang"
      obat "menang bisa saja instalasi Windows, bukan yang baru kita pasang."
      obat "Lakukan dari WSL: cmd.exe /c \"npm rm -g openclaw\""
      obat "sudo TIDAK membantu untuk kasus ini."
      gagal=1
    fi
  fi

  if [ "$gagal" = 0 ]; then
    local v
    # CLI OpenClaw bisa 13-91 detik di PC kelas -- beri waktu longgar.
    v="$(batas_waktu 120 openclaw --version 2>/dev/null | head -1 | tr -d '\r')"
    if [ -n "$v" ]; then
      ok "openclaw --version: $v"
      catat "[versi] openclaw=$v"
    else
      bad "'openclaw --version' tidak mengeluarkan apa pun."
      obat "Biner ada tapi tidak bisa dijalankan -- biasanya Node-nya"
      obat "tidak cocok atau pemasangan paket tidak tuntas."
      gagal=1
    fi
  fi

  # doctor: informatif, TIDAK dijadikan penentu. Pada instalasi yang belum
  # di-onboard, doctor memang melapor "belum dikonfigurasi" -- itu wajar.
  if [ "$gagal" = 0 ] && ada openclaw; then
    if batas_waktu 180 openclaw doctor >>"$LOG" 2>&1; then
      ok "openclaw doctor: tidak ada keluhan"
    else
      warn "openclaw doctor melaporkan sesuatu (wajar bila belum onboarding)"
      obat "Isinya tercatat di $LOG"
    fi
  fi

  if [ "$gagal" = 1 ]; then
    if [ "$babak" = "ulang" ]; then
      say ""
      bad "OpenClaw tadinya sehat, sekarang bermasalah SETELAH Hermes dipasang."
      obat "Ini pola yang sudah kami kenal: installer Hermes memasang Node"
      obat "sendiri di ~/.hermes/node dan menautkan ~/.local/bin/node, npm,"
      obat "npx ke sana, kadang juga menulis prefix npm ke ~/.npmrc."
      obat "Periksa dua hal itu dulu sebelum memasang ulang apa pun:"
      obat "  ls -l ~/.local/bin/node ~/.local/bin/npm ~/.local/bin/npx"
      obat "  cat ~/.npmrc"
    fi
    return 1
  fi
  return 0
}

# =====================================================================
#  TAHAP 4 -- PASANG HERMES
# =====================================================================
pasang_hermes() {
  judul "TAHAP 4/8 -- pasang Hermes"

  local f="$TMPDIR_KITA/hermes-install.sh"
  unduh_installer "$URL_HM" "$f" "Hermes" || return 1

  local args=""
  if [ "$TANPA_BROWSER" = 1 ]; then
    args="--skip-browser"
    say "  --tanpa-browser: Chromium/Playwright TIDAK dipasang (hemat ~1 GB)"
    say "  Catatan: fitur browser Hermes tidak akan bisa dipakai."
  fi
  say "  menjalankan: bash <installer-hermes> $args"

  if [ "$KERING" = 1 ]; then
    say "  [kering] installer Hermes tidak dijalankan"
    return 0
  fi

  # shellcheck disable=SC2086
  if jalankan bash "$f" $args; then
    ok "installer Hermes selesai"
  else
    bad "installer Hermes berhenti dengan error."
    obat "Apa yang gagal: skrip resmi Hermes tidak selesai."
    obat "Kenapa biasanya: git/xz belum ada, unduhan Node atau Chromium"
    obat "                 terputus, atau ruang disk habis di tengah jalan."
    ekor_log 30
    return 1
  fi

  # Installer Hermes menulis PATH ke file rc; shell yang sedang jalan
  # belum tentu ikut. Bantu diri sendiri untuk langkah verifikasi.
  export PATH="$HOME/.local/bin:$PATH"
  hash -r 2>/dev/null || true
  return 0
}

verifikasi_hermes() {
  [ "$KERING" = 1 ] && { say "  [kering] verifikasi dilewati"; return 0; }
  local gagal=0 biner v

  biner="$(type -aP hermes 2>/dev/null | tr '\n' ' ')"
  if [ -z "$biner" ]; then
    bad "biner 'hermes' tidak ditemukan di PATH."
    obat "Installer menaruhnya di ~/.local/bin/hermes dan menulis PATH ke"
    obat "file rc. Coba: source ~/.bashrc  (atau buka terminal baru)."
    gagal=1
  else
    ok "hermes ada di: $biner"
    if printf '%s' "$biner" | grep -q '/mnt/'; then
      bad "ada 'hermes' dari sisi WINDOWS (path /mnt/...)."
      obat "Dari WSL: cmd.exe /c \"npm rm -g hermes\" atau cabut lewat"
      obat "installer Windows-nya di sisi Windows."
      gagal=1
    fi
  fi

  if [ "$gagal" = 0 ]; then
    v="$(batas_waktu 120 hermes version 2>/dev/null | head -3 | tr -d '\r' | tr '\n' ' ')"
    if [ -n "$v" ]; then
      ok "hermes version: $v"
      catat "[versi] hermes=$v"
    else
      warn "'hermes version' tidak mengeluarkan apa pun -- coba terminal baru."
    fi
    if batas_waktu 240 hermes doctor >>"$LOG" 2>&1; then
      ok "hermes doctor: tidak ada keluhan"
    else
      warn "hermes doctor melaporkan sesuatu (wajar bila belum 'hermes setup')"
      obat "Isinya tercatat di $LOG"
    fi
  fi

  [ "$gagal" = 1 ] && return 1
  return 0
}

# =====================================================================
#  TAHAP 6 -- MIGRASI DATA LAMA OPENCLAW -> HERMES  (BEST-EFFORT)
# =====================================================================
# Dijalankan HANYA bila ~/.openclaw memang berisi data lama. Kalau
# perintahnya gagal atau tidak dikenal, itu PERINGATAN saja -- instalasi
# tetap dianggap sukses.
#
# JUJUR: perilaku `hermes claw migrate` belum pernah kami uji di mesin
# nyata. Referensi CLI Hermes hanya menyebut `hermes claw` = "OpenClaw
# migration helpers", tanpa halaman rinci. Karena itu kita tidak
# mengandalkan --dry-run dan tidak menggantungkan apa pun padanya.
ada_data_openclaw_lama() {
  local st="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
  [ -d "$st" ] || return 1
  [ -s "$st/openclaw.json" ] && return 0
  [ -d "$st/credentials" ]   && return 0
  [ -d "$st/agents" ]        && return 0
  return 1
}

migrasi_claw() {
  judul "TAHAP 6/8 -- migrasi data OpenClaw lama ke Hermes (bila ada)"

  if ! ada_data_openclaw_lama; then
    ok "tidak ada data OpenClaw lama yang perlu dipindahkan -- dilewati"
    return 0
  fi
  if ! ada hermes; then
    warn "hermes tidak ada di PATH -- migrasi dilewati"
    return 0
  fi

  say "  ditemukan data OpenClaw di ${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
  say "  mencoba: hermes claw migrate"
  if [ "$KERING" = 1 ]; then
    say "  [kering] tidak dijalankan"
    return 0
  fi

  if batas_waktu 300 hermes claw migrate >>"$LOG" 2>&1; then
    ok "migrasi selesai"
  else
    warn "'hermes claw migrate' tidak berhasil (kode keluar bukan 0)."
    obat "Ini TIDAK menggagalkan pemasangan -- OpenClaw dan Hermes tetap"
    obat "terpasang dan bisa dipakai."
    obat "Kemungkinan: perintahnya berbeda di versi Hermes ini, atau tidak"
    obat "ada yang perlu dipindahkan."
    obat "Cek sendiri kalau perlu: hermes claw --help"
    obat "Keluarannya tercatat di $LOG"
  fi
  return 0
}

# =====================================================================
#  ROLLBACK -- memakai oc-uninstall.sh yang SUDAH ADA
# =====================================================================
# Tidak menulis ulang logika cabut. Cari salinan lokal dulu, baru unduh.
cari_uninstaller() {
  local kandidat
  for kandidat in \
      "${OC_UNINSTALL:-}" \
      "$SCRIPT_DIR/oc-uninstall.sh" \
      "$SCRIPT_DIR/../openclaw-cleanup/scripts/oc-uninstall.sh" \
      "$HOME/torang-murid/openclaw-cleanup/scripts/oc-uninstall.sh" ; do
    [ -n "$kandidat" ] && [ -f "$kandidat" ] && { printf '%s' "$kandidat"; return 0; }
  done
  return 1
}

rollback() {
  judul "ROLLBACK -- mencabut yang baru saja dipasang"

  local unin
  if ! unin="$(cari_uninstaller)"; then
    say "  tidak ada salinan lokal oc-uninstall.sh -- mengunduh dari GitHub"
    unin="$TMPDIR_KITA/oc-uninstall.sh"
    if ! curl -fsSL --proto '=https' --tlsv1.2 --max-time 60 "$URL_UNINSTALL" -o "$unin"; then
      bad "gagal mengunduh alat pencabut."
      obat "Rollback otomatis tidak bisa dijalankan sekarang."
      obat "Jalankan sendiri nanti, satu baris:"
      obat "  bash <(curl -fsSL $URL_UNINSTALL) --sisakan-torang"
      return 1
    fi
  fi
  say "  memakai pencabut: $unin"

  # Versi lama (v1.1) belum punya --sisakan-agenlain karena tahap "agen
  # lain" memang belum ada di sana. Deteksi dulu; memberi flag yang tidak
  # dikenal membuat skripnya langsung berhenti.
  local args="-y --sisakan-torang"
  if ! grep -q -- '--sisakan-torang' "$unin" 2>/dev/null; then
    bad "pencabut ini tidak mengenal --sisakan-torang."
    obat "Menjalankannya tanpa flag itu bisa ikut mencabut monitor Torang"
    obat "yang BUKAN kita pasang. Rollback dibatalkan demi keamanan."
    obat "Cabut manual dengan versi terbaru dari repo torang-murid."
    return 1
  fi
  if grep -q -- '--sisakan-agenlain' "$unin" 2>/dev/null; then
    args="$args --sisakan-agenlain"
  else
    say "  (pencabut versi lama: tidak punya tahap 'agen lain' -- aman tanpa flag)"
  fi

  say ""
  say "  Yang akan dicabut : OpenClaw dan Hermes."
  say "  Yang TIDAK dicabut: monitor Torang, Codex, cua-driver, agent-browser."
  say ""
  if ! tanya "  Jalankan rollback sekarang?"; then
    say "  Rollback dilewati."
    say "  PENTING: komputer ini sekarang dalam keadaan SETENGAH JADI."
    say "  Artinya: sebagian berkas sudah terpasang, tapi belum tentu bisa"
    say "  dipakai. Jangan memasang ulang di atasnya -- itu justru sumber"
    say "  'gateway error / token tidak ke-generate / dashboard tak terbuka'."
    say "  Bersihkan dulu, baru pasang lagi dari awal."
    return 1
  fi

  # shellcheck disable=SC2086
  bash "$unin" $args 2>&1 | tee -a "$LOG"
  local rc=${PIPESTATUS[0]}
  say ""
  if [ "$rc" = 0 ]; then
    ok "rollback selesai -- sistem kembali bersih"
  else
    warn "pencabut selesai dengan kode $rc (2 = masih ada sisa)"
    obat "Baca baris bertanda KOTOR di atas untuk tahu apa yang tersisa."
  fi
  return 0
}

tawarkan_rollback() {
  say ""
  if tanya "  Mau kembalikan komputer ke keadaan semula (rollback)?"; then
    rollback
  else
    say ""
    say "  Baik, tidak ada yang dicabut."
    say "  Keadaan sekarang: pemasangan berhenti di tengah."
    say "  Log lengkap: $LOG"
  fi
}

# =====================================================================
#  LAPORAN
# =====================================================================
laporan_sukses() {
  local rc_verif="$1"
  say ""
  say "======================================================"
  if [ "$rc_verif" = 0 ]; then
    say "  SELESAI. OpenClaw dan Hermes terpasang."
  else
    say "  TERPASANG, TAPI VERIFIKASI MENEMUKAN CATATAN."
    say "  Baca baris bertanda GAGAL di atas. Sebagian catatan wajar"
    say "  sebelum onboarding dijalankan (mis. gateway belum hidup)."
  fi
  say "======================================================"
  say ""
  say "  LANGKAH BERIKUTNYA (dikerjakan sendiri, tidak bisa otomatis)"
  say ""
  say "  1. openclaw onboard"
  say "     Akan menanyakan: cara login (kunci API OpenAI atau langganan),"
  say "     lalu apakah gateway dipasang sebagai layanan -- jawab YA."
  say ""
  say "  2. hermes setup"
  say "     Akan menanyakan: penyedia model dan kunci/akunnya. Kalau bingung,"
  say "     pilih Quick Setup (Nous Portal)."
  say ""
  say "  Setelah keduanya selesai, jalankan lagi:"
  say "     bash verifikasi.sh"
  say ""
  say "  Log lengkap pemasangan: $LOG"
  say "======================================================"
}

# =====================================================================
#  ALUR UTAMA
# =====================================================================
deteksi_lingkungan

say ""
say "======================================================"
say " TORANG -- PEMASANG OpenClaw + Hermes  v$VERSI"
say " waktu: $(date '+%Y-%m-%d %H:%M:%S')"
say "======================================================"

pra_cek || exit 1

if [ "$KERING" = 0 ]; then
  say ""
  say "  Yang akan dilakukan:"
  [ "$TANPA_OPENCLAW" = 0 ] && say "   - memasang OpenClaw (installer resmi openclaw.ai)"
  [ "$TANPA_HERMES" = 0 ]   && say "   - memasang Hermes (installer resmi nousresearch.com)"
  say "   - memverifikasi hasilnya"
  say "   - TIDAK menjalankan onboarding (itu langkahmu sendiri nanti)"
  say ""
  if ! tanya "  Lanjut memasang?"; then
    say "  Dibatalkan. Tidak ada yang diubah."
    exit 1
  fi
fi

potret_awal || exit 1

# --- OpenClaw ---
if [ "$TANPA_OPENCLAW" = 1 ]; then
  judul "TAHAP 2/8 -- OpenClaw dilewati (--tanpa-openclaw)"
else
  if ! pasang_openclaw; then
    tawarkan_rollback
    exit 1
  fi
  judul "TAHAP 3/8 -- verifikasi OpenClaw (wajib lulus sebelum Hermes)"
  if ! verifikasi_openclaw "pertama"; then
    say ""
    bad "OpenClaw belum terbukti sehat. Hermes TIDAK akan dipasang di atasnya."
    obat "Kenapa: memasang Hermes di atas OpenClaw yang bermasalah membuat"
    obat "kedua-duanya sulit didiagnosis, dan Hermes ikut memindahkan npm."
    tawarkan_rollback
    exit 1
  fi
  ok "OpenClaw sehat"
fi

# --- Hermes ---
if [ "$TANPA_HERMES" = 1 ]; then
  judul "TAHAP 4/8 -- Hermes dilewati (--tanpa-hermes)"
else
  if ! pasang_hermes; then
    say ""
    say "  Pilihanmu sekarang:"
    say "   - rollback keduanya (OpenClaw ikut dicabut), atau"
    say "   - berhenti di sini dengan OpenClaw saja yang terpasang."
    say "  Berhenti dengan OpenClaw saja itu keadaan yang SAH -- Hermes bisa"
    say "  dipasang lagi kapan pun dengan menjalankan skrip ini lagi."
    tawarkan_rollback
    exit 1
  fi
  judul "TAHAP 5/8 -- verifikasi ulang OpenClaw setelah Hermes"
  say "  (installer Hermes memasang Node sendiri dan menautkan npm --"
  say "   kita pastikan OpenClaw tidak ikut terbawa)"
  hash -r 2>/dev/null || true
  if [ "$TANPA_OPENCLAW" = 0 ]; then
    if ! verifikasi_openclaw "ulang"; then
      tawarkan_rollback
      exit 1
    fi
    ok "OpenClaw masih sehat setelah Hermes dipasang"
  fi
  verifikasi_hermes || warn "Hermes belum terbukti sehat -- baca catatan di atas"
fi

# --- migrasi (best-effort) ---
if [ "$TANPA_HERMES" = 0 ] && [ "$TANPA_OPENCLAW" = 0 ]; then
  migrasi_claw
fi

# --- verifikasi akhir ---
judul "TAHAP 7/8 -- verifikasi akhir"
RC_VERIF=0
if [ "$KERING" = 1 ]; then
  say "  [kering] dilewati"
elif [ -f "$VERIFIKATOR" ]; then
  bash "$VERIFIKATOR" 2>&1 | tee -a "$LOG"
  RC_VERIF=${PIPESTATUS[0]}
else
  warn "verifikasi.sh tidak ada -- verifikasi akhir dilewati"
fi

judul "TAHAP 8/8 -- laporan"
if [ "$KERING" = 1 ]; then
  say ""
  say "  MODE KERING SELESAI. Tidak ada yang dipasang."
  say "  Jalankan lagi tanpa --kering untuk memasang sungguhan."
  exit 0
fi

laporan_sukses "$RC_VERIF"
[ "$RC_VERIF" = 0 ] && exit 0
exit 2
