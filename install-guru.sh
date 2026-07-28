#!/usr/bin/env bash
# =====================================================================
#  TORANG - Pemasang OFFICE + MONITOR GURU (turnkey / curl|bash)
#  Jalankan di WSL PC GURU:
#
#    curl -fsSL https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/install-guru.sh | bash
#
#  Yang diurus otomatis:
#    1) CLONE office (torang-office) dari GitHub kalau belum ada lokal
#    2) PASANG Python venv + flask (fresh clone tak punya .venv) -> office langsung jalan
#    3) join-keys.json: key kelas + maxConcurrent BESAR (default 100) -> 4-10 murid muat
#    4) .wslconfig (batasi RAM WSL biar Windows tak nge-hang)
#    5) launcher office (app.py) + monitor guru (peran teacher), auto-restart
#    6) auto-start tiap buka WSL (.bashrc)
#    7) JARINGAN LAN (portproxy+firewall) via PowerShell admin (muncul UAC -> klik Yes)
#    8) scheduled task Windows: relink portproxy tiap 2 menit + nyalakan office saat PC login
#    9) alat ganti-key (torang-key.sh) + CETAK perintah murid siap-tempel
#
#  Prasyarat di PC guru:
#    - WSL + OpenClaw terpasang (ada `node`, `python3`, `git`)
#    - Akses GitHub ke repo PRIVAT torang-office (salah satu):
#        * sudah login git di PC ini (git credential manager / `gh auth login`), ATAU
#        * kasih token saat pasang:  TORANG_GH_TOKEN=ghp_xxx  (read-only cukup)
#
#  Override lewat env (opsional):
#    TORANG_JOIN_KEY=kelas-7a         key kelas (default ocj_test)
#    TORANG_MAXCONC=100               batas koneksi per-key (default 100)
#    TORANG_OFFICE_DIR=/path/office   folder office kalau sudah ada lokal
#    TORANG_OFFICE_REPO / TORANG_OFFICE_DEST / TORANG_GH_TOKEN   opsi clone
#    TORANG_PORT=19000                port office
#    TORANG_WSL_MEM=3GB / TORANG_WSL_CPU=2 / TORANG_WSL_SWAP=2GB  batas WSL
#    TORANG_NO_NET=1  lewati setup jaringan Windows   |  TORANG_NO_BOOT=1  jangan auto-start saat login
# =====================================================================
set -e

PORT="${TORANG_PORT:-19000}"
JOIN_KEY="${TORANG_JOIN_KEY:-ocj_test}"
MAXCONC="${TORANG_MAXCONC:-100}"
WSL_MEM="${TORANG_WSL_MEM:-3GB}"
WSL_CPU="${TORANG_WSL_CPU:-2}"
WSL_SWAP="${TORANG_WSL_SWAP:-2GB}"
BASE_URL="${TORANG_BASE_URL:-https://raw.githubusercontent.com/yuzuruzero/torang-murid/main}"
OFFICE_REPO="${TORANG_OFFICE_REPO:-https://github.com/yuzuruzero/torang-office.git}"
OFFICE_DEST="${TORANG_OFFICE_DEST:-$HOME/torang-office}"
GDIR="$HOME/.torang-guru"

say(){ echo "[Torang-Guru] $*"; }
die(){ echo "[Torang-Guru] GAGAL: $*" >&2; exit 1; }

# --- pastikan ini WSL (ada sisi Windows) ---------------------------------
[ -d /mnt/c ] || die "Ini tampaknya bukan WSL (tidak ada /mnt/c). Jalankan di WSL PC guru."

# --- cari nama user Windows (untuk .wslconfig) ---------------------------
WINUSER="$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r\n')"
WINPROFILE="/mnt/c/Users/$WINUSER"
if [ -z "$WINUSER" ] || [ ! -d "$WINPROFILE" ]; then
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
  if [ -n "$TORANG_OFFICE_DIR" ] && [ -f "$TORANG_OFFICE_DIR/backend/app.py" ]; then
    echo "$TORANG_OFFICE_DIR"; return 0
  fi
  for c in \
    "$OFFICE_DEST" \
    /mnt/d/projects/torangapp/torang-office \
    /mnt/d/projects/torangapp/Star-Office-UI \
    /mnt/c/projects/torangapp/Star-Office-UI \
    "$HOME/torangapp/Star-Office-UI" \
    "$HOME/Star-Office-UI" ; do
    [ -f "$c/backend/app.py" ] && { echo "$c"; return 0; }
  done
  for base in /mnt/d /mnt/c /mnt/e /mnt/f; do
    [ -d "$base" ] || continue
    hit="$(find "$base" -maxdepth 5 -type f -path '*/backend/app.py' 2>/dev/null | head -1)"
    [ -n "$hit" ] && { echo "$(dirname "$(dirname "$hit")")"; return 0; }
  done
  return 1
}

