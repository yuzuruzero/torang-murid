#!/usr/bin/env bash
# =====================================================================
#  TORANG -- VERIFIKASI PEMASANGAN OpenClaw + Hermes  v1.0
#
#  Kembarannya oc-verify.sh: yang itu memeriksa apakah sistem BERSIH,
#  yang ini memeriksa apakah sistem TERPASANG dengan benar.
#
#  Skrip ini TIDAK MENGUBAH APA PUN. Hanya memeriksa dan melapor.
#  Aman dijalankan kapan saja, tanpa konfirmasi.
#
#  PAKAI:
#    bash verifikasi.sh                  laporan lengkap (9 kelompok)
#    bash verifikasi.sh --potret         ringkas -- dipakai pasang-inti.sh
#    bash verifikasi.sh --openclaw-saja  hanya kelompok OpenClaw
#    bash verifikasi.sh --dengan-torang  ikut periksa monitor Torang
#
#  KELUAR: 0 = lengkap  |  2 = ada yang kurang
#
#  CATATAN PENTING TENTANG "KURANG":
#  Sebelum `openclaw onboard` dan `hermes setup` dijalankan, wajar kalau
#  gateway belum hidup dan port 18789 masih bebas. Itu dilaporkan sebagai
#  CATATAN, bukan GAGAL.
# =====================================================================
set -uo pipefail

VERSI="1.0"
OC_STATE="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
OC_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"

MODE="penuh"
DENGAN_TORANG=0
for a in "$@"; do
  case "$a" in
    --potret)         MODE="potret" ;;
    --openclaw-saja)  MODE="openclaw" ;;
    --dengan-torang)  DENGAN_TORANG=1 ;;
    --bantuan|-h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Pilihan tak dikenal: $a  (pakai --bantuan)"; exit 1 ;;
  esac
done

GAGAL=0; CATATAN=0

ok()   { [ "$MODE" = "potret" ] || printf '  \033[32m OK   \033[0m %s\n' "$1"; }
bad()  { printf '  \033[31mKURANG\033[0m %s\n' "$1"; GAGAL=$((GAGAL+1)); }
info() { [ "$MODE" = "potret" ] || printf '  \033[33m  i   \033[0m %s\n' "$1"; CATATAN=$((CATATAN+1)); }
obat() { [ "$MODE" = "potret" ] || printf '         -> %s\n' "$1"; }
judul(){ [ "$MODE" = "potret" ] || { echo ""; echo "$1"; }; }

ada() { command -v "$1" >/dev/null 2>&1; }

# `timeout` tidak ada di macOS bawaan.
batas_waktu() {
  local detik="$1"; shift
  if ada timeout; then timeout "$detik" "$@"; else "$@"; fi
}

LINGKUNGAN="linux"
case "$(uname -s 2>/dev/null || echo '?')" in
  Darwin) LINGKUNGAN="mac" ;;
  Linux)  grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null && LINGKUNGAN="wsl" ;;
esac

# Port dibaca dari /proc/net/tcp yang SELALU ada di Linux -- ss/lsof/fuser
# belum tentu terpasang di WSL polos, dan kalau deteksi diam-diam gagal,
# laporan "port bebas" itu palsu.
port_terpakai() {
  local port="$1" hex
  hex="$(printf '%04X' "$port")"
  if [ -r /proc/net/tcp ]; then
    awk -v h=":$hex" '$4=="0A" && $2 ~ h"$"{f=1} END{exit !f}' /proc/net/tcp  2>/dev/null && return 0
    awk -v h=":$hex" '$4=="0A" && $2 ~ h"$"{f=1} END{exit !f}' /proc/net/tcp6 2>/dev/null && return 0
    return 1
  fi
  # Mac: tidak ada /proc, pakai lsof kalau ada
  if ada lsof; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 && return 0
  fi
  return 1
}

if [ "$MODE" != "potret" ]; then
  echo ""
  echo "=== TORANG -- VERIFIKASI PEMASANGAN v$VERSI ==="
  echo "user: $(id -un)   lingkungan: $LINGKUNGAN   $(date '+%Y-%m-%d %H:%M')"
fi

