#!/usr/bin/env bash
# =====================================================================
#  OPENCLAW-CLEANUP -- VERIFIKASI KEBERSIHAN  v1.2
#  (turunan torang-cek-siap-pasang.sh v1.0 yang sudah teruji di kelas)
#
#  Memeriksa apakah sistem BENAR-BENAR bersih dari OpenClaw, Hermes, dan
#  Torang Event: proses, unit systemd (user & sistem), biner di PATH,
#  paket (npm/pnpm/bun/pipx/pip), direktori config/cache/log, port
#  gateway, autostart/cron/rc, dan docker.
#
#  Skrip ini TIDAK MENGUBAH APA PUN. Hanya memeriksa dan melapor.
#  Aman dijalankan kapan saja, tanpa konfirmasi.
#
#  Pakai  : bash oc-verify.sh
#  Keluar : 0 = bersih  |  2 = tidak bersih (ada temuan)
# =====================================================================
set -uo pipefail

VERSI="1.2"
SELF_PAT='oc-uninstall|oc-verify|oc-reset|openclaw-cleanup|torang-bersih|cek-siap-pasang'
OC_STATE="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
OC_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
GURU_PORT="${TORANG_PORT:-19000}"
KOMP_RE='openclaw|hermes|torang'
GAGAL=0; INGAT=0

ok()   { printf '  \033[32m OK   \033[0m %s\n' "$1"; }
bad()  { printf '  \033[31mKOTOR \033[0m %s\n' "$1"; GAGAL=$((GAGAL+1)); }
warn() { printf '  \033[33m  ?   \033[0m %s\n' "$1"; INGAT=$((INGAT+1)); }
obat() { printf '         -> %s\n' "$1"; }

ada() { command -v "$1" >/dev/null 2>&1; }

case "${1:-}" in
  --bantuan|-h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

# rantai leluhur (jangan laporkan shell pemanggil sebagai "proses openclaw")
LELUHUR=" "
_p=$$
while [ -n "$_p" ] && [ "$_p" != "0" ] && [ "$_p" != "1" ]; do
  LELUHUR="$LELUHUR$_p "
  _p="$(awk '/^PPid:/{print $2}' "/proc/$_p/status" 2>/dev/null)"
done
# Baca cmdline sebuah pid. 2>/dev/null SEBELUM < : kalau proses sudah lenyap,
# kegagalan redirect stdin ikut terbungkam.
cmd_of() { tr '\0' ' ' 2>/dev/null < "/proc/$1/cmdline" || true; }

bukan_diri_sendiri() {
  case "$LELUHUR" in *" $1 "*) return 1 ;; esac
  local cmd; cmd="$(cmd_of "$1")"
  printf '%s' "$cmd" | grep -Eq "$SELF_PAT" && return 1
  return 0
}

# Port dibaca dari /proc/net/tcp yang SELALU ada -- ss/lsof/fuser belum tentu
# terpasang di WSL polos, dan kalau deteksi diam-diam gagal, laporan "port
# bebas" itu palsu.
port_terpakai() {
  local port="$1" hex; hex="$(printf '%04X' "$port")"
  awk -v h=":$hex" '$4=="0A" && $2 ~ h"$"{f=1} END{exit !f}' /proc/net/tcp  2>/dev/null && return 0
  awk -v h=":$hex" '$4=="0A" && $2 ~ h"$"{f=1} END{exit !f}' /proc/net/tcp6 2>/dev/null && return 0
  return 1
}
pid_port() {
  local port="$1" pids="" inode p
  ada ss    && pids="$(ss -ltnpH "sport = :$port" 2>/dev/null | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u)"
  [ -z "$pids" ] && ada lsof  && pids="$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | sort -u)"
  [ -z "$pids" ] && ada fuser && pids="$(fuser -n tcp "$port" 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' | sort -u)"
  if [ -z "$pids" ]; then
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
cmd_pid() { cmd_of "$1" | cut -c1-70; }

echo ""
echo "=== OPENCLAW-CLEANUP -- VERIFIKASI KEBERSIHAN v$VERSI ==="
echo "user: $(id -un)   host: $(hostname 2>/dev/null || echo '?')   $(date '+%Y-%m-%d %H:%M')"
echo ""

# ---------------------------------------------------------------- 1
echo "[1] Proses yang masih hidup"
HIDUP=""
for pola in "monitor-client\.js" "openclaw" "hermes" "\.torang/start\.sh" "\.torang-guru/start\.sh"; do
  for pid in $(pgrep -f -- "$pola" 2>/dev/null || true); do
    bukan_diri_sendiri "$pid" || continue
    CMDX="$(cmd_of "$pid")"
    [ -n "$CMDX" ] || continue                              # lenyap: race pgrep->baca
    printf '%s' "$CMDX" | grep -qE -- "$pola" || continue   # sudah exec jadi hal lain
    case " $HIDUP " in *" $pid "*) continue ;; esac
    HIDUP="$HIDUP $pid"
  done
