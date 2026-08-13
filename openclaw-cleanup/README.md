# openclaw-cleanup

Plugin Claude Code/Cowork untuk mengelola uninstall, reset, dan verifikasi
kebersihan **OpenClaw**, **Hermes Agent**, dan **Torang Event** di Ubuntu /
WSL Ubuntu. Logika inti diambil dari perkakas kelas Torang yang sudah teruji
(`torang-bersih-kelas.sh` v1.2 dan `torang-cek-siap-pasang.sh`), lengkap
dengan semua pagar keamanan hasil kejadian nyata di kelas.

## Sekali jalan TANPA Claude (untuk kelas)

Tidak perlu install apa pun selain yang sudah ada di Ubuntu/WSL (bash + curl).
Satu perintah mencakup potret kondisi -> rencana -> konfirmasi -> cabut ->
verifikasi akhir:

```
bash <(curl -fsSL https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/openclaw-cleanup/scripts/oc-total.sh)
```

Varian:

```
... oc-total.sh) --dry-run     # lihat rencana saja, tidak menghapus
... oc-total.sh) -y --sudo     # kelas: tanpa tanya + bereskan bagian root
... oc-total.sh) --reset       # backup -> bersihkan -> install ulang terbaru
```

Catatan: pakai bentuk `bash <(curl ...)` persis seperti di atas -- kalau
`curl ... | bash`, konfirmasi tak terbaca dan skrip menolak jalan tanpa `-y`.
Dari clone/plugin, `oc-total.sh` otomatis memakai skrip di sebelahnya
(tanpa unduh, bisa offline).

## Skill

| Skill | Fungsi | Destruktif? |
|---|---|---|
| `/uninstall` | Deteksi metode instal (npm/pnpm/bun, pipx/pip, biner, Docker), stop & disable semua service/proses, hapus config/cache/log/cron/autostart, verifikasi akhir | Ya -- dry-run + konfirmasi wajib |
| `/reset` | Backup config & credential ke `~/openclaw-backup-<tanggal>`, bersihkan, install ulang OpenClaw + Hermes terbaru, setup awal | Ya -- dry-run + konfirmasi wajib |
| `/verify` | Pindai proses, unit systemd (user & sistem), biner PATH, paket, direktori, port gateway, autostart/cron, Docker; laporan bersih/kotor per item | Tidak (read-only) |

## Skrip inti (`scripts/`)

- `oc-total.sh` -- SEKALI JALAN: verify -> dry-run -> konfirmasi -> cabut ->
  verify akhir; `--reset` mendelegasikan ke oc-reset.sh. Bisa berdiri sendiri
  lewat `bash <(curl ...)` (mengunduh pendukungnya ke folder sementara).
- `oc-uninstall.sh` -- mesin cabut. Exit: `0` bersih, `2` masih ada sisa.
- `oc-reset.sh` -- backup -> bersih -> install ulang. Backup gagal = tidak ada
  yang dihapus; pembersihan menyisakan jejak = install dibatalkan.
- `oc-verify.sh` -- verifikasi read-only. Exit: `0` bersih, `2` tidak bersih.

Semua skrip punya `--dry-run` dan `--bantuan`, menolak dijalankan sebagai
root, dan bisa dijalankan langsung dari terminal tanpa Claude.

## Aturan keamanan yang ditegakkan

1. Selalu tampilkan rencana (dry-run) lalu minta konfirmasi pengguna sebelum
   eksekusi -- tidak pernah langsung menghapus.
2. `--dry-run` sungguhan: tidak ada satu pun perubahan.
3. Tidak ada `rm -rf` pada path variabel tanpa pagar: fungsi `buang()` menolak
   path kosong, `/`, `$HOME`, path di luar HOME (kecuali whitelist), dan folder
   backup `~/openclaw-backup-*`.
4. sudo tidak pernah otomatis: item yang butuh root dilaporkan; dieksekusi
   hanya dengan `--sudo` setelah pengguna mengizinkan, dengan penjelasan.
5. `pgrep`/`pkill` mengecualikan rantai leluhur proses -- tidak membunuh
   terminal pemanggil.
6. Urutan cabut dijaga: Torang -> OpenClaw -> Hermes (Hermes pemilik
   node/npm di `~/.local/bin`).

## Referensi (`references/`)

- `peta-jejak-instalasi.md` -- peta lengkap semua jejak ketiga komponen.
- `pengetahuan-lapangan.md` -- akar masalah gagal pasang ulang + bug yang
  tidak boleh diulang.

## Kebutuhan

Ubuntu / WSL Ubuntu, bash, coreutils. `systemctl`, `docker`, `pipx`, `ss`,
`lsof` semuanya OPSIONAL -- skrip mendeteksi dan menurunkan kemampuan dengan
anggun (deteksi port punya jalur cadangan lewat `/proc/net/tcp`). `/reset`
butuh internet ke `openclaw.ai` dan `hermes-agent.nousresearch.com`.

## Catatan

- Jalankan di dalam WSL/mesin yang dituju; sisi Windows PC guru (portproxy,
  scheduled task) tidak terjangkau dari Ubuntu.
- Yang tak bisa dibersihkan dari dalam PC: bot Telegram murid (BotFather ->
  /deletebot), API key OpenAI (rotate dari dasbor), pairing basi di office
  guru.