# ---------------------------------------------------------------- 1
judul "[1] Biner dan PATH"
for b in openclaw hermes; do
  [ "$MODE" = "openclaw" ] && [ "$b" = "hermes" ] && continue
  # `command -v -a` BUKAN opsi yang sah. `type -aP` mendaftar SEMUA biner
  # senama di PATH -- itu yang kita butuhkan untuk melihat bentrokan.
  BINER="$(type -aP "$b" 2>/dev/null | tr '\n' ' ')"
  if [ -z "$BINER" ]; then
    bad "'$b' tidak ada di PATH"
    obat "Kalau installer bilang sukses, ini hampir selalu soal PATH."
    obat "Coba buka terminal baru, atau: source ~/.bashrc"
  else
    ok "$b: $BINER"
    if printf '%s' "$BINER" | grep -q '/mnt/'; then
      bad "'$b' ini berasal dari sisi WINDOWS (path /mnt/...)"
      obat "PATH di WSL mewarisi PATH Windows, jadi yang menang bisa saja"
      obat "instalasi Windows -- bukan yang kita pasang di Ubuntu."
      obat "Cabut dari WSL: cmd.exe /c \"npm rm -g $b\"   (sudo tidak membantu)"
    fi
  fi
done

# ---------------------------------------------------------------- 2
judul "[2] Versi terpasang"
if ada openclaw; then
  V_OC="$(batas_waktu 120 openclaw --version 2>/dev/null | head -1 | tr -d '\r')"
  if [ -n "${V_OC:-}" ]; then ok "openclaw: $V_OC"
  else bad "'openclaw --version' tidak mengeluarkan apa pun"
       obat "Biner ada tapi tidak jalan -- biasanya Node tidak cocok."; fi
fi
if [ "$MODE" != "openclaw" ] && ada hermes; then
  V_HM="$(batas_waktu 120 hermes version 2>/dev/null | head -3 | tr -d '\r' | tr '\n' ' ')"
  if [ -n "${V_HM:-}" ]; then ok "hermes: $V_HM"
  else info "'hermes version' tidak mengeluarkan apa pun -- coba terminal baru"; fi
fi
if [ -f "$(dirname "$0")/VERSI-TERUJI.md" ]; then
  obat "Bandingkan sendiri dengan VERSI-TERUJI.md. Versi berbeda BUKAN"
  obat "kegagalan -- hanya perlu dicatat saat melapor kalau ada masalah."
fi

# ---------------------------------------------------------------- 3
judul "[3] Node.js"
if ada node; then
  V_NODE="$(node -v 2>/dev/null | tr -d 'v\r')"
  MAY="${V_NODE%%.*}"
  case "$MAY" in
    ''|*[!0-9]*) info "versi Node tidak terbaca: $V_NODE" ;;
    23) bad "Node 23 tidak didukung OpenClaw"
        obat "Yang didukung: 22.22.3+, 24.15+, atau 25.9+ (26 disarankan)."
        obat "Ganti versi Node, lalu pasang ulang OpenClaw." ;;
    22) ok "node v$V_NODE  ($(type -aP node 2>/dev/null | head -1))"
        obat "Jalur 22 didukung mulai 22.22.3 -- pastikan versimu tidak di bawah itu." ;;
    *)  if [ "$MAY" -ge 24 ]; then
          ok "node v$V_NODE  ($(type -aP node 2>/dev/null | head -1))"
          [ "$MAY" -eq 24 ] && obat "Jalur 24 didukung mulai 24.15."
          [ "$MAY" -eq 25 ] && obat "Jalur 25 didukung mulai 25.9."
        else
          bad "Node v$V_NODE terlalu tua untuk OpenClaw"
          obat "Butuh 22.22.3+, 24.15+, atau 25.9+ (26 disarankan)."
        fi ;;
  esac
  # Node mana yang menang di PATH itu penting: kalau yang menang milik
  # Hermes, OpenClaw ikut memakainya.
  NODE_SEMUA="$(type -aP node 2>/dev/null | tr '\n' ' ')"
  case "$NODE_SEMUA" in
    *".hermes"*) info "node yang menang di PATH milik Hermes ($HOME/.hermes/node)"
                 obat "Wajar. Jadi masalah hanya kalau OpenClaw ikut rusak." ;;
  esac
else
  bad "'node' tidak ada di PATH"
  obat "Installer resmi seharusnya memasangnya. Coba terminal baru dulu."
fi