done
if [ -n "$HIDUP" ]; then
  bad "masih ada proses hidup:$HIDUP"
  for p in $HIDUP; do obat "pid $p = $(cmd_pid "$p")"; done
else
  ok "tidak ada proses openclaw/hermes/torang/monitor yang hidup"
fi

# ---------------------------------------------------------------- 2
echo ""
echo "[2] Unit systemd USER"
if ada systemctl && systemctl --user show >/dev/null 2>&1; then
  U="$(systemctl --user list-unit-files --no-legend --plain 2>/dev/null | awk '{print $1}' \
      | grep -Ei "$KOMP_RE" | tr '\n' ' ')"
  if [ -n "$U" ]; then
    bad "unit systemd user masih terdaftar: $U"
    obat "systemctl --user disable --now <unit> && rm ~/.config/systemd/user/<unit>"
  else
    ok "tidak ada unit systemd user openclaw/hermes/torang"
  fi
else
  warn "systemd --user tidak aktif (wajar di WSL) -- cek file unit langsung"
fi
SISA_UNIT=""
if [ -d "$HOME/.config/systemd/user" ]; then
  SISA_UNIT="$(ls -1 "$HOME/.config/systemd/user" 2>/dev/null | grep -Ei "$KOMP_RE" | tr '\n' ' ' || true)"
fi
if [ -n "$SISA_UNIT" ]; then
  bad "file unit user masih ada: $SISA_UNIT"
  obat "rm ~/.config/systemd/user/<nama>"
else
  ok "tidak ada file unit tertinggal di ~/.config/systemd/user"
fi

# ---------------------------------------------------------------- 3
echo ""
echo "[3] Unit systemd SISTEM"
SIS="$(ls -1 /etc/systemd/system 2>/dev/null | grep -Ei "$KOMP_RE" | tr '\n' ' ' || true)"
if [ -n "$SIS" ]; then
  bad "unit tingkat sistem masih ada: $SIS"
  obat "sudo systemctl disable --now <unit> && sudo rm /etc/systemd/system/<unit>"
else
  ok "tidak ada unit openclaw/hermes/torang di /etc/systemd/system"
fi
if ada systemctl && systemctl list-unit-files >/dev/null 2>&1; then
  SIS2="$(systemctl list-unit-files --no-legend --plain 2>/dev/null | awk '{print $1}' \
         | grep -Ei "$KOMP_RE" | tr '\n' ' ' || true)"
  if [ -n "$SIS2" ]; then
    bad "systemd sistem masih mendaftar: $SIS2"
    obat "sudo systemctl disable --now <unit> ; sudo systemctl daemon-reload ; sudo systemctl reset-failed"
  fi
fi

