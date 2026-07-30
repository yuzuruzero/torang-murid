#!/usr/bin/env bash
# =====================================================================
#  TORANG — SAPU AGENT BASI dari office
#
#  Menghapus karakter yang sudah lama tak mengirim kabar — biasanya PC murid
#  yang dimatikan. Monitor SENGAJA tidak mengirim /leave-agent saat mati
#  (lihat komentar di monitor-client.js: restart loop bikin semua karakter
#  berkedip hilang-muncul), jadi office tak pernah tahu PC-nya sudah pergi.
#
#  Hanya memakai endpoint yang sudah ada, jadi TIDAK perlu restart office.
#
#  Pakai:
#    ./torang-sapu-agent.sh --kering          lihat dulu, tanpa menghapus
#    ./torang-sapu-agent.sh                   sapu dengan ambang 15 menit
#    ./torang-sapu-agent.sh --ambang 600      sapu dengan ambang 10 menit
# =====================================================================
set -u

AMBANG=900
KERING=0
OFFICE="${TORANG_OFFICE_URL:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --ambang) AMBANG="${2:-900}"; shift 2 ;;
    --kering|--dry-run) KERING=1; shift ;;
    --office) OFFICE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "[sapu] argumen tak dikenal: $1 (pakai --help)"; exit 1 ;;
  esac
done

# alamat office: env -> config.env guru -> default lokal
if [ -z "$OFFICE" ]; then
  for f in "$HOME/.torang-guru/config.env" "$HOME/.torang/config.env"; do
    [ -f "$f" ] || continue
    # shellcheck disable=SC1090
    P="$(grep -E '^TORANG_PORT=' "$f" | tail -1 | cut -d= -f2)"
    U="$(grep -E '^TORANG_OFFICE_URL=' "$f" | tail -1 | cut -d= -f2)"
    [ -n "$U" ] && { OFFICE="$U"; break; }
    [ -n "$P" ] && { OFFICE="http://127.0.0.1:$P"; break; }
  done
fi
OFFICE="${OFFICE:-http://127.0.0.1:19000}"
OFFICE="${OFFICE%/}"

command -v curl >/dev/null 2>&1 || { echo "[sapu] butuh 'curl'."; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "[sapu] butuh 'python3'."; exit 1; }

DAFTAR="$(curl -fsS --max-time 10 "$OFFICE/agents" 2>/dev/null)" || {
  echo "[sapu] office tidak menjawab di $OFFICE — nyala tidak?"; exit 1; }

# Pilih yang basi. Umur dihitung dari lastPushAt, mundur ke updated_at lalu
# authApprovedAt — rantai yang sama dipakai office saat menandai 'offline'.
# Karakter utama (isMain, yaitu 'star') tidak pernah ikut tersapu.
PILIHAN="$(printf '%s' "$DAFTAR" | python3 -c "
import json, sys
from datetime import datetime as d
ambang = float(sys.argv[1])
now = d.now()
try:
    agents = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for a in agents:
    if a.get('isMain'):
        continue
    umur = None
    for k in ('lastPushAt', 'updated_at', 'authApprovedAt'):
        s = a.get(k)
        if not s:
            continue
        try:
            umur = (now - d.fromisoformat(s)).total_seconds(); break
        except Exception:
            continue
    if umur is None or umur > ambang:
        menit = '?' if umur is None else str(int(umur // 60))
        print('%s\t%s\t%s' % (a.get('agentId', ''), menit, a.get('name', '')))
" "$AMBANG")"

if [ -z "$PILIHAN" ]; then
  echo "[sapu] Tidak ada karakter basi (ambang ${AMBANG} dtk). Office bersih."
  exit 0
fi

JUMLAH="$(printf '%s\n' "$PILIHAN" | wc -l)"
echo "[sapu] office   : $OFFICE"
echo "[sapu] ambang   : ${AMBANG} dtk ($((AMBANG / 60)) menit)"
echo "[sapu] ditemukan: $JUMLAH karakter basi"
echo ""

OK=0
GAGAL=0
while IFS="$(printf '\t')" read -r ID MENIT NAMA; do
  [ -n "$ID" ] || continue
  if [ "$KERING" = "1" ]; then
    printf '  (kering) %-22s diam %s menit  %s\n' "$ID" "$MENIT" "$NAMA"
    continue
  fi
  if curl -fsS --max-time 8 -X POST "$OFFICE/leave-agent" \
       -H 'Content-Type: application/json' -d "{\"agentId\":\"$ID\"}" >/dev/null 2>&1; then
    printf '  dihapus  %-22s diam %s menit  %s\n' "$ID" "$MENIT" "$NAMA"
    OK=$((OK + 1))
  else
    printf '  GAGAL    %-22s %s\n' "$ID" "$NAMA"
    GAGAL=$((GAGAL + 1))
  fi
done <<EOF
$PILIHAN
EOF

echo ""
if [ "$KERING" = "1" ]; then
  echo "[sapu] Mode kering — tidak ada yang dihapus. Jalankan tanpa --kering untuk menyapu."
else
  SISA="$(curl -fsS --max-time 8 "$OFFICE/agents" 2>/dev/null | python3 -c "import json,sys;print(len(json.load(sys.stdin)))" 2>/dev/null || echo '?')"
  echo "[sapu] Selesai: $OK dihapus, $GAGAL gagal. Sisa karakter di office: $SISA"
fi