# ---------------------------------------------------------------- 4
judul "[4] Berkas konfigurasi"
if [ -f "$OC_STATE/openclaw.json" ]; then
  ok "ada $OC_STATE/openclaw.json"
  if ada node; then
    if node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$OC_STATE/openclaw.json" >/dev/null 2>&1; then
      ok "openclaw.json bisa dibaca (JSON valid)"
    else
      bad "openclaw.json ADA tapi isinya rusak (bukan JSON yang sah)"
      obat "Ini bikin gateway gagal dengan pesan yang membingungkan."
      obat "Perbaiki isinya, atau jalankan onboarding ulang."
    fi
  fi
else
  info "belum ada $OC_STATE/openclaw.json"
  obat "Wajar kalau 'openclaw onboard' belum dijalankan."
fi

if [ "$MODE" != "openclaw" ]; then
  [ -f "$HOME/.hermes/config.yaml" ] && ok "ada ~/.hermes/config.yaml" \
    || info "belum ada ~/.hermes/config.yaml (wajar sebelum 'hermes setup')"
  [ -f "$HOME/.hermes/.env" ] && ok "ada ~/.hermes/.env" \
    || info "belum ada ~/.hermes/.env (tempat kunci API disimpan)"
  [ -d "$HOME/.hermes/hermes-agent" ] && ok "kode Hermes ada di ~/.hermes/hermes-agent" \
    || bad "~/.hermes/hermes-agent tidak ada -- Hermes belum terpasang utuh"
fi

# ---------------------------------------------------------------- 5
judul "[5] Layanan gateway"
if [ "$LINGKUNGAN" = "mac" ]; then
  if [ -f "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist" ]; then
    ok "LaunchAgent ai.openclaw.gateway terpasang"
  else
    info "LaunchAgent OpenClaw belum ada"
    obat "Dibuat saat 'openclaw onboard --install-daemon' atau"
    obat "'openclaw gateway install'."
  fi
else
  UNIT="$HOME/.config/systemd/user/openclaw-gateway.service"
  if [ -f "$UNIT" ]; then
    ok "unit systemd user openclaw-gateway.service terpasang"
  else
    LAIN="$(ls -1 "$HOME/.config/systemd/user" 2>/dev/null | grep -i openclaw | tr '\n' ' ' || true)"
    if [ -n "${LAIN:-}" ]; then ok "unit gateway terpasang dengan nama profil: $LAIN"
    else info "unit gateway OpenClaw belum ada"
         obat "Dibuat saat 'openclaw onboard --install-daemon'."; fi
  fi
  if ada systemctl && systemctl --user show >/dev/null 2>&1; then
    ok "systemd --user aktif"
  else
    if [ "$LINGKUNGAN" = "wsl" ]; then
      info "systemd --user tidak aktif (wajar di WSL polos)"
    else
      info "systemd --user tidak aktif di sesi ini"
      obat "Di VPS: gateway baru hidup sendiri setelah"
      obat "        sudo loginctl enable-linger $(id -un)"
    fi
    obat "Gateway tetap bisa dijalankan manual: openclaw gateway start"
  fi
fi

# ---------------------------------------------------------------- 6
judul "[6] Port gateway ($OC_PORT)"
if port_terpakai "$OC_PORT"; then
  ok "ada yang mendengar di port $OC_PORT (gateway kemungkinan hidup)"
else
  info "port $OC_PORT masih bebas"
  obat "Wajar sebelum onboarding. Setelah gateway hidup, port ini terpakai."
fi
if [ "$LINGKUNGAN" = "wsl" ]; then
  obat "Di WSL, kalau gateway hidup tapi dashboard tak mau terbuka dari"
  obat "browser Windows, itu masalah PENERUSAN PORT -- bukan OpenClaw."
  obat "Uji pembeda, dari dalam WSL: curl -sI http://127.0.0.1:$OC_PORT"
fi

# ---------------------------------------------------------------- 7
judul "[7] Pemeriksa bawaan (doctor)"
if ada openclaw; then
  if batas_waktu 180 openclaw doctor >/dev/null 2>&1; then
    ok "openclaw doctor: tidak ada keluhan"
  else
    info "openclaw doctor melaporkan sesuatu"
    obat "Wajar bila belum onboarding. Lihat rinciannya: openclaw doctor"
  fi