# ---------------------------------------------------------------- 4
echo ""
echo "[4] Biner di PATH & paket terdaftar"
# `command -v -a` BUKAN opsi valid -- pakai `type -aP` untuk SEMUA biner senama.
for b in openclaw hermes; do
  BINER="$(type -aP "$b" 2>/dev/null | tr '\n' ' ')"
  if [ -n "$BINER" ]; then
    bad "biner $b masih di PATH: $BINER"
    if printf '%s' "$BINER" | grep -q '/mnt/'; then
      obat "path /mnt/* = instalasi sisi WINDOWS (npm Windows); sudo tidak membantu"
      obat "dari WSL: cmd.exe /c \"npm rm -g $b\"   atau di PowerShell Windows: npm rm -g $b"
    else
      obat "hapus lalu buka ulang terminal (atau: hash -r)"
    fi
  else
    ok "which $b : (kosong)"
  fi
done
for PM in npm pnpm bun; do
  ada "$PM" || continue
  case "$PM" in
    npm)  L="$($PM ls -g --depth=0 2>/dev/null)" ;;
    pnpm) L="$($PM list -g --depth=0 2>/dev/null)" ;;
    bun)  L="$($PM pm ls -g 2>/dev/null)" ;;
  esac
  if printf '%s' "$L" | grep -qiE "$KOMP_RE"; then
    bad "paket global tersangkut di $PM: $(printf '%s' "$L" | grep -iE "$KOMP_RE" | head -3 | tr '\n' ' ')"
    obat "$PM rm -g <paket>   (pnpm/bun: remove -g)"
  else
    ok "tidak ada paket openclaw/hermes/torang di $PM global"
  fi
done
if ada pipx; then
  PX="$(pipx list --short 2>/dev/null | awk '{print $1}' | grep -iE "$KOMP_RE" | tr '\n' ' ' || true)"
  if [ -n "$PX" ]; then bad "paket pipx tersangkut: $PX"; obat "pipx uninstall <paket>"
  else ok "tidak ada paket pipx yang cocok"; fi
fi
PIP_BIN="$(command -v pip3 2>/dev/null || command -v pip 2>/dev/null || true)"
if [ -n "$PIP_BIN" ]; then
  PPK="$("$PIP_BIN" list --format=freeze 2>/dev/null | cut -d= -f1 | grep -iE "^(openclaw|hermes|torang)" | tr '\n' ' ' || true)"
  if [ -n "$PPK" ]; then bad "paket pip tersangkut: $PPK"; obat "$PIP_BIN uninstall -y <paket>"
  else ok "tidak ada paket pip yang cocok"; fi
fi

# ---------------------------------------------------------------- 5
echo ""
echo "[5] Direktori config / cache / log / state"
KOTOR_D=""
for d in "$OC_STATE" "$HOME/.openclaw" "$HOME/.config/openclaw" "$HOME/.cache/openclaw" \
         "$HOME/.local/share/openclaw" "$HOME/.local/state/openclaw" \
         "$HOME/.hermes" "$HOME/.config/hermes" "$HOME/.cache/hermes" \
         "$HOME/.local/share/hermes" "$HOME/.local/state/hermes" \
         "$HOME/.torang" "$HOME/.torang-plugin" "$HOME/.torang-monitor" \
         "$HOME/.torang-guru" "$HOME/torang-office" "$HOME/.torang-events.env" \
         "$HOME/torang-events.log" "$HOME/.torang-events.log" \
         "$HOME/.torang-events-state.json" \
         "$HOME/.config/torang" "$HOME/.cache/torang" "$HOME/.local/share/torang" \
         "$HOME/.codex" "$HOME/.cua-driver" "$HOME/.agent-browser" \
         "$HOME/.local/share/uv" "$HOME/.npm-global"; do
  [ -e "$d" ] || continue
  case " $KOTOR_D " in *" $d "*) continue ;; esac
  KOTOR_D="$KOTOR_D $d"
