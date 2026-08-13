---
name: verify
description: >
  This skill should be used when the user asks to verify/check whether a system
  is clean of OpenClaw, Hermes, and Torang Event -- e.g. "/verify", "cek
  bersih", "sudah bersih belum", "verifikasi uninstall", "cek sisa openclaw",
  "siap pasang ulang?", "scan jejak openclaw/hermes/torang". Read-only scan of
  processes, systemd units (user & system), PATH binaries, packages,
  config/cache/log dirs, gateway ports, autostart/cron, and docker; reports
  clean/dirty per item.
metadata:
  version: "0.1.0"
---

# /verify -- Cek sistem benar-benar bersih

Jalankan pemindaian READ-ONLY dengan `scripts/oc-verify.sh` (turunan
`torang-cek-siap-pasang.sh` yang teruji di kelas). Skrip tidak mengubah apa
pun, jadi TIDAK perlu konfirmasi -- langsung jalankan.

## Lokasi skrip

Akar plugin = dua tingkat di atas direktori skill ini (`skills/verify/` ->
akar); atau `${CLAUDE_PLUGIN_ROOT}` kalau tersedia. Skrip:
`<akar>/scripts/oc-verify.sh`.

## Prosedur

1. Jalankan: `bash <akar>/scripts/oc-verify.sh`
2. Baca exit code: `0` = BERSIH, `2` = TIDAK BERSIH.
3. Laporkan ke pengguna per kelompok pemeriksaan (8 kelompok), ringkas:
   [1] proses hidup, [2] unit systemd user, [3] unit systemd sistem,
   [4] biner di PATH + paket npm/pnpm/bun/pipx/pip, [5] direktori
   config/cache/log/state (HOME, /etc, /var/log), [6] port gateway (18789 dan
   office guru 19000), [7] autostart/cron/file rc, [8] docker.
   Tunjukkan mana OK dan mana KOTOR; sertakan saran perbaikan (baris `->`)
   untuk tiap temuan kotor.
4. Interpretasi penting:
   - Temuan `~/.torang-guru` / `~/torang-office` = sisi GURU; uninstall tanpa
     `--guru` memang menyisakannya -- tanyakan apakah memang PC guru.
   - Port 18789 terpakai padahal tidak ada proses openclaw = proses yatim;
     inilah biang "gateway active tapi dashboard mati".
   - Baris bertanda `?` (mis. folder backup, systemd --user tidak aktif di
     WSL) = catatan, bukan temuan kotor.
   - `pgrep` di skrip sudah mengecualikan rantai leluhur & skrip plugin ini
     sendiri, jadi temuan proses adalah proses nyata.
5. Kalau TIDAK BERSIH: tawarkan `/uninstall` untuk menyapu (atau perbaikan
   tertarget sesuai baris saran). Kalau BERSIH: sampaikan sistem siap dipasang
   ulang; sarankan buka terminal baru (WSL: `wsl --shutdown`) sebelum
   memasang.

## Batasan

- Skrip memindai mesin tempat ia dijalankan. Di mesin dengan WSL, jalankan di
  DALAM WSL yang dimaksud -- distro WSL terdaftar per akun Windows, dan sisi
  Windows (portproxy, scheduled task, excluded port range) tidak terlihat dari
  Ubuntu.
- Jangan "memperbaiki" temuan langsung dari skill ini; perbaikan destruktif
  selalu lewat /uninstall dengan konfirmasinya sendiri.

Untuk latar belakang temuan (kenapa sisa lama berbahaya), baca
`<akar>/references/pengetahuan-lapangan.md`.
