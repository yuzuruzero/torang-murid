#!/usr/bin/env bash
# =====================================================================
#  TORANG - Pemasang OFFICE + MONITOR GURU (versi bash / curl|bash)
#  Jalankan di WSL PC GURU (setelah OpenClaw & folder office ada):
#
#    curl -fsSL https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/install-guru.sh | bash
#
#  Yang diurus otomatis:
#    1) .wslconfig (batasi RAM WSL biar Windows tak nge-hang)
#    2) launcher office (app.py) + monitor guru (peran teacher)
#    3) auto-start tiap buka WSL (.bashrc)
#    4) JARINGAN LAN (portproxy+firewall) via PowerShell admin (muncul UAC -> klik Yes)
#    5) scheduled task Windows: relink portproxy tiap 2 menit + nyalakan office saat PC login
#
#  Yang HARUS sudah ada di PC guru sebelum jalanin ini:
#    - WSL + OpenClaw terpasang (ada `node`, `python3`)
#    - Folder office (Star-Office-UI) sudah dicopy ke PC ini (installer cari otomatis)
#
#  Override lewat env (opsional):
#    TORANG_OFFICE_DIR=/mnt/d/.../Star-Office-UI   folder office (kalau tak ketemu otomatis)
#    TORANG_PORT=19000                              port office
#    TORANG_JOIN_KEY=ocj_test                       join key
#    TORANG_WSL_MEM=3GB / TORANG_WSL_CPU=2 / TORANG_WSL_SWAP=2GB   batas WSL
#    TORANG_NO_NET=1        lewati setup jaringan Windows (kalau mau atur sendiri)
#    TORANG_NO_BOOT=1       jangan pasang auto-start saat PC login
# =====================================================================
set -e

PORT="${TORANG_PORT:-19000}"
JOIN_KEY="${TORANG_JOIN_KEY:-ocj_test}"
WSL_MEM="${TORANG_WSL_MEM:-3GB}"
WSL_CPU="${TORANG_WSL_CPU:-2}"
WSL_SWAP="${TORANG_WSL_SWAP:-2GB}"
BASE_URL="${TORANG_BASE_URL:-https://raw.githubusercontent.com/yuzuruzero/torang-murid/main}"
GDIR="$HOME/.torang-guru"

say(){ echo "[Torang-Guru] $*"; }
die(){ echo "[Torang-Guru] GAGAL: $*" >&2; exit 1; }

# --- pastikan ini WSL (ada sisi Windows) ---------------------------------
[ -d /mnt/c ] || die "Ini tampaknya bukan WSL (tidak ada /mnt/c). Jalankan di WSL PC guru."

# --- cari nama user Windows (untuk .wslconfig) ---------------------------
WINUSER="$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r\n')"
WINPROFILE="/mnt/c/Users/$WINUSER"
if [ -z "$WINUSER" ] || [ ! -d "$WINPROFILE" ]; then
  # fallback: tebak dari folder Users yang punya file (bukan Public/Default)
  for d in /mnt/c/Users/*/; do
    b="$(basename "$d")"
    case "$b" in Public|Default|Default*|All*|desktop.ini) continue;; esac
    [ -d "$d/AppData" ] && { WINPROFILE="$d"; WINUSER="$b"; break; }
  done
fi
[ -d "$WINPROFILE" ] || die "Tak menemukan folder user Windows di /mnt/c/Users. Set manual nanti."
say "User Windows: $WINUSER  ->  $WINPROFILE"

# --- deteksi folder office (yang ada backend/app.py) ---------------------
find_office(){
  # 1) env
  if [ -n "$TORANG_OFFICE_DIR" ] && [ -f "$TORANG_OFFICE_DIR/backend/app.py" ]; then
    echo "$TORANG_OFFICE_DIR"; return 0
  fi
  # 2) lokasi umum
  for c in \
    /mnt/d/projects/torangapp/Star-Office-UI \
    /mnt/c/projects/torangapp/Star-Office-UI \
    "$HOME/torangapp/Star-Office-UI" \
    "$HOME/Star-Office-UI" ; do
    [ -f "$c/backend/app.py" ] && { echo "$c"; return 0; }
  done
  # 3) scan dangkal beberapa drive
  for base in /mnt/d /mnt/c /mnt/e /mnt/f; do
    [ -d "$base" ] || continue
    hit="$(find "$base" -maxdepth 5 -type f -path '*/backend/app.py' 2>/dev/null | head -1)"
    [ -n "$hit" ] && { echo "$(dirname "$(dirname "$hit")")"; return 0; }
  done
  return 1
}