done
if [ -n "$KOTOR_D" ]; then
  for d in $KOTOR_D; do
    case "$d" in
      "$HOME/.torang-guru"|"$HOME/torang-office")
        bad "sisa (sisi GURU): $d"; obat "uninstall tanpa --guru memang menyisakan ini; pakai --guru untuk mencabutnya" ;;
      *) bad "sisa: $d" ;;
    esac
  done
  obat "jalankan /uninstall (skrip oc-uninstall.sh) untuk menyapunya"
else
  ok "tidak ada direktori sisa di HOME"
fi
for d in /etc/openclaw /etc/hermes /etc/torang; do
  [ -e "$d" ] && { bad "sisa di /etc: $d"; obat "sudo rm -rf $d"; }
done
VLOG="$(ls -1d /var/log/openclaw* /var/log/hermes* /var/log/torang* 2>/dev/null | tr '\n' ' ' || true)"
[ -n "$VLOG" ] && { bad "log sistem tersisa: $VLOG"; obat "sudo rm -rf <path>"; }
LS_LOG="$(ls -1d "$HOME/.local/share"/*openclaw* "$HOME/.local/share"/*hermes* "$HOME/.local/share"/*torang* 2>/dev/null | tr '\n' ' ' || true)"
[ -n "$LS_LOG" ] && bad "sisa di ~/.local/share: $LS_LOG"
if [ -f "$HOME/.npmrc" ] && grep -qi 'hermes' "$HOME/.npmrc" 2>/dev/null; then
  bad "~/.npmrc masih mengarahkan prefix npm ke Hermes"
  obat "sunting/hapus baris prefix di ~/.npmrc"
fi
HB=""
for L in "$HOME/.local/bin"/hermes* "$HOME/.local/bin/cua-driver" "$HOME/.local/bin/agent-browser"; do
  { [ -e "$L" ] || [ -L "$L" ]; } && HB="$HB $(basename "$L")"
done
if [ -n "$HB" ]; then
  bad "biner agen tersisa di ~/.local/bin:$HB"
  obat "jalankan /uninstall terbaru (oc-uninstall.sh) untuk menyapunya"
