#!/usr/bin/env bash
# =====================================================================
#  TORANG — CEK JALUR MURID (jalankan sebelum kelas mulai)
#
#  Memeriksa seluruh rantai dari office sampai ke titik yang diketuk PC murid.
#  Dibuat setelah kejadian 31 Jul 2026: office sehat sempurna, tapi tak ada satu
#  pun murid bisa menjangkaunya karena layanan IP Helper Windows berhenti —
#  dan `netsh portproxy show all` tetap menampilkan aturannya dengan rapi
#  seolah semua beres. Cek ini melihat port yang BENAR-BENAR terdengar,
#  bukan cuma tabel aturannya.
#
#  Pakai:  ~/.torang-guru/torang-cek-jaringan.sh
# =====================================================================
set -u
PORT="$(grep -E '^TORANG_PORT=' "$HOME/.torang-guru/config.env" 2>/dev/null | tail -1 | cut -d= -f2)"
PORT="${PORT:-19000}"
GAGAL=0
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
bad()  { printf '  \033[31mGAGAL\033[0m %s\n' "$1"; GAGAL=$((GAGAL+1)); }
warn() { printf '  \033[33m?\033[0m     %s\n' "$1"; }

echo ""
echo "=== CEK JALUR TORANG (port $PORT) ==="

# 1) office hidup di dalam WSL
if curl -fsS --max-time 5 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  N="$(curl -fsS --max-time 5 "http://127.0.0.1:$PORT/agents" 2>/dev/null | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null || echo '?')"
  ok "office hidup — $N karakter di dalamnya"
else
  bad "office TIDAK menjawab di dalam WSL. Cek: tail ~/.torang-guru/office.log"
fi

# 2) monitor guru jalan
if pgrep -f "$HOME/.torang-guru/monitor-client.js" >/dev/null 2>&1; then
  ok "monitor guru jalan"
else
  bad "monitor guru TIDAK jalan. Nyalakan: ~/.torang-guru/start.sh"
fi

# 3) layanan IP Helper — ini yang membuka port di sisi Windows
SVC="$(powershell.exe -NoProfile -Command '(Get-Service iphlpsvc).Status' 2>/dev/null | tr -d '\r\n ')"
case "$SVC" in
  Running) ok "layanan IP Helper (iphlpsvc) hidup" ;;
  "")      warn "status iphlpsvc tak terbaca (PowerShell tak terjangkau?)" ;;
  *)       bad "iphlpsvc $SVC — INI biang tersering. Perbaiki: klik kanan PowerShell > Run as administrator, lalu: Start-Service iphlpsvc" ;;
esac

# 4) Windows benar-benar mendengarkan (bukan sekadar ada aturannya)
if netstat.exe -ano 2>/dev/null | tr -d '\r' | grep -q "LISTENING" && \
   netstat.exe -ano 2>/dev/null | tr -d '\r' | grep -E "^ *TCP +0\.0\.0\.0:$PORT " | grep -q LISTENING; then
  ok "Windows mendengarkan di port $PORT"
else
  bad "Windows TIDAK mendengarkan di port $PORT — murid pasti tak bisa masuk"
fi

# 5) portproxy menunjuk ke IP WSL yang sekarang
WSLIP="$(hostname -I 2>/dev/null | awk '{print $1}')"
TUJUAN="$(netsh.exe interface portproxy show all 2>/dev/null | tr -d '\r' | awk -v p="$PORT" '$1=="0.0.0.0" && $2==p {print $3}' | head -1)"
if [ -z "$TUJUAN" ]; then
  bad "aturan portproxy untuk port $PORT tidak ada"
elif [ "$TUJUAN" = "$WSLIP" ]; then
  ok "portproxy menunjuk IP WSL yang benar ($WSLIP)"
else
  bad "portproxy menunjuk $TUJUAN, padahal IP WSL sekarang $WSLIP"
fi

# 6) alamat yang benar-benar diketuk PC murid
LANIP="$(cmd.exe /c 'ipconfig' 2>/dev/null | tr -d '\r' | awk '/IPv4/{print $NF}' | grep -E '^(192\.168\.|10\.)' | head -1)"
if [ -n "$LANIP" ]; then
  if curl -fsS --max-time 6 "http://$LANIP:$PORT/health" >/dev/null 2>&1; then
    ok "alamat murid http://$LANIP:$PORT terjangkau"
  else
    bad "alamat murid http://$LANIP:$PORT TIDAK terjangkau"
  fi
else
  warn "IP LAN Windows tak terbaca"
fi

echo ""
if [ "$GAGAL" = "0" ]; then
  echo "  SIAP. Alamat untuk murid & layar TV:  http://${LANIP:-IP-GURU}:$PORT"
else
  echo "  ADA $GAGAL MASALAH — baca baris GAGAL di atas sebelum kelas mulai."
fi
echo ""
exit "$GAGAL"