say "Mencari folder office (ada backend/app.py)..."
OFFICE_DIR="$(find_office || true)"
[ -n "$OFFICE_DIR" ] || die "Folder office tak ketemu. Copy dulu folder Star-Office-UI ke PC ini, atau set TORANG_OFFICE_DIR=/mnt/.../Star-Office-UI lalu ulangi."
[ -f "$OFFICE_DIR/backend/app.py" ] || die "backend/app.py tak ada di $OFFICE_DIR"
say "Office: $OFFICE_DIR"

# --- siapkan folder guru -------------------------------------------------
mkdir -p "$GDIR"

# --- ambil monitor-client.js: utamakan lokal, kalau tak ada -> download --
MON_LOCAL=""
for c in \
  "$(dirname "$OFFICE_DIR")/star-office-tools/monitor-client.js" \
  "$OFFICE_DIR/../star-office-tools/monitor-client.js" \
  "$OFFICE_DIR/tools/monitor-client.js" \
  "$OFFICE_DIR/monitor-client.js" ; do
  [ -f "$c" ] && { MON_LOCAL="$c"; break; }
done
if [ -n "$MON_LOCAL" ]; then
  cp "$MON_LOCAL" "$GDIR/monitor-client.js"
  say "Monitor disalin dari lokal: $MON_LOCAL"
else
  say "Monitor lokal tak ada -> unduh dari $BASE_URL"
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$BASE_URL/monitor-client.js" -o "$GDIR/monitor-client.js"
  elif command -v wget >/dev/null 2>&1; then wget -qO "$GDIR/monitor-client.js" "$BASE_URL/monitor-client.js"
  else die "Butuh curl/wget untuk mengunduh monitor, atau taruh monitor-client.js di samping folder office."; fi
fi
[ -s "$GDIR/monitor-client.js" ] || die "monitor-client.js kosong/gagal."

# --- config.env ----------------------------------------------------------
cat > "$GDIR/config.env" <<EOF
TORANG_OFFICE_DIR=$OFFICE_DIR
TORANG_PORT=$PORT
TORANG_JOIN_KEY=$JOIN_KEY
EOF

# --- start.sh: nyalakan office + monitor guru (auto-restart) -------------
cat > "$GDIR/start.sh" <<'EOF'
#!/usr/bin/env bash
# Nyalakan office (app.py) + monitor guru. Aman dijalankan berkali-kali.
set -a; . "$HOME/.torang-guru/config.env"; set +a
G="$HOME/.torang-guru"
PORT="${TORANG_PORT:-19000}"

# kalau monitor guru sudah jalan -> anggap sudah nyala, keluar (hindari dobel)
if pgrep -f "$G/monitor-client.js" >/dev/null 2>&1; then
  echo "[start] sudah jalan"; exit 0
fi

# 1) OFFICE (loop auto-restart)
(
  cd "$TORANG_OFFICE_DIR/backend" || exit 1
  export STAR_BACKEND_PORT="$PORT"
  while true; do
    python3 app.py >>"$G/office.log" 2>&1
    echo "[office] berhenti, restart 3s..." >>"$G/office.log"
    sleep 3
  done
) &

# tunggu office siap
for i in $(seq 1 20); do
  if command -v curl >/dev/null 2>&1 && curl -fsS "http://127.0.0.1:$PORT/status" >/dev/null 2>&1; then break; fi
  sleep 1
done

