#!/usr/bin/env bash
# =====================================================================
#  OPENCLAW-CLEANUP -- MESIN UNINSTALL  v1.2
#  (turunan torang-bersih-kelas.sh v1.2 yang sudah teruji di kelas Torang)
#
#  Mencabut sampai bersih dari Ubuntu / WSL Ubuntu:
#    1. Torang Event  (monitor murid, plugin torang-events, office guru*)
#    2. OpenClaw      (gateway, plugin, config, sesi, workspace, biner)
#    3. Hermes Agent  (nousresearch) termasuk Node bawaannya
#
#  Urutan SENGAJA: matikan dulu -> Torang -> OpenClaw -> Hermes.
#  Hermes memasang Node-nya sendiri dan menautkan ~/.local/bin/{node,npm,npx};
#  kalau Hermes dicabut duluan, npm ikut hilang dan OpenClaw tak bisa dicabut
#  dengan rapi.
#
#  Node/nvm/npm SISTEM tidak disentuh. Paket apt (ripgrep, ffmpeg, git,
#  build-essential) tidak dicabut -- dipakai hal lain di Ubuntu.
#
#  PAKAI:
#    bash oc-uninstall.sh --dry-run   # LIHAT rencana dulu, tak menghapus apa pun
#    bash oc-uninstall.sh             # interaktif (konfirmasi y/ya)
#    bash oc-uninstall.sh -y          # tanpa tanya -- HANYA setelah pengguna
#                                     # memberi konfirmasi eksplisit di percakapan
#
#  PILIHAN:
#    --dry-run | --kering | -n   rencana saja, tidak ada yang dihapus
#    -y | --yes | --paksa        tanpa prompt konfirmasi internal
#    --sudo                      boleh sudo untuk unit sistem, /etc, /usr/local, /var/log
#    --guru                      ikut cabut sisi guru (~/.torang-guru, ~/torang-office, port 19000)
#    --arsip                     arsipkan hasil kerja murid dulu ke .tar.gz
#    --sisakan-oc                JANGAN cabut OpenClaw
#    --sisakan-hm                JANGAN cabut Hermes
#    --sisakan-torang            JANGAN cabut Torang Event (dipakai /reset)
#    --sisakan-agenlain          JANGAN cabut agen lain kelas (Codex, cua-driver,
#                                agent-browser)
#    --bersihkan-path            ikut buang baris PATH ~/.local/bin dari file rc
#    --bantuan | -h              bantuan
#
#  KELUAR: 0 = bersih  |  1 = gagal/batal  |  2 = masih ada sisa
# =====================================================================
set -uo pipefail

SELF_TAG="oc-uninstall"
SELF_PAT='oc-uninstall|oc-verify|oc-reset|openclaw-cleanup|torang-bersih'
VERSI="1.2"

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------- pilihan ----------
KERING=0; PAKSA=0; GURU=0; ARSIP=0
SISAKAN_OC=0; SISAKAN_HM=0; SISAKAN_TORANG=0; SISAKAN_AGENLAIN=0
BERSIHKAN_PATH=0; PAKAI_SUDO=0

for a in "$@"; do
  case "$a" in
    --dry-run|--kering|-n)  KERING=1 ;;
    -y|--yes|--paksa)       PAKSA=1 ;;
    --guru)                 GURU=1 ;;
    --arsip)                ARSIP=1 ;;
    --sisakan-oc)           SISAKAN_OC=1 ;;
    --sisakan-hm)           SISAKAN_HM=1 ;;
    --sisakan-torang)       SISAKAN_TORANG=1 ;;
    --sisakan-agenlain)     SISAKAN_AGENLAIN=1 ;;
    --bersihkan-path)       BERSIHKAN_PATH=1 ;;
    --sudo)                 PAKAI_SUDO=1 ;;
    --bantuan|-h|--help)    usage; exit 0 ;;
    *) echo "Pilihan tak dikenal: $a  (pakai --bantuan)"; exit 1 ;;
  esac
done

# ---------- pengaman dasar ----------
[ -n "${HOME:-}" ] || { echo "GAGAL: \$HOME kosong. Batal demi keamanan."; exit 1; }
[ -d "$HOME" ]     || { echo "GAGAL: \$HOME ($HOME) bukan folder. Batal."; exit 1; }
if [ "$(id -u)" = "0" ]; then
  echo "GAGAL: jangan jalankan sebagai root/sudo."
  echo "       Semua yang dicabut ada di HOME milik user. Jalankan sebagai user biasa."
  echo "       Bagian yang butuh root ditangani terpisah lewat --sudo."
  exit 1
fi

# OpenClaw boleh dipindah lewat env; hormati kalau di-set (docs: OPENCLAW_STATE_DIR).
OC_STATE="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
OC_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"

CAP="$(date +%Y%m%d-%H%M%S)"
LOG="/tmp/oc-uninstall-$CAP.log"
: > "$LOG"
say()  { printf '%s\n' "$*" | tee -a "$LOG"; }
judul(){ say ""; say "=== $* ==="; }

say "OPENCLAW-CLEANUP -- MESIN UNINSTALL v$VERSI"
say "waktu : $(date '+%Y-%m-%d %H:%M:%S')"
say "user  : $(id -un)   HOME: $HOME   host: $(hostname 2>/dev/null || echo '?')"
say "log   : $LOG"
[ "$KERING" = 1 ] && say ">>> MODE DRY-RUN -- tidak ada yang benar-benar dihapus <<<"

# Regex komponen yang aktif (dipakai untuk unit systemd, cron, autostart).
KOMP_RE=""
tambah_re() { KOMP_RE="${KOMP_RE:+$KOMP_RE|}$1"; }
[ "$SISAKAN_OC" = 0 ]     && tambah_re "openclaw"
[ "$SISAKAN_HM" = 0 ]     && tambah_re "hermes"
[ "$SISAKAN_TORANG" = 0 ] && tambah_re "torang"
if [ -z "$KOMP_RE" ]; then
  say "Semua komponen di-sisakan -- tidak ada pekerjaan. Selesai."
  exit 0
fi

# ---------- konfirmasi internal ----------
if [ "$KERING" = 0 ] && [ "$PAKSA" = 0 ]; then
  if [ ! -t 0 ]; then
    say ""
    say "GAGAL: stdin bukan terminal, konfirmasi tak bisa dibaca."
    say "       Jalankan --dry-run dulu, minta persetujuan pengguna, baru ulangi dengan -y."
    exit 1
  fi
  say ""
  say "Ini akan MENGHAPUS PERMANEN (sesuai pilihan): Torang Event, OpenClaw"
  say "(beserta seluruh workspace & sesi), dan Hermes dari HOME ini."
  printf 'Lanjut hapus? (y = lanjut, lainnya batal): '
  read -r JWB
  JWB="${JWB//$'\r'/}"   # buang CR: tty aneh/paste Windows mengirim jawaban+CR
  JWB="${JWB,,}"         # huruf kecil semua: y/Y/ya/YA sama saja
  case "$JWB" in y|ya|yes) ;; *) say "Dibatalkan. Tidak ada yang diubah."; exit 1 ;; esac
