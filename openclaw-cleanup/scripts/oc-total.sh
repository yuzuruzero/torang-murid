#!/usr/bin/env bash
# =====================================================================
#  OPENCLAW-CLEANUP -- SEKALI JALAN  (oc-total.sh)  v1.2
#
#  SATU perintah, TANPA install Claude, TANPA clone:
#
#    bash <(curl -fsSL https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/openclaw-cleanup/scripts/oc-total.sh)
#
#  Alurnya:
#    [1/4] POTRET     : verifikasi read-only -- apa saja yang terpasang
#                       (kalau sudah bersih, berhenti di sini)
#    [2/4] RENCANA    : dry-run pencabutan -- daftar persis yang akan dihapus
#    [3/4] KONFIRMASI : jawab y/ya, baru eksekusi (lewati dengan -y)
#    [4/4] BUKTI      : verifikasi ulang -- laporan bersih/tidak per item
#
#  PENTING: pakai bentuk  bash <(curl ...)  BUKAN  curl ... | bash
#  (kalau lewat pipe, konfirmasi tak bisa dibaca dan skrip menolak tanpa -y).
#
#  PILIHAN (diteruskan ke mesin di bawahnya):
#    --dry-run | -n     berhenti setelah RENCANA -- tidak ada yang dihapus
#    -y | --yes         tanpa konfirmasi (untuk kelas / otomasi)
#    --sudo             ikut bereskan unit sistem, /etc, /usr/local, /var/log
#    --guru             ikut cabut sisi guru (office, port 19000)
#    --arsip            arsipkan hasil kerja murid dulu (.tar.gz)
#    --sisakan-oc / --sisakan-hm / --sisakan-torang   lewati komponen itu
#    --reset            BUKAN cabut total: backup -> bersihkan -> install ulang
#                       (delegasi ke oc-reset.sh; butuh internet)
#    --tetap-cabut      tetap jalankan pencabutan walau potret awal bersih
#    --bantuan | -h     bantuan ini
#
#  Skrip pendukung (oc-verify.sh, oc-uninstall.sh, oc-reset.sh) dipakai dari
#  folder yang sama bila ada (mis. dari clone/plugin); kalau tidak ada,
#  diunduh sekali ke folder sementara dan dibersihkan otomatis saat selesai.
#
#  KELUAR: 0 = bersih/selesai | 1 = gagal/batal | 2 = masih ada sisa
# =====================================================================
set -uo pipefail

VERSI="1.2"
BASE_URL="${TORANG_BASE_URL:-https://raw.githubusercontent.com/yuzuruzero/torang-murid/main}"
SUB="openclaw-cleanup/scripts"

usage() { sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; }
die()   { echo "[oc-total] GAGAL: $*" >&2; exit 1; }

KERING=0; PAKSA=0; MODE="cabut"; TETAP=0
TERUS=()
for a in "$@"; do
  case "$a" in
    --dry-run|--kering|-n) KERING=1 ;;
    -y|--yes|--paksa)      PAKSA=1 ;;
    --reset)               MODE="reset" ;;
    --tetap-cabut)         TETAP=1 ;;
    --bantuan|-h|--help)   usage; exit 0 ;;
    *)                     TERUS+=("$a") ;;
  esac
done

[ -n "${HOME:-}" ] && [ -d "$HOME" ] || die "\$HOME kosong/bukan folder."
[ "$(id -u)" = "0" ] && die "jangan jalankan sebagai root. Bagian root ditangani lewat --sudo."

# ---------------------------------------------------------------------
# Temukan skrip pendukung: folder sendiri dulu, baru unduh ke mktemp.
# ---------------------------------------------------------------------
BUTUH="oc-verify.sh oc-uninstall.sh"
[ "$MODE" = "reset" ] && BUTUH="$BUTUH oc-reset.sh"

SRC=""
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || true)"
if [ -n "$SELF_DIR" ] && [ "$SELF_DIR" != "/dev/fd" ] && [ "$SELF_DIR" != "/proc/self/fd" ]; then
  LENGKAP=1
  for f in $BUTUH; do [ -f "$SELF_DIR/$f" ] || LENGKAP=0; done
  [ "$LENGKAP" = 1 ] && SRC="$SELF_DIR"
fi

TMP=""
if [ -z "$SRC" ]; then
  command -v curl >/dev/null 2>&1 || die "'curl' tidak ada. Pasang dulu: sudo apt install -y curl"
  TMP="$(mktemp -d /tmp/oc-total.XXXXXX)" || die "tidak bisa membuat folder sementara."
  trap '[ -n "$TMP" ] && rm -rf "$TMP"' EXIT
  echo "[oc-total] mengunduh skrip pendukung dari $BASE_URL ..."
  for f in $BUTUH; do
    curl -fsSL "$BASE_URL/$SUB/$f" -o "$TMP/$f" || die "gagal mengunduh $f (cek internet / repo)."
    [ -s "$TMP/$f" ] || die "$f kosong setelah diunduh."
    bash -n "$TMP/$f" 2>/dev/null || die "$f rusak (sintaks tidak sah)."
  done
  SRC="$TMP"