# 2) MONITOR GURU (loop auto-restart)
(
  export TORANG_TARGET=star-office
  export TORANG_SO_ROLE=teacher
  export TORANG_OFFICE_URL="http://127.0.0.1:$PORT"
  export TORANG_JOIN_KEY="${TORANG_JOIN_KEY:-ocj_test}"
  while true; do
    node "$G/monitor-client.js" >>"$G/monitor.log" 2>&1
    echo "[monitor] berhenti, restart 5s..." >>"$G/monitor.log"
    sleep 5
  done
) &

wait
EOF
chmod +x "$GDIR/start.sh"

# --- helper stop ---------------------------------------------------------
cat > "$GDIR/stop.sh" <<'EOF'
#!/usr/bin/env bash
pkill -f "$HOME/.torang-guru/start.sh" 2>/dev/null || true
pkill -f "$HOME/.torang-guru/monitor-client.js" 2>/dev/null || true
pkill -f "backend/app.py" 2>/dev/null || true
echo "[Torang-Guru] dihentikan."
EOF
chmod +x "$GDIR/stop.sh"

# --- .wslconfig (batasi RAM WSL) ----------------------------------------
WSLCONF="$WINPROFILE/.wslconfig"
if [ -f "$WSLCONF" ] && grep -qi '\[wsl2\]' "$WSLCONF"; then
  say ".wslconfig sudah ada -> dibiarkan ($WSLCONF)"
else
  printf '[wsl2]\nmemory=%s\nprocessors=%s\nswap=%s\n' "$WSL_MEM" "$WSL_CPU" "$WSL_SWAP" > "$WSLCONF"
  say ".wslconfig ditulis (memory=$WSL_MEM cpu=$WSL_CPU swap=$WSL_SWAP). Aktif setelah WSL/PC restart."
fi

# --- auto-start tiap buka WSL (idempoten) --------------------------------
HOOK='pgrep -f "$HOME/.torang-guru/monitor-client.js" >/dev/null 2>&1 || (nohup "$HOME/.torang-guru/start.sh" >>"$HOME/.torang-guru/boot.log" 2>&1 &)'
if ! grep -q "torang-guru/start.sh" "$HOME/.bashrc" 2>/dev/null; then
  { echo ""; echo "# Torang office+monitor guru (auto-start saat buka WSL)"; echo "$HOOK"; } >> "$HOME/.bashrc"
fi

# --- roster bersih sekali di awal ---------------------------------------
rm -f "$OFFICE_DIR/backend/agents-state.json" 2>/dev/null || true

# =====================================================================
#  BAGIAN WINDOWS: jaringan LAN + auto-start saat PC login (butuh admin)
# =====================================================================
if [ "${TORANG_NO_NET:-0}" != "1" ]; then
  BOOTLINE=""
  [ "${TORANG_NO_BOOT:-0}" != "1" ] && BOOTLINE="setboot"

  SETUP_LX="$WINPROFILE/torang-guru-setup.ps1"
  # tulis setup.ps1 (baris pertama inject $port & flag boot, sisanya literal)
  {
    echo "\$port = $PORT"
    if [ -n "$BOOTLINE" ]; then echo "\$doBoot = \$true"; else echo "\$doBoot = \$false"; fi
    cat <<'PSEOF'
$ErrorActionPreference = 'Continue'
$dir = "$env:ProgramData\Torang"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

function Get-WslIp {
  $o = (wsl.exe hostname -I) 2>$null
  if ($o) { return (($o -join ' ').Trim() -split '\s+')[0] }
  return $null
}

# 1) portproxy SEKARANG
$wslip = Get-WslIp
if ($wslip) {
  netsh interface portproxy delete v4tov4 listenport=$port listenaddress=0.0.0.0 2>$null | Out-Null
  netsh interface portproxy add    v4tov4 listenport=$port listenaddress=0.0.0.0 connectport=$port connectaddress=$wslip | Out-Null
  Write-Host ("[net] portproxy 0.0.0.0:{0} -> {1}:{0}" -f $port,$wslip)
} else {
  Write-Host "[net] PERINGATAN: IP WSL tak terbaca (WSL mati?). Portproxy dilewati."
}

# 2) firewall
netsh advfirewall firewall delete rule name="Torang Office $port" 2>$null | Out-Null
netsh advfirewall firewall add rule name="Torang Office $port" dir=in action=allow protocol=TCP localport=$port | Out-Null
Write-Host "[net] firewall izinkan TCP $port"

# 3) skrip relink (dipakai scheduled task tiap 2 menit)
$relink = Join-Path $dir "relink.ps1"
@"
`$port = $port
`$o = (wsl.exe hostname -I) 2>`$null
if (`$o) {
  `$ip = ((`$o -join ' ').Trim() -split '\s+')[0]
  netsh interface portproxy delete v4tov4 listenport=`$port listenaddress=0.0.0.0 2>`$null | Out-Null
  netsh interface portproxy add    v4tov4 listenport=`$port listenaddress=0.0.0.0 connectport=`$port connectaddress=`$ip | Out-Null
}
"@ | Set-Content -Path $relink -Encoding ASCII

# 4) scheduled task: relink tiap 2 menit
schtasks /Create /TN "TorangOfficeLAN" /F /RL HIGHEST /SC MINUTE /MO 2 `
  /TR "powershell -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$relink`"" | Out-Null
