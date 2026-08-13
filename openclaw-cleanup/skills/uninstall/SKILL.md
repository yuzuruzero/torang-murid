---
name: uninstall
description: >
  This skill should be used when the user asks to uninstall, remove, or wipe
  OpenClaw, Hermes, and/or Torang Event from Ubuntu/WSL -- e.g. "/uninstall",
  "uninstall openclaw", "cabut openclaw", "hapus hermes", "bersihkan PC murid",
  "hapus semua jejak openclaw/hermes/torang", "uninstall total". It stops
  services and processes, uninstalls by detected install method, removes
  config/cache/logs, and verifies. Always dry-run + explicit user confirmation
  before deleting anything.
metadata:
  version: "0.1.0"
---

# /uninstall -- Cabut total OpenClaw + Hermes + Torang Event

Cabut ketiga komponen sampai bersih dari Ubuntu/WSL memakai skrip teruji
`scripts/oc-uninstall.sh` -- BUKAN dengan merangkai perintah hapus manual.
Skrip ini turunan `torang-bersih-kelas.sh` v1.2 yang sudah dipakai di kelas dan
membawa semua pagar keamanan hasil kejadian nyata.

## Lokasi skrip

Akar plugin = dua tingkat di atas direktori skill ini (`skills/uninstall/` ->
akar). Kalau variabel `${CLAUDE_PLUGIN_ROOT}` tersedia di lingkungan Bash, itu
juga akar plugin. Skrip: `<akar>/scripts/oc-uninstall.sh`. Pastikan file itu
ada (`ls`) sebelum menjalankan; kalau tak ada, lihat bagian "Fallback".

## Prosedur WAJIB (jangan lompati satu pun)

1. **Pahami argumen pengguna.** Petakan permintaan ke flag skrip:
   - hanya lihat rencana -> `--dry-run`
   - ikut cabut sisi guru (office di ~/torang-office) -> `--guru`
   - simpan hasil kerja murid dulu -> `--arsip`
   - jangan cabut OpenClaw / Hermes / Torang -> `--sisakan-oc` / `--sisakan-hm`
     / `--sisakan-torang`
   - buang baris PATH ~/.local/bin dari rc -> `--bersihkan-path`
2. **Selalu dry-run dulu**, apa pun permintaannya:
   `bash <akar>/scripts/oc-uninstall.sh --dry-run [flag...]`
   Tahap 0 skrip melaporkan METODE INSTAL yang terdeteksi (npm/pnpm/bun global,
   pipx/pip, biner manual, docker, dir state) -- pencabutan mengikuti metode itu.
3. **Tampilkan rencana ke pengguna** secara ringkas dan terstruktur: apa yang
   akan dimatikan (proses, unit systemd user & sistem, pemegang port 18789),
   apa yang akan dihapus (paket, direktori config/cache/log, cron, autostart),
   dan baris `perlu --sudo` yang mana saja. Jangan tempel log mentah panjang.
4. **Minta konfirmasi eksplisit** lewat AskUserQuestion (kalau tersedia; kalau
   tidak, tanya lewat teks dan TUNGGU jawaban). Opsi minimal: lanjut hapus /
   batal. TANPA konfirmasi eksplisit dari pengguna, JANGAN pernah eksekusi.
   Kalau sesi tampak tak dijaga (scheduled/unattended), berhenti di rencana
   dry-run dan laporkan -- jangan menghapus.
5. **Sudo hanya dengan izin per kebutuhan.** Kalau dry-run menandai item
   `perlu --sudo` (unit systemd sistem, /etc/openclaw, /usr/local/bin,
   /var/log), jelaskan ke pengguna item apa dan kenapa butuh root, lalu minta
   izin. Baru setelah disetujui tambahkan `--sudo`. Kalau ditolak, jalan tanpa
   `--sudo` dan laporkan sisa yang butuh root berikut perintah manualnya.
6. **Eksekusi**: `bash <akar>/scripts/oc-uninstall.sh -y [flag...]`
   (`-y` sah HANYA karena konfirmasi sudah diberikan pengguna di langkah 4).
7. **Baca exit code dan laporkan**:
   - `0` = bersih -- tunjukkan ringkasan verifikasi bawaan skrip
     (`which openclaw` kosong, tidak ada unit/proses/port/direktori sisa).
   - `2` = masih ada sisa -- kutip baris `MASIH ADA ...`, jelaskan penyebab
     (biasanya butuh `--sudo`), tawarkan mengulang.
   - `1` = gagal/batal -- laporkan apa adanya.
8. **Sampaikan langkah manual di luar PC** (skrip juga mencetaknya): bot
   Telegram murid masih hidup di server Telegram (BotFather -> /deletebot),
   API key OpenAI kelas perlu di-rotate, dan pairing basi sisi guru
   (`~/torang-office/agents-state.json`). Sisi Windows PC guru (portproxy,
   scheduled task) tidak terjangkau dari Ubuntu/WSL.
9. **Tawarkan /verify** untuk pemeriksaan independen, dan ingatkan: tutup
   terminal lalu buka lagi (WSL: `wsl --shutdown`) supaya PATH segar.

## Aturan keamanan keras

- JANGAN merangkai `rm -rf` manual di luar skrip. Semua penghapusan lewat
  fungsi `buang()` yang menolak path kosong, `/`, `$HOME`, path di luar HOME,
  dan folder `~/openclaw-backup-*`.
- JANGAN menjalankan skrip sebagai root/sudo langsung -- skrip menolak dan itu
  disengaja. Root hanya lewat `--sudo` untuk item spesifik.
- JANGAN `pkill -f openclaw` mentah -- pola itu bisa membunuh shell pemanggil.
  Skrip sudah mengecualikan seluruh rantai leluhur proses.
- Urutan cabut TIDAK boleh dibalik: Torang -> OpenClaw -> Hermes. Hermes
  pemilik node/npm di ~/.local/bin; kalau dicabut duluan, npm hilang dan
  OpenClaw tak bisa dicabut rapi.

## Fallback (skrip tidak ada / gagal total)

Baca `<akar>/references/peta-jejak-instalasi.md` (peta lengkap semua jejak) dan
`<akar>/references/pengetahuan-lapangan.md` (bug yang tidak boleh diulang),
lalu kerjakan manual MENGIKUTI aturan yang sama: dry-run/tampilkan dulu,
konfirmasi, validasi tiap path tidak kosong sebelum menghapus, `type -aP`
(bukan `command -v -a`), port lewat `/proc/net/tcp`.