fi
if [ -d "$HOME/.local/bin" ]; then
  for L in "$HOME/.local/bin"/*; do
    if [ -L "$L" ] && [ ! -e "$L" ]; then
      bad "symlink menggantung: $L (target sudah tiada)"
      obat "rm $L  -- kalau dibiarkan, installer berikutnya gagal di tengah jalan"
    fi
  done
fi
for f in "$HOME/.bashrc.torang-bak" "$HOME/.profile.torang-bak" "$HOME/.npmrc.torang-bak"; do
  [ -e "$f" ] && { bad "cadangan sisa versi lama: $f"; obat "jalankan /uninstall terbaru -- versi kini menyapu ini otomatis"; }
done
if [ -f "$HOME/.npmrc" ] && grep -q 'npm-global' "$HOME/.npmrc" 2>/dev/null; then
  bad "~/.npmrc masih memuat prefix npm-global (residu toolchain kelas)"
fi
BK="$(ls -1d "$HOME"/openclaw-backup-* 2>/dev/null | tr '\n' ' ' || true)"
[ -n "$BK" ] && warn "ada folder backup (bukan temuan kotor, hanya info): $BK"

# ---------------------------------------------------------------- 6
echo ""
echo "[6] Port gateway"
PP="$(pid_port "$OC_PORT")"
if port_terpakai "$OC_PORT" || [ -n "$PP" ]; then
  bad "port gateway $OC_PORT masih dipegang pid:${PP:-?}"
  for p in $PP; do obat "pid $p = $(cmd_pid "$p")"; done
  [ -z "$PP" ] && obat "pid tak terbaca (pasang iproute2/lsof), tapi port JELAS terpakai"
  obat "ini yang bikin gateway baru 'active' tapi dashboard tak bisa dibuka"
else
  ok "port gateway $OC_PORT bebas"
fi
GP="$(pid_port "$GURU_PORT")"
if port_terpakai "$GURU_PORT" || [ -n "$GP" ]; then
  CMDG=""
  for p in $GP; do CMDG="$(cmd_pid "$p")"; break; done
  if printf '%s' "$CMDG" | grep -qiE 'torang|backend/app\.py|flask'; then
    bad "port office guru $GURU_PORT masih dipegang pid:$GP ($CMDG)"
  else
    warn "port $GURU_PORT dipakai proses lain (bukan torang): ${CMDG:-pid $GP}"
  fi
else
  ok "port office guru $GURU_PORT bebas"
fi

# ---------------------------------------------------------------- 7
echo ""
echo "[7] Autostart, cron, dan file rc"
RC_K=""
for f in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshrc"; do
  [ -f "$f" ] && grep -qE '\.torang(-guru)?/start\.sh' "$f" 2>/dev/null && RC_K="$RC_K $f"
done
if [ -n "$RC_K" ]; then bad "auto-start Torang masih tertanam di:$RC_K"
else ok "tidak ada auto-start Torang di file rc"; fi
if ada crontab && crontab -l 2>/dev/null | grep -qEi "$KOMP_RE"; then
  bad "crontab masih memuat baris terkait:"
  crontab -l 2>/dev/null | grep -Ei "$KOMP_RE" | sed 's/^/         /'
else
  ok "crontab bersih"
fi
AUTO=""
if [ -d "$HOME/.config/autostart" ]; then
  for f in "$HOME/.config/autostart"/*.desktop; do
    [ -e "$f" ] || continue
    if basename "$f" | grep -qiE "$KOMP_RE" || grep -qiE "$KOMP_RE" "$f" 2>/dev/null; then
      AUTO="$AUTO $(basename "$f")"
    fi
  done
fi
if [ -n "$AUTO" ]; then bad "entry autostart desktop:$AUTO"; obat "rm ~/.config/autostart/<nama>.desktop"
else ok "tidak ada entry autostart desktop"; fi
if [ -f /etc/wsl.conf ] && grep -qEi "$KOMP_RE" /etc/wsl.conf 2>/dev/null; then
  bad "/etc/wsl.conf masih memuat baris terkait (sunting manual, root)"
fi

# ---------------------------------------------------------------- 8
echo ""
echo "[8] Docker"
if ada docker; then
  DC="$(docker ps -a --format '{{.Names}} ({{.Image}})' 2>/dev/null | grep -iE "$KOMP_RE" | tr '\n' ' ' || true)"
  DI="$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -iE "$KOMP_RE" | tr '\n' ' ' || true)"
  DV="$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -iE "$KOMP_RE" | tr '\n' ' ' || true)"
  [ -n "$DC" ] && { bad "container docker: $DC"; obat "docker rm -f <nama>"; }
  [ -n "$DI" ] && { bad "image docker: $DI"; obat "docker rmi <image>"; }
  [ -n "$DV" ] && { bad "volume docker: $DV"; obat "docker volume rm <nama>"; }
  [ -z "$DC$DI$DV" ] && ok "tidak ada container/image/volume docker yang cocok"
else
  ok "docker tidak terpasang -- tidak ada yang perlu dicek"
fi

# ---------------------------------------------------------------- hasil
echo ""
if [ "$GAGAL" -eq 0 ]; then
  echo "======================================================"
  echo "  BERSIH. Tidak ada jejak OpenClaw/Hermes/Torang Event."
  [ "$INGAT" -gt 0 ] && echo "  ($INGAT catatan bertanda ? -- baca sekilas, bukan penghalang)"
  echo "======================================================"
  exit 0
else
  echo "======================================================"
  echo "  TIDAK BERSIH -- $GAGAL temuan."
  echo "  Memasang di atas sisa lama = gateway error / token tak"
  echo "  ke-generate / dashboard tak mau terbuka."
  echo ""
  echo "  Bersihkan dengan /uninstall (oc-uninstall.sh), lalu"
  echo "  tutup terminal, buka lagi, dan ulangi verifikasi ini."
  echo "======================================================"
  exit 2
fi
