# Panduan Torang — Setup Bersih dari Awal (Guru & Murid)

> Tujuan: satu alur pasti, tanpa mode ketuker. Baca "Konsep" sekali biar nggak pusing lagi.

## Konsep (WAJIB paham dulu)

Tiga komponen terpisah:

1. **Office** — hanya jalan di **PC GURU** (Flask, port 19000). Menyimpan tampilan pixel-office.
2. **Monitor** (`monitor-client.js`) — polling `openclaw`, mendorong agen ke office. Dua mode:
   - **teacher** (guru): main = **KUCING tengah**, + 3 worker permanen sebagai **guest**.
   - **student** (murid): **SEMUA agen (termasuk main murid)** sebagai **guest**.
3. **Plugin `torang-events`** (opsional) — event-driven, memunculkan **subagent transient** `(temp)` saat lahir.

Aturan emas: **di GURU, main itu KUCING — bukan guest.** Kalau ada yang menyuruh "push 4 agen di guru", itu perilaku MURID; jangan.

Fakta penting yang bikin karakter "nyangkut":
- Office menyimpan guest di `~/torang-office/agents-state.json` dan **TIDAK auto-hapus** guest yang diam.
- Guest dihapus hanya lewat `/leave-agent`, yang dipanggil monitor **selama dia hidup**.
- `pkill` monitor = guest membeku di office (bukan hilang). Untuk membersihkan: lihat Bagian 0.

---

## Bagian 0 — RESET BERSIH (kalau ada karakter nyangkut)

Di **GURU**:
```bash
pkill -f monitor-client.js          # hentikan semua monitor
rm -f ~/torang-office/agents-state.json   # hapus semua guest (kucing pakai state.json, aman)
```
Office membaca file ini tiap request; begitu dihapus, guest nyangkut langsung hilang dalam beberapa detik. Tidak perlu restart office. (Kalau mau benar-benar fresh, boleh restart office juga — file dibuat ulang berisi hanya main.)

Join key (`ocj_test`) di `join-keys.json` tidak terpengaruh.

---

## Bagian 1 — PC GURU

### 1a. Nyalakan office (Terminal 1 — biarkan terbuka)
```bash
cd ~/torang-office && source .venv/bin/activate && PORT=19000 python3 backend/app.py
```
Verifikasi (terminal lain):
```bash
curl -sS http://127.0.0.1:19000/health     # {"status":"ok",...}
```
Buka `http://127.0.0.1:19000` di browser guru untuk lihat office.

### 1b. Pastikan monitor versi terbaru (cegah drift)
```bash
head -3 ~/torang-office/monitor-client.js   # harus v3.9
# kalau bukan v3.9, sinkron dari repo:
cp /mnt/d/projects/torangapp/star-office-tools/monitor-client.js ~/torang-office/monitor-client.js
```

### 1c. Jalankan monitor mode teacher (Terminal 2 — biarkan terbuka)
```bash
cd ~/torang-office && TORANG_TARGET=star-office TORANG_SO_ROLE=teacher \
  TORANG_OFFICE_URL=http://127.0.0.1:19000 TORANG_JOIN_KEY=ocj_test \
  TORANG_AGENT_NAME=Miri node monitor-client.js
```
Hasil: main = kucing panggung; `desainer_etalase`/`customer_service`/`business_analyst` = guest di ruang masing-masing (idle → Standby).
Catatan: kucing baru **beranimasi** saat main benar-benar kerja lewat gateway (`openclaw tui`/`chat`/`message`). Uji pakai `openclaw agent --local` mungkin tidak menyalakan animasi (sesi embedded tak update file sesi yang dipantau).

### 1d. Pasang plugin subagent hatch (Terminal 3 — sekali jalan)
```bash
cd /mnt/d/projects/torangapp/star-office-tools && bash install-plugin-torang.sh
tail -n 3 ~/torang-events.log       # harus ada: REGISTER v0.2
```
Uji: delegasikan tugas ke subagent → karakter `ai6 · … (temp)` muncul di Ruang Tamu → pindah ke Data → keluar saat selesai.

### 1e. Buka akses jaringan buat murid (kalau lewat LAN)
Jalankan `PASANG-permanen-win10.bat` (as admin, dari `torang-guru-win10-permanen.zip`) — nyambungkan `Windows:19000 → WSL:19000`, bertahan reboot. Verifikasi dari HP sejaringan: `http://IP-GURU:19000`.

---

## Bagian 2 — PC MURID (tiap PC, di WSL yang ada OpenClaw)

### 2a. Pasang monitor student
```bash
# ganti IP-GURU dengan IP LAN guru (mis. 192.168.18.12)
TORANG_OFFICE_URL=http://IP-GURU:19000 bash <(curl -fsSL \
  https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/install-torang-murid.sh)
```
Installer menulis `~/.torang/{monitor-client.js,config.env,start.sh}`, menambah auto-start di `.bashrc`, dan menjalankan monitor mode **student** di latar (nama = hostname).
Hasil: tim murid (main + 3 worker) muncul sebagai **guest terpisah** dengan prefix nama hostname — tidak merge dengan tim PC lain.

### 2b. (Opsional) plugin subagent hatch di murid
```bash
TORANG_OFFICE_URL=http://IP-GURU:19000 TORANG_JOIN_KEY=ocj_test \
  bash <(curl -fsSL https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/install-plugin-torang.sh)
```

### 2c. Stop / bersih di murid
```bash
pkill -f 'torang/start.sh'; pkill -f monitor-client.js
```

---

## Verifikasi akhir (di layar office guru)
- 1 kucing di panggung (guru) + `Miri`'s 3 worker.
- Saat delegasi subagent → karakter `(temp)` muncul lalu hilang saat selesai.
- Tiap murid online → tim guest sendiri dengan prefix hostname.

## Kalau kacau lagi
Ulangi **Bagian 0** (reset) di guru, lalu **Bagian 1c** (monitor teacher). Jangan pernah jalankan monitor mode student di PC guru.

## Cek proses cepat
```bash
pgrep -af 'backend/app.py'        # office (harus 1)
pgrep -af monitor-client.js       # monitor (guru: 1 teacher; jangan ada student nyasar)
openclaw plugins list | grep -i torang   # plugin enabled
```