fi

SISA=0   # penanda hasil verifikasi akhir

# =====================================================================
#  Perkakas
# =====================================================================

# Hapus path dengan pagar: tolak kosong, "/", HOME sendiri, folder backup,
# dan apa pun di luar HOME kecuali di-whitelist eksplisit ("luar").
buang() {
  local p="${1:-}" izin_luar="${2:-}"
  [ -n "$p" ] || return 0
  case "$p" in
    "/"|"$HOME"|"$HOME/"|"$HOME/."|".."|".") say "  TOLAK path berbahaya: $p"; return 1 ;;
    "$HOME/openclaw-backup-"*) say "  TOLAK (folder backup dilindungi): $p"; return 1 ;;
  esac
  case "$p" in
    "$HOME"/*) ;;
    *) if [ "$izin_luar" != "luar" ]; then say "  LEWAT (di luar HOME): $p"; return 0; fi ;;
  esac
  if [ ! -e "$p" ] && [ ! -L "$p" ]; then return 0; fi
  local info="folder"; [ -L "$p" ] && info="symlink"; [ -f "$p" ] && info="file"
  if [ "$KERING" = 1 ]; then
    say "  [dry-run] hapus $info : $p"
  else
    if rm -rf -- "$p" 2>>"$LOG"; then say "  hapus $info : $p"
    else say "  GAGAL hapus : $p"; SISA=1; fi
  fi
}

ada_perintah() { command -v "$1" >/dev/null 2>&1; }

# Rantai leluhur proses ini (diri sendiri -> induk -> kakek -> ...).
# WAJIB: kalau skrip dijalankan dari shell yang baris perintahnya kebetulan
# memuat kata "openclaw"/"hermes", pgrep -f akan ikut menemukan shell itu.
# Tanpa pagar ini skrip bisa membunuh terminalnya sendiri di tengah jalan.
LELUHUR=" "
_p=$$
while [ -n "$_p" ] && [ "$_p" != "0" ] && [ "$_p" != "1" ]; do
  LELUHUR="$LELUHUR$_p "
  _p="$(awk '/^PPid:/{print $2}' "/proc/$_p/status" 2>/dev/null)"
done

# Baca cmdline sebuah pid. 2>/dev/null DITARUH SEBELUM < : kalau prosesnya
# sudah lenyap, kegagalan redirect stdin ikut terbungkam (kalau ditaruh
# sesudah, error "No such file" tetap bocor ke layar).
cmd_of() { tr '\0' ' ' 2>/dev/null < "/proc/$1/cmdline" || true; }

bukan_diri_sendiri() {
  case "$LELUHUR" in *" $1 "*) return 1 ;; esac
  local cmd; cmd="$(cmd_of "$1")"
  printf '%s' "$cmd" | grep -Eq "$SELF_PAT" && return 1
  return 0
}

# Matikan proses berdasar pola, TANPA ikut membunuh diri sendiri / induknya.
matikan_pola() {
  local pat="$1" pid daftar="" cmd
  for pid in $(pgrep -f -- "$pat" 2>/dev/null || true); do
    bukan_diri_sendiri "$pid" || continue
    daftar="$daftar $pid"
  done
  [ -n "$daftar" ] || return 0
  for pid in $daftar; do
    cmd="$(cmd_of "$pid" | cut -c1-90)"
    # proses bisa lenyap di antara pgrep dan sekarang (race) -- lewati saja
    [ -n "$cmd" ] || continue
    if [ "$KERING" = 1 ]; then say "  [dry-run] matikan pid $pid : $cmd"
    else say "  matikan pid $pid : $cmd"; kill "$pid" 2>/dev/null; fi
  done
  [ "$KERING" = 1 ] && return 0
  sleep 2
  for pid in $daftar; do
    if kill -0 "$pid" 2>/dev/null; then say "  paksa (KILL) pid $pid"; kill -9 "$pid" 2>/dev/null; fi
  done
}

# Buang baris yang cocok regex dari sebuah file rc, simpan cadangan sekali.
saring_rc() {
  local f="$1" re="$2" label="$3" n
  [ -f "$f" ] || return 0
  n="$(grep -cE "$re" "$f" 2>/dev/null || true)"; n="${n:-0}"
  [ "$n" -gt 0 ] || return 0
  if [ "$KERING" = 1 ]; then
    say "  [dry-run] buang $n baris $label dari $f"
    grep -nE "$re" "$f" | sed 's/^/      /' | tee -a "$LOG"
    return 0
  fi
  # KEBIJAKAN: penghapusan TANPA membuat backup apa pun -- rc disunting
  # langsung, dan sisa .torang-bak dari versi lama ikut disapu.
  # PENTING: grep -v keluar dengan kode 1 kalau TIDAK ADA baris tersisa
  # (mis. seluruh isi file cocok). Itu sukses, bukan gagal -- kode <=1 = aman.
  grep -vE "$re" "$f" > "$f.tmp-torang" 2>/dev/null
  local rc=$?
  if [ "$rc" -le 1 ] && mv "$f.tmp-torang" "$f"; then
    say "  buang $n baris $label dari $f"
    rm -f "$f.torang-bak" 2>/dev/null
  else
    rm -f "$f.tmp-torang"; say "  GAGAL menyunting $f (grep rc=$rc)"; SISA=1
  fi
}

# Apakah ADA yang mendengar di port ini? Dibaca dari /proc/net/tcp yang SELALU
# ada -- tidak bergantung ss/lsof/fuser yang belum tentu terpasang di WSL polos.
port_terpakai() {
  local port="$1" hex; hex="$(printf '%04X' "$port")"
  awk -v h=":$hex" '$4=="0A" && $2 ~ h"$"{f=1} END{exit !f}' /proc/net/tcp  2>/dev/null && return 0
  awk -v h=":$hex" '$4=="0A" && $2 ~ h"$"{f=1} END{exit !f}' /proc/net/tcp6 2>/dev/null && return 0
  return 1
}

# PID yang memegang port. Beberapa cara, karena tak satu pun dijamin ada.
pid_port() {
  local port="$1" pids="" inode p
  if ada_perintah ss; then
    pids="$(ss -ltnpH "sport = :$port" 2>/dev/null | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u)"
  fi
  if [ -z "$pids" ] && ada_perintah lsof; then
    pids="$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | sort -u)"
  fi
  if [ -z "$pids" ] && ada_perintah fuser; then
    pids="$(fuser -n tcp "$port" 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' | sort -u)"
  fi
  if [ -z "$pids" ]; then   # jalur terakhir: inode socket -> pemilik fd
    local hex; hex="$(printf '%04X' "$port")"
    inode="$(awk -v h=":$hex" '$4=="0A" && $2 ~ h"$"{print $10; exit}' /proc/net/tcp /proc/net/tcp6 2>/dev/null)"
    if [ -n "$inode" ]; then
      for p in /proc/[0-9]*; do
        if ls -l "$p/fd" 2>/dev/null | grep -q "socket:\[$inode\]"; then pids="${p#/proc/}"; break; fi
      done
    fi
  fi
  echo $pids
}

bunuh_pemegang_port() {
  local port="$1" label="$2" pid
  local PP; PP="$(pid_port "$port")"
  if port_terpakai "$port" || [ -n "$PP" ]; then
    say "  port $label $port masih dipakai (pid:${PP:-tak terbaca})"
    for pid in $PP; do
      bukan_diri_sendiri "$pid" || continue
      if [ "$KERING" = 1 ]; then say "  [dry-run] matikan pemegang port $port : pid $pid"
      else
        say "  matikan pemegang port $port : pid $pid"
        kill "$pid" 2>/dev/null; sleep 2
        kill -0 "$pid" 2>/dev/null && { say "  paksa (KILL) pid $pid"; kill -9 "$pid" 2>/dev/null; }
      fi
    done
  else
    say "  port $label $port sudah bebas"
  fi
}

# docker: coba tanpa sudo dulu; kalau tak boleh dan --sudo, pakai sudo.
dkr() {
  if docker "$@" 2>>"$LOG"; then return 0; fi
  if [ "$PAKAI_SUDO" = 1 ] && ada_perintah sudo; then sudo docker "$@" 2>>"$LOG"; return $?; fi
  return 1
}

# =====================================================================
#  TAHAP 0 -- DETEKSI METODE INSTAL
#  Dilaporkan dulu supaya jelas APA yang akan dicabut dengan cara apa.
# =====================================================================
judul "TAHAP 0/7 -- deteksi metode instal"

PIP_BIN="$(command -v pip3 2>/dev/null || command -v pip 2>/dev/null || true)"

deteksi_pm() {  # $1 = nama paket (regex)
  local hasil=""
  if ada_perintah npm  && npm ls -g --depth=0 2>/dev/null | grep -qiE "$1"; then hasil="$hasil npm-global"; fi
  if ada_perintah pnpm && pnpm list -g --depth=0 2>/dev/null | grep -qiE "$1"; then hasil="$hasil pnpm-global"; fi
  if ada_perintah bun  && bun pm ls -g 2>/dev/null | grep -qiE "$1"; then hasil="$hasil bun-global"; fi
  if ada_perintah pipx && pipx list --short 2>/dev/null | awk '{print $1}' | grep -qiE "^($1)"; then hasil="$hasil pipx"; fi
  if [ -n "$PIP_BIN" ] && "$PIP_BIN" list --format=freeze 2>/dev/null | cut -d= -f1 | grep -qiE "^($1)"; then hasil="$hasil pip"; fi
  echo "$hasil"
}

deteksi_docker() {  # $1 = regex
  ada_perintah docker || { echo ""; return; }
  local c i
  c="$(docker ps -a --format '{{.Names}} ({{.Image}})' 2>/dev/null | grep -iE "$1" | tr '\n' ' ' || true)"
  i="$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -iE "$1" | tr '\n' ' ' || true)"
  [ -n "$c$i" ] && echo "container:[${c:-#}] image:[${i:-#}]" | tr -d '#'
}

lapor_komponen() {  # $1 label, $2 regex paket, $3 dir state, $4 nama biner
  say "  [$1]"
  local biner pm dock
  biner="$(type -aP "$4" 2>/dev/null | tr '\n' ' ' || true)"
  pm="$(deteksi_pm "$2")"
  dock="$(deteksi_docker "$2")"
  [ -e "$3" ]        && say "      state/config : $3 (ada)"        || say "      state/config : -"
  [ -n "$biner" ]    && say "      biner PATH   : $biner"          || say "      biner PATH   : -"
  [ -n "$pm" ]       && say "      paket        :$pm"              || say "      paket        : -"
  [ -n "$dock" ]     && say "      docker       : $dock"           || say "      docker       : -"
}

[ "$SISAKAN_OC" = 0 ]     && lapor_komponen "OpenClaw"     'openclaw'          "$OC_STATE"             "openclaw"
[ "$SISAKAN_HM" = 0 ]     && lapor_komponen "Hermes"       'hermes(-agent)?'   "$HOME/.hermes"         "hermes"
[ "$SISAKAN_TORANG" = 0 ] && lapor_komponen "Torang Event" 'torang'            "$HOME/.torang"         "torang"

# =====================================================================
#  TAHAP 1 -- MATIKAN SEMUANYA DULU
#  Auto-start dicabut PALING AWAL supaya tak ada yang hidup lagi
#  begitu proses dibunuh.
# =====================================================================
judul "TAHAP 1/7 -- cabut auto-start & matikan proses/service"

RE_TORANG_RC='(\.torang(-guru)?/start\.sh|^[[:space:]]*#[[:space:]]*Torang)'
if [ "$SISAKAN_TORANG" = 0 ]; then
  for f in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    saring_rc "$f" "$RE_TORANG_RC" "auto-start Torang"
  done
fi

# Sapu TANPA SYARAT cadangan .torang-bak sisa versi lama (kebijakan: tanpa
# backup). Dulu hanya tersapu saat file rc masih disunting -- celah: di PC
# yang sudah pernah dibersihkan, bak basi tertinggal selamanya.
for f in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshrc" "$HOME/.npmrc"; do
  buang "$f.torang-bak"
done

# systemd milik user (di WSL sering tidak aktif -- ditangani dengan anggun)
if ada_perintah systemctl && systemctl --user show >/dev/null 2>&1; then
  UNIT_USER="$(systemctl --user list-unit-files --no-legend --plain 2>/dev/null | awk '{print $1}' \
               | grep -Ei "$KOMP_RE" || true)"
  UNIT_AKTIF="$(systemctl --user list-units --no-legend --plain 2>/dev/null | awk '{print $1}' \
               | grep -Ei "$KOMP_RE" || true)"
  UNITS="$(printf '%s\n%s\n' "$UNIT_USER" "$UNIT_AKTIF" | sort -u | sed '/^$/d')"
  if [ -n "$UNITS" ]; then
    for u in $UNITS; do
      if [ "$KERING" = 1 ]; then say "  [dry-run] stop+disable unit user: $u"
      else
        say "  stop+disable unit user: $u"
        systemctl --user stop    "$u" >>"$LOG" 2>&1
        systemctl --user disable "$u" >>"$LOG" 2>&1
      fi
      buang "$HOME/.config/systemd/user/$u"
    done
    if [ "$KERING" = 0 ]; then
      systemctl --user daemon-reload >>"$LOG" 2>&1
      systemctl --user reset-failed  >>"$LOG" 2>&1
    fi
  else
    say "  tidak ada unit systemd --user yang cocok ($KOMP_RE)"
  fi
else
  say "  systemd --user tidak aktif di sini (wajar di WSL) -- dilewati"
fi

# File unit tetap disapu walau systemd tidak aktif, supaya tidak menyala lagi
# kalau kelak systemd dihidupkan di WSL (/etc/wsl.conf systemd=true).
if [ -d "$HOME/.config/systemd/user" ]; then
  for f in "$HOME/.config/systemd/user"/*; do
    [ -e "$f" ] || continue
    basename "$f" | grep -qiE "$KOMP_RE" && buang "$f"
  done
fi

# Gateway OpenClaw = unit systemd USER openclaw-gateway.service (varian profil
# openclaw-gateway-<profil>.service). Ini yang paling sering tertinggal --
# pastikan sekali lagi secara eksplisit.
if [ "$SISAKAN_OC" = 0 ] && ada_perintah systemctl && systemctl --user show >/dev/null 2>&1; then
  for u in $(systemctl --user list-unit-files --no-legend --plain 2>/dev/null \
             | awk '{print $1}' | grep -E '^openclaw-gateway' || true); do
    if [ "$KERING" = 1 ]; then say "  [dry-run] disable --now $u"
    else
      say "  disable --now $u"
      systemctl --user disable --now "$u" >>"$LOG" 2>&1
    fi
    buang "$HOME/.config/systemd/user/$u"
  done
  [ "$KERING" = 0 ] && systemctl --user daemon-reload >>"$LOG" 2>&1
fi

# unit systemd tingkat SISTEM: dilaporkan; dieksekusi hanya dengan --sudo
UNIT_SIS="$(ls -1 /etc/systemd/system 2>/dev/null | grep -Ei "$KOMP_RE" || true)"
if [ -n "$UNIT_SIS" ]; then
  say "  DITEMUKAN unit systemd tingkat SISTEM:"
  printf '%s\n' "$UNIT_SIS" | sed 's/^/      /' | tee -a "$LOG"
  if [ "$PAKAI_SUDO" = 1 ] && [ "$KERING" = 0 ] && ada_perintah sudo; then
    for u in $UNIT_SIS; do
      say "  (sudo) stop+disable+hapus $u"
      sudo systemctl stop    "$u" >>"$LOG" 2>&1
      sudo systemctl disable "$u" >>"$LOG" 2>&1
      sudo rm -f "/etc/systemd/system/$u" >>"$LOG" 2>&1
    done
    sudo systemctl daemon-reload >>"$LOG" 2>&1
    sudo systemctl reset-failed  >>"$LOG" 2>&1
  elif [ "$KERING" = 1 ]; then
    say "  [dry-run] perlu --sudo untuk: stop+disable+hapus unit di atas"
  else
    say "  -> TIDAK disentuh (perlu root). Ulangi dengan --sudo, atau manual:"
    for u in $UNIT_SIS; do say "       sudo systemctl disable --now $u && sudo rm /etc/systemd/system/$u"; done
    SISA=1
  fi
fi

# minta OpenClaw menutup dirinya baik-baik dulu (kalau masih bisa)
if [ "$SISAKAN_OC" = 0 ] && ada_perintah openclaw && [ "$KERING" = 0 ]; then
  say "  minta openclaw menonaktifkan plugin & menghentikan gateway..."
  timeout 60 openclaw plugins disable torang-events >>"$LOG" 2>&1
  timeout 90 openclaw gateway stop                  >>"$LOG" 2>&1
fi

# proses latar
POLA_MATI=""
[ "$SISAKAN_TORANG" = 0 ] && POLA_MATI="$POLA_MATI monitor-client\.js \.torang/start\.sh \.torang-guru/start\.sh"
[ "$SISAKAN_OC" = 0 ]     && POLA_MATI="$POLA_MATI openclaw"
[ "$SISAKAN_HM" = 0 ]     && POLA_MATI="$POLA_MATI hermes"
# Sisi guru: office Flask jalan sebagai `python3 backend/app.py` di port 19000.
[ "$GURU" = 1 ]           && POLA_MATI="$POLA_MATI backend/app\.py"
for pola in $POLA_MATI; do
  matikan_pola "$pola"
done

# Proses yatim yang MASIH MEMEGANG port gateway. Biang kerok nomor satu saat
# pasang ulang: `openclaw gateway stop` sering TIDAK membunuhnya, port 18789
# tetap terpakai, gateway baru gagal bind (EADDRINUSE) -- systemd bilang
# "active" tapi dashboard tak bisa dibuka.
[ "$SISAKAN_OC" = 0 ] && bunuh_pemegang_port "$OC_PORT" "gateway"
[ "$GURU" = 1 ]       && bunuh_pemegang_port "${TORANG_PORT:-19000}" "office guru"

# cron milik user yang mungkin menghidupkan lagi
if ada_perintah crontab; then
  if crontab -l 2>/dev/null | grep -qEi "$KOMP_RE"; then
    say "  PERINGATAN: ada baris crontab yang cocok ($KOMP_RE):"
    crontab -l 2>/dev/null | grep -Ei "$KOMP_RE" | sed 's/^/      /' | tee -a "$LOG"
    if [ "$KERING" = 0 ]; then
      crontab -l 2>/dev/null | grep -vEi "$KOMP_RE" | crontab - 2>>"$LOG" \
        && say "  baris crontab tsb dibuang" || { say "  GAGAL menyunting crontab"; SISA=1; }
    else
      say "  [dry-run] baris crontab tsb akan dibuang"
    fi
  fi
fi

# entry autostart desktop (~/.config/autostart)
if [ -d "$HOME/.config/autostart" ]; then
  for f in "$HOME/.config/autostart"/*.desktop; do
    [ -e "$f" ] || continue
    if basename "$f" | grep -qiE "$KOMP_RE" || grep -qiE "$KOMP_RE" "$f" 2>/dev/null; then
      buang "$f"
    fi
  done
fi

# hook boot WSL
if [ -f /etc/wsl.conf ] && grep -qEi "$KOMP_RE" /etc/wsl.conf 2>/dev/null; then
  say "  PERINGATAN: /etc/wsl.conf memuat baris terkait -- perlu disunting manual (root):"
  grep -nEi "$KOMP_RE" /etc/wsl.conf | sed 's/^/      /' | tee -a "$LOG"
  SISA=1
fi

# =====================================================================
#  TAHAP 2 -- ARSIP (opsional)
# =====================================================================
if [ "$ARSIP" = 1 ]; then
  judul "TAHAP 2/7 -- arsipkan hasil kerja murid"
  ARS="$HOME/arsip-kelas-$CAP.tar.gz"
  ADA=""
  for d in "$OC_STATE/workspace" "$HOME/.hermes/memories" "$HOME/.hermes/sessions"; do
    [ -d "$d" ] && ADA="$ADA ${d#$HOME/}"
  done
  if [ -n "$ADA" ]; then
    if [ "$KERING" = 1 ]; then say "  [dry-run] arsipkan ->$ADA  ke $ARS"
    else
      if tar -czf "$ARS" -C "$HOME" $ADA 2>>"$LOG"; then
        say "  arsip dibuat: $ARS ($(du -h "$ARS" 2>/dev/null | cut -f1))"
        say "  >>> SALIN arsip ini keluar sebelum PC dipakai kelas berikutnya <<<"
      else say "  GAGAL membuat arsip -- pembersihan DIHENTIKAN demi keamanan."; exit 1; fi
    fi
  else
    say "  tidak ada yang perlu diarsipkan"
  fi
else
  judul "TAHAP 2/7 -- arsip dilewati (pakai --arsip kalau perlu)"
fi

# =====================================================================
#  TAHAP 3 -- TORANG EVENT
# =====================================================================
if [ "$SISAKAN_TORANG" = 1 ]; then
  judul "TAHAP 3/7 -- Torang Event dilewati (--sisakan-torang)"
else
  judul "TAHAP 3/7 -- cabut Torang Event"
  buang "$HOME/.torang"
  buang "$HOME/.torang-plugin"
  buang "$HOME/.torang-monitor"
  buang "$HOME/.torang-events.env"
  buang "$HOME/.torang-events-state.json"
  buang "$HOME/torang-events.log"
  buang "$HOME/.torang-events.log"
  buang "$HOME/.config/torang"
  buang "$HOME/.cache/torang"
  buang "$HOME/.local/share/torang"
  buang "$HOME/.local/state/torang"
  if [ "$GURU" = 1 ]; then
    say "  (mode --guru) ikut cabut sisi guru:"
    buang "$HOME/.torang-guru"
    buang "$HOME/torang-office"
  else
    for d in "$HOME/.torang-guru" "$HOME/torang-office"; do
      [ -e "$d" ] && say "  ADA sisi guru di sini: $d (tidak disentuh; pakai --guru kalau memang mau dicabut)"
    done
  fi
fi

# =====================================================================
#  TAHAP 4 -- OPENCLAW
#  Dicabut SEBELUM Hermes, karena npm bisa saja milik Hermes.
# =====================================================================
if [ "$SISAKAN_OC" = 1 ]; then
  judul "TAHAP 4/7 -- OpenClaw dilewati (--sisakan-oc)"
else
  judul "TAHAP 4/7 -- cabut OpenClaw"
  say "  biner yang terlihat sekarang:"
  { type -aP openclaw 2>/dev/null || echo "      (tidak ada)"; } | sed 's/^/      /' | tee -a "$LOG"

  # 4a. Jalur RESMI dulu (docs.openclaw.ai/install/uninstall). Kalau berhasil,
  #     sapuan manual di bawah tinggal memungut sisa.
  if ada_perintah openclaw; then
    if [ "$KERING" = 1 ]; then
      say "  [dry-run] openclaw uninstall --all --yes --non-interactive"
    else
      say "  openclaw uninstall --all --yes --non-interactive"
      timeout 300 openclaw uninstall --all --yes --non-interactive >>"$LOG" 2>&1 \
        && say "  uninstaller resmi selesai" \
        || say "  (uninstaller resmi gagal/tidak ada -- lanjut cabut manual)"
    fi
  fi

  # 4b. Paket global: npm resmi, tapi bisa juga pnpm/bun.
  for PM in "$(command -v npm 2>/dev/null || true)" \
            "$HOME/.npm-global/bin/npm" \
            "$HOME/.hermes/node/bin/npm" \
            "/usr/local/bin/npm" \
            "$(command -v pnpm 2>/dev/null || true)" \
            "$(command -v bun 2>/dev/null || true)" ; do
    [ -n "$PM" ] && [ -x "$PM" ] || continue
    case "$(basename "$PM")" in
      npm)  SUB="rm -g"     ; LS="ls -g --depth=0" ;;
      pnpm) SUB="remove -g" ; LS="list -g --depth=0" ;;
      bun)  SUB="remove -g" ; LS="pm ls -g" ;;
      *) continue ;;
    esac
    if $PM $LS 2>/dev/null | grep -qi 'openclaw'; then
      if [ "$KERING" = 1 ]; then say "  [dry-run] $PM $SUB openclaw"
      else
        say "  $PM $SUB openclaw"
        timeout 180 $PM $SUB openclaw >>"$LOG" 2>&1 || say "  ($PM gagal -- folder tetap dihapus manual di bawah)"
      fi
    fi
  done

  # 4b2. Instalasi npm sisi WINDOWS -- terlihat dari WSL sebagai biner di
  #      /mnt/<drive>/... (PATH Windows diwariskan ke WSL). npm di dalam WSL
  #      TIDAK BISA mencabutnya dan sudo TIDAK membantu. Jalur benar: interop
  #      cmd.exe (menjalankan npm WINDOWS asli), lalu sapu shim + modulnya.
  WIN_BIN="$(type -aP openclaw 2>/dev/null | grep -E '^/mnt/[a-z]/' || true)"
  if [ -n "$WIN_BIN" ]; then
    say "  TERDETEKSI instalasi npm sisi WINDOWS:"
    printf '%s\n' "$WIN_BIN" | sed 's/^/      /' | tee -a "$LOG"
    CMDEXE=""
    ada_perintah cmd.exe && CMDEXE="cmd.exe"
    [ -z "$CMDEXE" ] && [ -x /mnt/c/Windows/System32/cmd.exe ] && CMDEXE="/mnt/c/Windows/System32/cmd.exe"
    if [ -n "$CMDEXE" ]; then
      if [ "$KERING" = 1 ]; then
        say "  [dry-run] (npm Windows) $CMDEXE /c \"npm rm -g openclaw\""
      else
        say "  (npm Windows) npm rm -g openclaw ... (bisa sampai 1-2 menit)"
        ( cd /mnt/c 2>/dev/null && timeout 240 "$CMDEXE" /c "npm rm -g openclaw" ) >>"$LOG" 2>&1 \
          && say "  npm Windows selesai mencabut" \
          || say "  (npm Windows gagal/lambat -- shim disapu langsung di bawah)"
      fi
    else
      say "  cmd.exe tidak terjangkau dari sini -- shim disapu langsung"
    fi
    while IFS= read -r b; do
      [ -n "$b" ] || continue
      NPMDIR="$(dirname "$b")"
      case "$NPMDIR" in
        /mnt/[a-z]/*npm)
          for t in "$NPMDIR/openclaw" "$NPMDIR/openclaw.cmd" "$NPMDIR/openclaw.ps1"; do
            { [ -e "$t" ] || [ -L "$t" ]; } && buang "$t" luar
          done
          [ -d "$NPMDIR/node_modules/openclaw" ] && buang "$NPMDIR/node_modules/openclaw" luar
          ;;
        *) say "  LEWAT (bukan folder npm Windows yang dikenal): $b" ;;
      esac
    done < <(printf '%s\n' "$WIN_BIN")
  fi

  # 4c. pipx / pip (kalau ada yang memasang lewat jalur Python)
  if ada_perintah pipx; then
    for p in $(pipx list --short 2>/dev/null | awk '{print $1}' | grep -iE '^openclaw' || true); do
      if [ "$KERING" = 1 ]; then say "  [dry-run] pipx uninstall $p"
      else say "  pipx uninstall $p"; timeout 120 pipx uninstall "$p" >>"$LOG" 2>&1 || SISA=1; fi
    done
  fi
  if [ -n "$PIP_BIN" ]; then
    for p in $("$PIP_BIN" list --format=freeze 2>/dev/null | cut -d= -f1 | grep -iE '^openclaw' || true); do
      if [ "$KERING" = 1 ]; then say "  [dry-run] $PIP_BIN uninstall -y $p"
      else
        say "  $PIP_BIN uninstall -y $p"
        timeout 120 "$PIP_BIN" uninstall -y --break-system-packages "$p" >>"$LOG" 2>&1 \
          || timeout 120 "$PIP_BIN" uninstall -y "$p" >>"$LOG" 2>&1 || SISA=1
      fi
    done
  fi

  # 4d. State dir -- hormati OPENCLAW_STATE_DIR / OPENCLAW_CONFIG_PATH kalau di-set.
  buang "$OC_STATE"
  [ -n "${OPENCLAW_CONFIG_PATH:-}" ] && buang "$OPENCLAW_CONFIG_PATH"
  [ "$OC_STATE" = "$HOME/.openclaw" ] || buang "$HOME/.openclaw"
  buang "$HOME/.config/openclaw"
  buang "$HOME/.cache/openclaw"
  buang "$HOME/.local/share/openclaw"
  buang "$HOME/.local/state/openclaw"
  for b in "$HOME/.local/bin/openclaw" "$HOME/.npm-global/bin/openclaw" \
           "$HOME/bin/openclaw" "$HOME/.hermes/node/bin/openclaw"; do
    buang "$b"
  done
  for b in /usr/local/bin/openclaw /usr/bin/openclaw /etc/openclaw; do
    if [ -e "$b" ]; then
      if [ "$PAKAI_SUDO" = 1 ] && [ "$KERING" = 0 ] && ada_perintah sudo; then
        say "  (sudo) hapus $b"; sudo rm -rf "$b" >>"$LOG" 2>&1
      elif [ "$KERING" = 1 ]; then
        say "  [dry-run] perlu --sudo: hapus $b"
      else
        say "  ADA di luar HOME: $b -> perlu root. Manual: sudo rm -rf $b"; SISA=1
      fi
    fi
  done
fi

# =====================================================================
#  TAHAP 5 -- HERMES  (paling akhir: dia pemilik tautan node/npm/npx)
# =====================================================================
if [ "$SISAKAN_HM" = 1 ]; then
  judul "TAHAP 5/7 -- Hermes dilewati (--sisakan-hm)"
else
  judul "TAHAP 5/7 -- cabut Hermes Agent"

  # pipx / pip dulu selagi toolchain masih utuh
  if ada_perintah pipx; then
    for p in $(pipx list --short 2>/dev/null | awk '{print $1}' | grep -iE '^hermes' || true); do
      if [ "$KERING" = 1 ]; then say "  [dry-run] pipx uninstall $p"
      else say "  pipx uninstall $p"; timeout 120 pipx uninstall "$p" >>"$LOG" 2>&1 || SISA=1; fi
    done
  fi
  if [ -n "$PIP_BIN" ]; then
    for p in $("$PIP_BIN" list --format=freeze 2>/dev/null | cut -d= -f1 | grep -iE '^hermes' || true); do
      if [ "$KERING" = 1 ]; then say "  [dry-run] $PIP_BIN uninstall -y $p"
      else
        say "  $PIP_BIN uninstall -y $p"
        timeout 120 "$PIP_BIN" uninstall -y --break-system-packages "$p" >>"$LOG" 2>&1 \
          || timeout 120 "$PIP_BIN" uninstall -y "$p" >>"$LOG" 2>&1 || SISA=1
      fi
    done
  fi

  buang "$HOME/.hermes"
  buang "$HOME/.config/hermes"
  buang "$HOME/.cache/hermes"
  buang "$HOME/.local/share/hermes"
  buang "$HOME/.local/state/hermes"

  # Biner/berkas BERAWALAN hermes di ~/.local/bin (installer Hermes baru
  # menulis hermes-acp & hermes-agent sebagai FILE biasa, bukan symlink --
  # nama berawalan hermes = milik Hermes, sapu semua).
  for L in "$HOME/.local/bin"/hermes*; do
    { [ -e "$L" ] || [ -L "$L" ]; } || continue
    buang "$L"
  done
  # Toolchain uv (dipakai Hermes): python yang dipasang uv hidup di sini;
  # symlink ~/.local/bin/python* yang menunjuk ke sana ikut mati dan disapu
  # oleh sapuan tautan menggantung di Tahap 6.
  buang "$HOME/.local/share/uv"

  # tautan yang dibuat Hermes di ~/.local/bin -- hapus HANYA kalau menunjuk ke
  # ~/.hermes atau sudah menggantung (target hilang). Node sistem/nvm aman.
  for t in hermes node npm npx uv; do
    L="$HOME/.local/bin/$t"
    if [ -L "$L" ]; then
      TARGET="$(readlink -f "$L" 2>/dev/null || true)"
      # Menggantung dicek dengan [ ! -e ] (mengikuti symlink), BUKAN lewat
      # kegagalan readlink -f: readlink -f tetap sukses kalau hanya komponen
      # terakhir target yang hilang, jadi tautan menggantung bisa lolos.
      if [ ! -e "$L" ]; then
        say "  tautan menggantung: $t -> ${TARGET:-?}"; buang "$L"
      else
        case "${TARGET:-}" in
          "$HOME/.hermes"/*) say "  tautan Hermes: $t -> $TARGET"; buang "$L" ;;
          *)                 say "  biarkan $t (menunjuk ke $TARGET -- bukan milik Hermes)" ;;
        esac
      fi
    elif [ -f "$L" ] && grep -qi 'hermes' "$L" 2>/dev/null; then
      say "  shim Hermes: $t"; buang "$L"
    fi
  done

  buang "$HOME/.cache/ms-playwright"
  buang "$HOME/.cache/uv"

  for b in /usr/local/bin/hermes /usr/local/lib/hermes-agent /etc/hermes; do
    if [ -e "$b" ]; then
      if [ "$PAKAI_SUDO" = 1 ] && [ "$KERING" = 0 ] && ada_perintah sudo; then
        say "  (sudo) hapus $b"; sudo rm -rf "$b" >>"$LOG" 2>&1
      elif [ "$KERING" = 1 ]; then
        say "  [dry-run] perlu --sudo: hapus $b"
      else
        say "  ADA di luar HOME: $b -> perlu root. Manual: sudo rm -rf $b"; SISA=1
      fi
    fi
  done

  # npmrc yang mengarahkan prefix global ke Hermes
  if [ -f "$HOME/.npmrc" ] && grep -qi 'hermes' "$HOME/.npmrc" 2>/dev/null; then
    saring_rc "$HOME/.npmrc" 'hermes' "prefix npm milik Hermes"
  fi

  if [ "$BERSIHKAN_PATH" = 1 ]; then
    RE_PATH='(\.local/bin.*PATH|PATH.*\.local/bin|fish_add_path.*\.local/bin)'
    for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" \
             "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.config/fish/config.fish"; do
      saring_rc "$f" "$RE_PATH" "PATH ~/.local/bin"
    done
  else
    say "  baris PATH ~/.local/bin DIBIARKAN (tidak berbahaya). Pakai --bersihkan-path kalau mau dibuang."
  fi
fi

# =====================================================================
#  TAHAP 5b -- AGEN LAIN KELAS (Codex, cua-driver, agent-browser)
#  Ikut terpasang di PC murid selama kelas; disapu supaya PC benar-benar
#  kembali kosong. Lewati dengan --sisakan-agenlain.
# =====================================================================
if [ "$SISAKAN_AGENLAIN" = 1 ]; then
  judul "TAHAP 5b/7 -- agen lain dilewati (--sisakan-agenlain)"
else
  judul "TAHAP 5b/7 -- cabut agen lain kelas (Codex, cua-driver, agent-browser)"
  matikan_pola 'cua-driver'
  matikan_pola 'agent-browser'
  buang "$HOME/.codex"
  buang "$HOME/.config/codex"
  buang "$HOME/.cache/codex"
  buang "$HOME/.cua-driver"
  buang "$HOME/.agent-browser"
  buang "$HOME/.cache/agent-browser"
  buang "$HOME/.local/bin/cua-driver"
  buang "$HOME/.local/bin/agent-browser"
fi

# =====================================================================
#  TAHAP 6 -- DOCKER & CACHE
# =====================================================================
judul "TAHAP 6/7 -- docker & cache"

if ada_perintah docker; then
  CIDS="$(docker ps -a --format '{{.ID}}\t{{.Names}}\t{{.Image}}' 2>/dev/null | grep -iE "$KOMP_RE" | cut -f1 || true)"
  if [ -n "$CIDS" ]; then
    for c in $CIDS; do
      if [ "$KERING" = 1 ]; then say "  [dry-run] docker rm -f $c"
      else say "  docker rm -f $c"; dkr rm -f "$c" >/dev/null || { say "  GAGAL docker rm $c (butuh izin group docker / --sudo?)"; SISA=1; }; fi
    done
  fi
  IIDS="$(docker images --format '{{.ID}}\t{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -iE "$KOMP_RE" | cut -f1 | sort -u || true)"
  if [ -n "$IIDS" ]; then
    for i in $IIDS; do
      if [ "$KERING" = 1 ]; then say "  [dry-run] docker rmi -f $i"
      else say "  docker rmi -f $i"; dkr rmi -f "$i" >/dev/null || { say "  GAGAL docker rmi $i"; SISA=1; }; fi
    done
  fi
  VOLS="$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -iE "$KOMP_RE" || true)"
  if [ -n "$VOLS" ]; then
    for v in $VOLS; do
      if [ "$KERING" = 1 ]; then say "  [dry-run] docker volume rm $v"
      else say "  docker volume rm $v"; dkr volume rm "$v" >/dev/null || { say "  GAGAL docker volume rm $v"; SISA=1; }; fi
    done
  fi
  [ -z "$CIDS$IIDS$VOLS" ] && say "  tidak ada container/image/volume docker yang cocok"
else
  say "  docker tidak terpasang -- dilewati"
fi

# Residu toolchain npm KELAS: cache ~/.npm, prefix global ~/.npm-global,
# dan baris prefix di ~/.npmrc. Hanya bila OpenClaw DAN Hermes sama-sama
# dicabut (kalau salah satu disisakan, npm-global bisa masih dipakai).
if [ "$SISAKAN_OC" = 0 ] && [ "$SISAKAN_HM" = 0 ]; then
  buang "$HOME/.npm"
  buang "$HOME/.npm-global"
  if [ -f "$HOME/.npmrc" ] && grep -q 'npm-global' "$HOME/.npmrc" 2>/dev/null; then
    saring_rc "$HOME/.npmrc" 'npm-global' "prefix npm-global"
  fi
  # .npmrc yang jadi kosong setelah disaring tidak berguna -- buang sekalian
  [ "$KERING" = 0 ] && [ -f "$HOME/.npmrc" ] && [ ! -s "$HOME/.npmrc" ] && buang "$HOME/.npmrc"
else
  if ada_perintah npm && [ "$KERING" = 0 ]; then
    say "  npm cache clean --force"
    timeout 120 npm cache clean --force >>"$LOG" 2>&1 || buang "$HOME/.npm/_cacache"
  fi
fi

# cache pip (bisa dibangun ulang)
if [ "$KERING" = 1 ]; then
  [ -n "$PIP_BIN" ] && say "  [dry-run] $PIP_BIN cache purge"
  [ -d "$HOME/.cache/pip" ] && say "  [dry-run] hapus $HOME/.cache/pip (fallback)"
else
  if [ -n "$PIP_BIN" ]; then
    say "  $PIP_BIN cache purge"
    timeout 120 "$PIP_BIN" cache purge >>"$LOG" 2>&1 || buang "$HOME/.cache/pip"
  else
    buang "$HOME/.cache/pip"
  fi
fi

# Symlink MENGGANTUNG di ~/.local/bin -- target sudah dihapus tahap-tahap
# sebelumnya (mis. python3.11 -> ~/.local/share/uv/...). Broken link tidak
# berguna dan membuat installer berikutnya gagal di tengah jalan.
if [ -d "$HOME/.local/bin" ]; then
  for L in "$HOME/.local/bin"/*; do
    [ -L "$L" ] && [ ! -e "$L" ] && { say "  tautan menggantung: $(basename "$L")"; buang "$L"; }
  done
fi

# log di /var/log (biasanya butuh root)
for f in /var/log/openclaw* /var/log/hermes* /var/log/torang*; do
  [ -e "$f" ] || continue
  basename "$f" | grep -qiE "$KOMP_RE" || continue
  if [ "$PAKAI_SUDO" = 1 ] && [ "$KERING" = 0 ] && ada_perintah sudo; then
    say "  (sudo) hapus $f"; sudo rm -rf "$f" >>"$LOG" 2>&1
  elif [ "$KERING" = 1 ]; then
    say "  [dry-run] perlu --sudo: hapus $f"
  else
    say "  ADA log sistem: $f -> perlu root. Manual: sudo rm -rf $f"; SISA=1
  fi
done

# =====================================================================
#  TAHAP 7 -- VERIFIKASI
# =====================================================================
judul "TAHAP 7/7 -- verifikasi"

CEK_PATH=""
[ "$SISAKAN_TORANG" = 0 ]   && CEK_PATH="$CEK_PATH $HOME/.torang $HOME/.torang-plugin $HOME/.torang-monitor $HOME/torang-events.log $HOME/.torang-events-state.json"
[ "$SISAKAN_OC" = 0 ]       && CEK_PATH="$CEK_PATH $OC_STATE $HOME/.config/openclaw $HOME/.cache/openclaw"
[ "$SISAKAN_HM" = 0 ]       && CEK_PATH="$CEK_PATH $HOME/.hermes $HOME/.config/hermes $HOME/.cache/hermes $HOME/.local/share/uv"
[ "$SISAKAN_AGENLAIN" = 0 ] && CEK_PATH="$CEK_PATH $HOME/.codex $HOME/.cua-driver $HOME/.agent-browser"
[ "$GURU" = 1 ]             && CEK_PATH="$CEK_PATH $HOME/.torang-guru $HOME/torang-office"
[ "$SISAKAN_OC" = 0 ] && [ "$SISAKAN_HM" = 0 ] && CEK_PATH="$CEK_PATH $HOME/.npm-global"

TERSISA=""
for p in $CEK_PATH; do [ -e "$p" ] && TERSISA="$TERSISA $p"; done
if [ "$SISAKAN_HM" = 0 ]; then
  for L in "$HOME/.local/bin"/hermes*; do
    { [ -e "$L" ] || [ -L "$L" ]; } && TERSISA="$TERSISA $L"
  done
fi

PROSES=""
POLA_CEK=""
[ "$SISAKAN_TORANG" = 0 ] && POLA_CEK="$POLA_CEK monitor-client\.js \.torang/start\.sh"
[ "$SISAKAN_OC" = 0 ]     && POLA_CEK="$POLA_CEK openclaw"
[ "$SISAKAN_HM" = 0 ]     && POLA_CEK="$POLA_CEK hermes"
for pola in $POLA_CEK; do
  for pid in $(pgrep -f -- "$pola" 2>/dev/null || true); do
    bukan_diri_sendiri "$pid" || continue
    CMDX="$(cmd_of "$pid")"
    [ -n "$CMDX" ] || continue                              # lenyap: race pgrep->baca
    printf '%s' "$CMDX" | grep -qE -- "$pola" || continue   # sudah exec jadi hal lain
    case " $PROSES " in *" $pid "*) continue ;; esac
    PROSES="$PROSES $pid"
  done
done

# `command -v -a` BUKAN opsi valid; untuk mendaftar semua biner senama pakai
# `type -aP` -- bug lama yang membuat cek "biner masih di PATH" lolos palsu.
BINER=""
[ "$SISAKAN_OC" = 0 ] && { B="$(type -aP openclaw 2>/dev/null | tr '\n' ' ')"; [ -n "$B" ] && BINER="$BINER openclaw:($B)"; }
[ "$SISAKAN_HM" = 0 ] && { B="$(type -aP hermes 2>/dev/null | tr '\n' ' ')"; [ -n "$B" ] && BINER="$BINER hermes:($B)"; }

RC_SISA=""
if [ "$SISAKAN_TORANG" = 0 ]; then
  for f in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshrc"; do
    [ -f "$f" ] && grep -qE "$RE_TORANG_RC" "$f" 2>/dev/null && RC_SISA="$RC_SISA $f"
  done
fi

UNIT_SISA=""
if ada_perintah systemctl && systemctl --user show >/dev/null 2>&1; then
  UNIT_SISA="$(systemctl --user list-unit-files --no-legend --plain 2>/dev/null | awk '{print $1}' \
              | grep -Ei "$KOMP_RE" | tr '\n' ' ' || true)"
fi
UNIT_FILE_SISA=""
if [ -d "$HOME/.config/systemd/user" ]; then
  UNIT_FILE_SISA="$(ls -1 "$HOME/.config/systemd/user" 2>/dev/null | grep -Ei "$KOMP_RE" | tr '\n' ' ' || true)"
fi
UNIT_SIS_SISA="$(ls -1 /etc/systemd/system 2>/dev/null | grep -Ei "$KOMP_RE" | tr '\n' ' ' || true)"

PORT_SISA=""
[ "$SISAKAN_OC" = 0 ] && port_terpakai "$OC_PORT" && PORT_SISA="$OC_PORT"

if [ "$KERING" = 1 ]; then
  say ""
  say "Mode dry-run selesai -- TIDAK ADA yang dihapus."
  say "Tinjau rencana di atas, lalu jalankan tanpa --dry-run (atau lewat agen: -y setelah konfirmasi)."
  say "Log: $LOG"
  exit 0
fi

[ -n "$TERSISA" ]        && { say "MASIH ADA folder/file     :$TERSISA"; SISA=1; }
[ -n "$PROSES" ]         && { say "MASIH ADA proses hidup    :$PROSES"; SISA=1; }
[ -n "$BINER" ]          && { say "MASIH ADA biner di PATH   :$BINER"; SISA=1; }
if [ -n "$BINER" ] && printf '%s' "$BINER" | grep -q '/mnt/'; then
  say "  -> biner di /mnt/* = instalasi sisi WINDOWS; sudo TIDAK membantu."
  say "     Dari WSL: cmd.exe /c \"npm rm -g openclaw\"  atau di PowerShell Windows: npm rm -g openclaw"
fi
[ -n "$RC_SISA" ]        && { say "MASIH ADA auto-start di   :$RC_SISA"; SISA=1; }
[ -n "$UNIT_SISA" ]      && { say "MASIH ADA unit systemd    : $UNIT_SISA"; SISA=1; }
[ -n "$UNIT_FILE_SISA" ] && { say "MASIH ADA file unit user  : $UNIT_FILE_SISA"; SISA=1; }
[ -n "$UNIT_SIS_SISA" ]  && { say "MASIH ADA unit sistem     : $UNIT_SIS_SISA (butuh --sudo)"; SISA=1; }
[ -n "$PORT_SISA" ]      && { say "MASIH ADA yang mendengar di port $PORT_SISA (gateway?)"; SISA=1; }

say ""
if [ "$SISA" = 0 ]; then
  say "======================================================"
  say "  BERSIH. Komponen terpilih sudah tercabut."
  say "  which openclaw : $(command -v openclaw 2>/dev/null || echo '(kosong)')"
  say "  Tutup semua jendela terminal lalu buka lagi agar PATH"
  say "  kembali normal (WSL: wsl --shutdown dari Windows)."
  say "======================================================"
  say ""
  say "  YANG TIDAK BISA DIBERSIHKAN DARI SINI -- kerjakan manual:"
  say "  1. Bot Telegram murid masih HIDUP di server Telegram."
  say "     BotFather -> /deletebot -> pilih botnya."
  say "  2. API key OpenAI kelas: cabut/rotate dari dasbor OpenAI."
  say "  3. Pairing lama sisi guru: torang-sapu-agent.sh atau hapus"
  say "     ~/torang-office/agents-state.json"
  say "======================================================"
  say "Log: $LOG"
  exit 0
else
  say "======================================================"
  say "  BELUM SEPENUHNYA BERSIH -- lihat baris 'MASIH ADA' di atas."
  say "  Biasanya karena butuh root: ulangi dengan --sudo."
  say "======================================================"
  say "Log: $LOG"
  exit 2
fi