say "Mencari folder office (ada backend/app.py)..."
OFFICE_DIR="$(find_office || true)"

# --- kalau office belum ada lokal -> CLONE otomatis dari GitHub (repo privat) ---
if [ -z "$OFFICE_DIR" ]; then
  command -v git >/dev/null 2>&1 || die "Office tak ada & 'git' tak terpasang. Pasang git, atau copy folder office manual."
  if [ -f "$OFFICE_DEST/backend/app.py" ]; then
    say "Office hasil clone sebelumnya ditemukan: $OFFICE_DEST"
    OFFICE_DIR="$OFFICE_DEST"
  else
    say "Office lokal tak ketemu -> CLONE dari $OFFICE_REPO"
    CLONE_URL="$OFFICE_REPO"
    if [ -n "$TORANG_GH_TOKEN" ]; then
      SLUG="$(echo "$OFFICE_REPO" | sed -E 's#https?://github.com/##; s#\.git$##')"
      CLONE_URL="https://x-access-token:${TORANG_GH_TOKEN}@github.com/${SLUG}.git"
    fi
    rm -rf "$OFFICE_DEST" 2>/dev/null || true
    if git clone --depth 1 "$CLONE_URL" "$OFFICE_DEST" 2>&1 | sed 's/x-access-token:[^@]*@/x-access-token:***@/g' | tail -4; then :; fi
    if [ -f "$OFFICE_DEST/backend/app.py" ]; then
      OFFICE_DIR="$OFFICE_DEST"; say "Office ter-clone ke: $OFFICE_DIR"
    fi
  fi
fi

if [ -z "$OFFICE_DIR" ] || [ ! -f "$OFFICE_DIR/backend/app.py" ]; then
  die "Office tak ketemu & clone gagal. Repo torang-office PRIVAT butuh akses GitHub:
       - login dulu di PC ini: 'gh auth login'  (atau git credential manager), ATAU
       - kasih token saat pasang: TORANG_GH_TOKEN=ghp_xxx <perintah installer>
       Atau copy folder office manual & set TORANG_OFFICE_DIR=/mnt/.../office."
fi
say "Office: $OFFICE_DIR"

# =====================================================================
#  [BARU] PYTHON venv + flask  — fresh clone tak punya .venv (tanpa ini office error flask)
# =====================================================================
PYBIN="python3"
if python3 -c "import flask" 2>/dev/null; then
  say "flask sudah ada di python3 sistem."