fi
if [ "$MODE" != "openclaw" ] && ada hermes; then
  if batas_waktu 240 hermes doctor >/dev/null 2>&1; then
    ok "hermes doctor: tidak ada keluhan"
  else
    info "hermes doctor melaporkan sesuatu"
    obat "Wajar bila belum 'hermes setup'. Lihat rinciannya: hermes doctor"
  fi
fi

# ---------------------------------------------------------------- 8
judul "[8] Kewarasan setelah Hermes (npm, tautan, symlink)"
for t in node npm npx; do
  L="$HOME/.local/bin/$t"
  if [ -L "$L" ]; then
    # Symlink menggantung: readlink -f TETAP sukses kalau hanya komponen
    # terakhir target yang hilang. Deteksi yang benar: -L tapi tidak -e.
    if [ ! -e "$L" ]; then
      bad "symlink menggantung: $L (targetnya sudah tidak ada)"
      obat "Kalau dibiarkan, installer berikutnya bisa gagal di tengah jalan."
      obat "Hapus: rm $L"
    else
      ok "$L -> $(readlink "$L" 2>/dev/null)"
    fi
  elif [ -e "$L" ]; then
    ok "$L (berkas biasa, bukan tautan)"
  fi
done
if [ -f "$HOME/.npmrc" ]; then
  PREFIX="$(grep -i '^prefix' "$HOME/.npmrc" 2>/dev/null | head -1)"
  if [ -n "${PREFIX:-}" ]; then
    ok "~/.npmrc: $PREFIX"
    case "$PREFIX" in
      *hermes*) info "prefix npm global diarahkan ke Hermes"
                obat "Wajar setelah Hermes dipasang. Jadi masalah hanya kalau"
                obat "OpenClaw ikut tidak jalan -- cek kelompok [1] dan [2]." ;;
    esac
  else
    ok "~/.npmrc ada, tanpa baris prefix"
  fi
else
  ok "~/.npmrc tidak ada (wajar)"
fi
# symlink menggantung generik -- penyebab installer gagal di tengah jalan
if [ -d "$HOME/.local/bin" ]; then
  MENGGANTUNG=""
  for L in "$HOME/.local/bin"/*; do
    [ -L "$L" ] && [ ! -e "$L" ] && MENGGANTUNG="$MENGGANTUNG $(basename "$L")"
  done
  [ -n "$MENGGANTUNG" ] && { bad "symlink menggantung di ~/.local/bin:$MENGGANTUNG"; \
    obat "Hapus satu per satu dengan rm, lalu jalankan verifikasi ini lagi."; }
fi

# ---------------------------------------------------------------- 9
if [ "$DENGAN_TORANG" = 1 ]; then
  judul "[9] Monitor Torang (opsional)"
  [ -d "$HOME/.torang" ] && ok "ada ~/.torang" || info "~/.torang tidak ada"
  [ -f "$HOME/.torang-monitor/client_id" ] \
    && ok "client_id murid tersimpan (karakter tetap sama)" \
    || info "belum ada ~/.torang-monitor/client_id"
  [ -d "$HOME/.torang-plugin/torang-events" ] \
    && ok "plugin torang-events terpasang" \
    || info "plugin torang-events belum terpasang"
fi

# ---------------------------------------------------------------- hasil
if [ "$MODE" = "potret" ]; then
  [ "$GAGAL" -eq 0 ] && exit 0
  exit 2
fi

echo ""
if [ "$GAGAL" -eq 0 ]; then
  echo "======================================================"
  echo "  LENGKAP. OpenClaw dan Hermes terpasang dengan benar."
  [ "$CATATAN" -gt 0 ] && echo "  ($CATATAN catatan bertanda i -- baca sekilas, bukan penghalang)"
  echo "======================================================"
  exit 0
else
  echo "======================================================"
  echo "  ADA $GAGAL HAL YANG KURANG."
  echo ""
  echo "  Baca baris bertanda KURANG di atas -- tiap baris menyebut"
  echo "  apa yang kurang dan apa yang harus dilakukan."
  echo ""
  echo "  Kalau bingung, jalankan pemasangnya lagi. Aman diulang:"
  echo "  Windows -> PASANG.bat   ·   Mac -> bash pasang-mac.sh"
  echo "  Linux/VPS -> bash pasang-inti.sh"
  echo "======================================================"
  exit 2
fi