Write-Host "[task] TorangOfficeLAN (relink portproxy tiap 2 menit) terpasang"

# 5) auto-start office+monitor saat PC login (opsional)
if ($doBoot) {
  $bootcmd = Join-Path $dir "boot-guru.cmd"
  'wsl.exe -- bash -lc "$HOME/.torang-guru/start.sh"' | Set-Content -Path $bootcmd -Encoding ASCII

  $vbs = Join-Path $dir "run-hidden.vbs"
  ('Set s = CreateObject("WScript.Shell")' + "`r`n" + 's.Run "cmd /c ""' + $bootcmd + '""", 0, False') |
    Set-Content -Path $vbs -Encoding ASCII

  schtasks /Create /TN "TorangGuruBoot" /F /RL HIGHEST /SC ONLOGON `
    /TR "wscript `"$vbs`"" | Out-Null
  Write-Host "[task] TorangGuruBoot (nyalakan office+monitor saat login) terpasang"
}

Write-Host "[Torang-Guru] Setup Windows selesai."
PSEOF
  } > "$SETUP_LX"

  SETUP_WIN="$(wslpath -w "$SETUP_LX")"
  say "Menyiapkan jaringan Windows (akan muncul UAC -> klik YES)..."
  # jalankan elevated & tunggu
  powershell.exe -NoProfile -Command \
    "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$SETUP_WIN'" \
    || say "PERINGATAN: setup jaringan gagal/di-cancel. Jalankan ulang installer atau buka jaringan manual."
  rm -f "$SETUP_LX" 2>/dev/null || true
else
  say "TORANG_NO_NET=1 -> lewati setup jaringan Windows."
fi

# =====================================================================
#  Nyalakan sekarang (tanpa perlu reboot)
# =====================================================================
say "Menyalakan office + monitor sekarang..."
"$GDIR/stop.sh" >/dev/null 2>&1 || true
sleep 1
nohup "$GDIR/start.sh" >>"$GDIR/boot.log" 2>&1 &
sleep 4

# tampilkan IP LAN buat dibagikan ke murid
LANIP="$(cmd.exe /c 'ipconfig' 2>/dev/null | tr -d '\r' | awk '/IPv4/{print $NF}' | grep -E '^192\.|^10\.|^172\.' | head -1)"
echo ""
say "=================== SELESAI ==================="
say "Office     : http://127.0.0.1:$PORT  (di PC guru)"
[ -n "$LANIP" ] && say "Untuk murid: http://$LANIP:$PORT   (alamat office guru)"
say "Log office : $GDIR/office.log"
say "Log monitor: $GDIR/monitor.log"
say "Hentikan   : $GDIR/stop.sh    |  Nyalakan lagi: $GDIR/start.sh"
say "Auto-start : tiap buka WSL + (kalau dipasang) saat PC login."
say "==============================================="