else
  VENV="$OFFICE_DIR/.venv"
  say "Menyiapkan Python + flask (bikin venv + pasang dependensi)..."
  if [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c "import flask" 2>/dev/null; then
    PYBIN="$VENV/bin/python"
  elif python3 -m venv "$VENV" 2>/dev/null; then
    "$VENV/bin/python" -m ensurepip >/dev/null 2>&1 || true
    "$VENV/bin/pip" install --quiet --upgrade pip >/dev/null 2>&1 || true
    if [ -f "$OFFICE_DIR/backend/requirements.txt" ]; then
      "$VENV/bin/pip" install --quiet -r "$OFFICE_DIR/backend/requirements.txt" || true
    else
      "$VENV/bin/pip" install --quiet flask || true
    fi
    "$VENV/bin/python" -c "import flask" 2>/dev/null && PYBIN="$VENV/bin/python"
  fi
  if ! "$PYBIN" -c "import flask" 2>/dev/null; then
    say "venv gagal -> coba pip sistem."
    pip3 install --quiet flask 2>/dev/null \
      || pip3 install --quiet --break-system-packages flask 2>/dev/null \
      || pip3 install --quiet --user flask 2>/dev/null || true
    python3 -c "import flask" 2>/dev/null && PYBIN="python3"
  fi
  "$PYBIN" -c "import flask" 2>/dev/null \
    || die "Gagal memasang flask. Manual: python3 -m venv \"$OFFICE_DIR/.venv\" && \"$OFFICE_DIR/.venv/bin/pip\" install -r \"$OFFICE_DIR/backend/requirements.txt\""
  say "Python siap: $PYBIN"
fi

# =====================================================================
#  [BARU] join-keys.json — pastikan key kelas ADA + maxConcurrent BESAR
#         (office menolak key tak terdaftar & default maxConcurrent cuma 3)
# =====================================================================
JK="$OFFICE_DIR/join-keys.json"
python3 - "$JK" "$JOIN_KEY" "$MAXCONC" <<'PY'
import json, sys, os
path, key, mx = sys.argv[1], sys.argv[2], int(sys.argv[3])
data = {"keys": []}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as f: data = json.load(f)
    except Exception: data = {"keys": []}
if not isinstance(data, dict) or "keys" not in data: data = {"keys": []}
keys = data["keys"]
it = next((k for k in keys if k.get("key") == key), None)
if it:
    it["reusable"] = True; it["maxConcurrent"] = mx; it.pop("expiresAt", None)
else:
    keys.append({"key": key, "used": False, "reusable": True, "maxConcurrent": mx,
                 "usedBy": None, "usedByAgentId": None, "usedAt": None})
data["keys"] = keys
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
os.replace(tmp, path)
print(f"[join-keys] key '{key}' siap (maxConcurrent={mx}, reusable)")
PY

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

# --- [BARU] alat ganti-key (torang-key.sh) ------------------------------
KEY_LOCAL=""
for c in \
  "$(dirname "$OFFICE_DIR")/star-office-tools/torang-key.sh" \
  "$OFFICE_DIR/../star-office-tools/torang-key.sh" ; do
  [ -f "$c" ] && { KEY_LOCAL="$c"; break; }
done
if [ -n "$KEY_LOCAL" ]; then cp "$KEY_LOCAL" "$GDIR/torang-key.sh"
else curl -fsSL "$BASE_URL/torang-key.sh" -o "$GDIR/torang-key.sh" 2>/dev/null || true; fi
[ -f "$GDIR/torang-key.sh" ] && chmod +x "$GDIR/torang-key.sh"

# --- config.env ----------------------------------------------------------
cat > "$GDIR/config.env" <<EOF
TORANG_OFFICE_DIR=$OFFICE_DIR
TORANG_PORT=$PORT
TORANG_JOIN_KEY=$JOIN_KEY
TORANG_MAXCONC=$MAXCONC
TORANG_PYBIN=$PYBIN
EOF

# --- start.sh: nyalakan office + monitor guru (auto-restart) -------------
cat > "$GDIR/start.sh" <<'EOF'
#!/usr/bin/env bash
# Nyalakan office (app.py) + monitor guru. Aman dijalankan berkali-kali.
set -a; . "$HOME/.torang-guru/config.env"; set +a
G="$HOME/.torang-guru"
PORT="${TORANG_PORT:-19000}"
PYBIN="${TORANG_PYBIN:-python3}"

# kalau monitor guru sudah jalan -> anggap sudah nyala, keluar (hindari dobel)
if pgrep -f "$G/monitor-client.js" >/dev/null 2>&1; then
  echo "[start] sudah jalan"; exit 0
fi

# 1) OFFICE (loop auto-restart) — pakai PYBIN (venv) biar flask kebaca
(
  cd "$TORANG_OFFICE_DIR/backend" || exit 1
  export STAR_BACKEND_PORT="$PORT"
  while true; do
    "$PYBIN" app.py >>"$G/office.log" 2>&1
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
rm -f "$OFFICE_DIR/backend/agents-state.json" "$OFFICE_DIR/agents-state.json" 2>/dev/null || true

# =====================================================================
#  BAGIAN WINDOWS: jaringan LAN + auto-start saat PC login (butuh admin)
# =====================================================================
if [ "${TORANG_NO_NET:-0}" != "1" ]; then
  BOOTLINE=""
  [ "${TORANG_NO_BOOT:-0}" != "1" ] && BOOTLINE="setboot"

  SETUP_LX="$WINPROFILE/torang-guru-setup.ps1"
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
sleep 5

# --- tunggu office benar-benar siap (biar pesan akhir akurat) ---
OK=0
for i in $(seq 1 20); do
  if command -v curl >/dev/null 2>&1 && curl -fsS "http://127.0.0.1:$PORT/status" >/dev/null 2>&1; then OK=1; break; fi
  sleep 1
done

# --- IP LAN buat murid ---
LANIP="$(cmd.exe /c 'ipconfig' 2>/dev/null | tr -d '\r' | awk '/IPv4/{print $NF}' | grep -E '^192\.|^10\.|^172\.' | head -1)"
[ -z "$LANIP" ] && LANIP="IP-GURU"

echo ""
say "=================== SELESAI ==================="
[ "$OK" = "1" ] && say "Office AKTIF : http://127.0.0.1:$PORT  (buka di PC guru, Ctrl+F5)" \
                || say "Office belum kebaca di :$PORT — cek $GDIR/office.log"
say "Key kelas    : $JOIN_KEY   (maxConcurrent $MAXCONC)"
echo ""
echo "  >>> PERINTAH UNTUK MURID (tempel di WSL tiap PC murid): <<<"
echo "  -----------------------------------------------------------------"
echo "  TORANG_OFFICE_URL=http://$LANIP:$PORT TORANG_JOIN_KEY=$JOIN_KEY \\"
echo "  bash <(curl -fsSL $BASE_URL/install.sh)"
echo "  -----------------------------------------------------------------"
echo ""
say "Ganti key kelas kapan saja : bash $GDIR/torang-key.sh <key-baru>"
say "Log office/monitor         : $GDIR/office.log  |  $GDIR/monitor.log"
say "Stop / Start               : $GDIR/stop.sh  |  $GDIR/start.sh"
say "Auto-start                 : tiap buka WSL + (kalau dipasang) saat PC login."
say "==============================================="
