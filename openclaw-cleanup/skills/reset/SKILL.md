---
name: reset
description: >
  This skill should be used when the user asks to reset OpenClaw and Hermes to
  a fresh-install state -- e.g. "/reset", "reset openclaw", "fresh install
  openclaw", "pasang ulang dari nol", "reset hermes", "install ulang bersih",
  "kembalikan ke kondisi awal". It backs up important config/credentials to
  ~/openclaw-backup-<date>, wipes state, reinstalls the latest OpenClaw +
  Hermes, and reports the backup location. Always dry-run + explicit user
  confirmation first.
metadata:
  version: "0.1.0"
---

# /reset -- Kembalikan OpenClaw + Hermes ke kondisi fresh install

Reset memakai skrip teruji `scripts/oc-reset.sh`: backup dulu, bersihkan
(lewat mesin oc-uninstall.sh), install ulang versi terbaru, setup awal.
Torang Event TIDAK ikut di-reset kecuali pengguna memintanya
(`--dengan-torang`).

## Lokasi skrip

Akar plugin = dua tingkat di atas direktori skill ini (`skills/reset/` ->
akar); atau `${CLAUDE_PLUGIN_ROOT}` kalau tersedia. Skrip:
`<akar>/scripts/oc-reset.sh` (butuh `oc-uninstall.sh` di folder yang sama).

## Prosedur WAJIB

1. **Cek prasyarat**: reset butuh internet (installer resmi openclaw.ai dan
   hermes-agent.nousresearch.com). Skrip memeriksa sendiri di Tahap 1 dan
   MENOLAK menghapus apa pun kalau installer tak terjangkau. Flag:
   - `--dengan-torang` ikut cabut monitor/plugin Torang
   - `--arsip` arsipkan workspace & sesi murid dulu
   - `--tanpa-install` backup + bersihkan saja (tanpa install ulang)
2. **Selalu dry-run dulu**: `bash <akar>/scripts/oc-reset.sh --dry-run [flag...]`
3. **Tampilkan rencana ke pengguna**, tiga bagian jelas:
   - APA YANG DI-BACKUP -> `~/openclaw-backup-<tanggal>/` (openclaw.json,
     credentials, identity, agents tanpa sessions, config Hermes, memories,
     client_id Torang, snapshot rc). Tegaskan: backup TIDAK ikut terhapus --
     mesin uninstall menolak menyentuh `~/openclaw-backup-*`.
   - APA YANG DIHAPUS (dari bagian dry-run mesin uninstall, termasuk baris
     `perlu --sudo`).
   - APA YANG DIINSTAL ULANG (OpenClaw + Hermes terbaru + `uv pip install -e
     ".[web,pty]"` + `openclaw gateway install --force`).
4. **Minta konfirmasi eksplisit** (AskUserQuestion kalau tersedia; kalau tidak,
   tanya teks dan tunggu). Tanpa konfirmasi -> JANGAN eksekusi. Sesi tak
   dijaga -> berhenti di rencana.
5. **Sudo per izin**: sama seperti /uninstall -- jelaskan item root (unit
   sistem, /etc, /usr/local, /var/log) dan minta izin sebelum menambah
   `--sudo`.
6. **Eksekusi**: `bash <akar>/scripts/oc-reset.sh -y [flag...]`. Perhatikan
   perilaku aman bawaan skrip:
   - backup gagal -> berhenti TOTAL, tidak ada yang dihapus (exit 1)
   - pembersihan menyisakan jejak -> install ulang DIBATALKAN (exit 2),
     karena memasang di atas sisa lama = sumber "gateway token mismatch" /
     dashboard mati. Bantu selesaikan sisa (biasanya `--sudo`), ulangi.
7. **Laporkan hasil**, WAJIB menyebut lokasi backup `~/openclaw-backup-<tanggal>`
   dan isi pentingnya (MANIFEST.txt). Ingatkan: `openclaw.json` lama berisi
   token gateway LAMA -- jangan di-restore mentah; ambil hanya nilai yang
   dibutuhkan (API key, bot token) supaya tidak kena token mismatch.
8. **Pandu setup lanjutan yang interaktif** (tak bisa diotomatiskan skrip):
   `openclaw onboard --auth-choice openai-api-key` (INSTALL GATEWAY SERVICE
   NOW -> YES, mode NODE), config Telegram (`channels.telegram.enabled`,
   `botToken`, `dmPolicy=pairing`) + `openclaw gateway restart`, lalu
   `openclaw pairing approve telegram <kode>`. Tawarkan menemani langkah demi
   langkah. Kalau monitor Torang dicabut (--dengan-torang), tawarkan installer
   torang-murid setelahnya.

## Aturan keamanan keras

- Backup SELALU sebelum penghapusan; kalau backup gagal, tidak boleh ada yang
  dihapus. Jangan pernah menghapus folder `~/openclaw-backup-*`.
- Jangan jalankan sebagai root; jangan rangkai `rm -rf` manual di luar skrip.
- Jangan lewati pemeriksaan exit 2 (sisa jejak) -- dilarang memaksa install
  di atas sisa lama.

## Fallback

Skrip hilang/rusak -> baca `<akar>/references/peta-jejak-instalasi.md` dan
`<akar>/references/pengetahuan-lapangan.md`, kerjakan manual dengan urutan yang
sama (backup -> bersih -> verifikasi bersih -> install), aturan keamanan sama.