else
  echo "[oc-total] memakai skrip di $SRC (tanpa unduh)."
fi

# ---------------------------------------------------------------------
# MODE RESET: delegasikan seluruhnya ke oc-reset.sh (punya alur backup
# + konfirmasi sendiri; oc-uninstall.sh tersedia di folder yang sama).
# ---------------------------------------------------------------------
if [ "$MODE" = "reset" ]; then
  ARGS=()
  [ "$KERING" = 1 ] && ARGS+=(--dry-run)
  [ "$PAKSA" = 1 ]  && ARGS+=(-y)
  bash "$SRC/oc-reset.sh" "${ARGS[@]}" ${TERUS[@]+"${TERUS[@]}"}
  exit $?
fi

# ---------------------------------------------------------------------
# MODE CABUT TOTAL
# ---------------------------------------------------------------------
echo ""
echo "================================================================"
echo "  OPENCLAW-CLEANUP -- SEKALI JALAN v$VERSI"
echo "  user: $(id -un)   host: $(hostname 2>/dev/null || echo '?')"
echo "================================================================"

echo ""
echo ">>> [1/4] POTRET KONDISI (read-only) <<<"
bash "$SRC/oc-verify.sh"
RC_AWAL=$?
if [ "$RC_AWAL" = 0 ] && [ "$TETAP" = 0 ]; then
  echo ""
  echo "[oc-total] Sistem SUDAH BERSIH -- tidak ada yang perlu dicabut."
  echo "           (pakai --tetap-cabut kalau tetap mau menjalankan mesin cabut)"
  exit 0
fi

echo ""
echo ">>> [2/4] RENCANA PENCABUTAN (dry-run, belum ada yang dihapus) <<<"
bash "$SRC/oc-uninstall.sh" --dry-run ${TERUS[@]+"${TERUS[@]}"}
RC_RENCANA=$?
[ "$RC_RENCANA" = 0 ] || die "dry-run mesin cabut gagal (exit $RC_RENCANA) -- lihat pesan di atas."

if [ "$KERING" = 1 ]; then
  echo ""
  echo "[oc-total] Mode dry-run selesai -- TIDAK ADA yang diubah."
  echo "           Jalankan lagi tanpa --dry-run untuk benar-benar mencabut."
  exit 0
fi

echo ""
echo ">>> [3/4] KONFIRMASI & EKSEKUSI <<<"
if [ "$PAKSA" = 0 ]; then
  if [ ! -t 0 ]; then
    die "stdin bukan terminal (kemungkinan lewat 'curl | bash'). Pakai bentuk bash <(curl ...) atau tambahkan -y."
  fi
  printf 'Eksekusi rencana di atas sekarang? (y = lanjut, lainnya batal): '
  read -r JWB
  JWB="${JWB//$'\r'/}"   # buang CR: tty aneh/paste Windows mengirim jawaban+CR
  JWB="${JWB,,}"         # huruf kecil semua: y/Y/ya/YA sama saja
  case "$JWB" in y|ya|yes) ;; *) echo "[oc-total] Dibatalkan. Tidak ada yang diubah."; exit 1 ;; esac
fi
bash "$SRC/oc-uninstall.sh" -y ${TERUS[@]+"${TERUS[@]}"}
RC_CABUT=$?

echo ""
echo ">>> [4/4] BUKTI AKHIR (verifikasi ulang) <<<"
bash "$SRC/oc-verify.sh"
RC_AKHIR=$?

echo ""
echo "================================================================"
if [ "$RC_AKHIR" = 0 ]; then
  echo "  SELESAI & BERSIH. Tutup semua terminal lalu buka lagi"
  echo "  (WSL: jalankan 'wsl --shutdown' dari Windows) agar PATH segar."
  echo "  Jangan lupa langkah di luar PC: BotFather /deletebot bot murid,"
  echo "  dan rotate API key OpenAI kelas."
  echo "================================================================"
  exit 0
else
  echo "  MASIH ADA SISA (lihat baris KOTOR di atas)."
  if [ "$RC_CABUT" = 2 ]; then
    echo "  Mesin cabut juga melapor sisa -- biasanya butuh root:"
    echo "  ulangi perintah yang sama dengan tambahan --sudo"
  fi
  echo "================================================================"
  exit 2
fi
