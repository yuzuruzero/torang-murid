# Pengetahuan lapangan -- pelajaran dari kelas Torang

Bug dan akar masalah NYATA yang pernah terjadi. Skrip plugin sudah
menghindarinya; kalau harus improvisasi manual, JANGAN mengulanginya.

## Tiga akar masalah "gagal pasang ulang"

Keluhan berulang: gateway error / token tak ke-generate / dashboard tak mau
terbuka setelah uninstall + install ulang. Bukan tiga masalah -- SATU akar:
sisa pasangan lama (docs.openclaw.ai/gateway/troubleshooting + issue #48008):

1. `~/.openclaw/openclaw.json` lama masih memegang `gateway.auth.token` lama,
   gateway baru memakai token lain -> `unauthorized: gateway token mismatch`.
   Tampak seperti "token tak mau ke-generate".
   Cek: `openclaw config get gateway.auth.token`.
2. Proses yatim masih memegang port 18789; `openclaw gateway stop` sering
   TIDAK membunuhnya -> gateway baru gagal bind (EADDRINUSE); systemd bilang
   `active` tapi dashboard mati. Cek: `lsof -i :18789` atau /proc/net/tcp.
3. Unit systemd lama menunjuk entrypoint versi lama (`dist/entry.js` vs
   `dist/index.js`). `openclaw doctor --fix` TIDAK memperbaikinya -- obatnya
   `openclaw gateway install --force`.

Perbaikan cepat tanpa cabut total:
`openclaw config get gateway.auth.token` -> `lsof -i :18789` ->
`openclaw gateway install --force` -> `openclaw gateway restart`.
Kalau bandel: cabut bersih (/uninstall) lalu pasang dari nol.

## Empat bug skrip yang tidak boleh diulang

1. `pgrep -f "openclaw"` ikut menemukan SHELL PEMANGGIL kalau baris perintahnya
   memuat kata itu -> skrip membunuh terminalnya sendiri. Solusi: kecualikan
   seluruh RANTAI LELUHUR proses (walk `/proc/<pid>/status` -> PPid), bukan
   cuma `$$`/`$PPID`.
2. `grep -v` keluar kode 1 kalau TIDAK ADA baris tersisa -- itu sukses, bukan
   gagal. Saat menyunting file rc, perlakukan rc<=1 sebagai aman.
3. `command -v -a` BUKAN opsi valid ("invalid option"). Untuk mendaftar SEMUA
   biner senama di PATH pakai `type -aP`. Bug ini membuat cek "biner masih di
   PATH" selalu lolos palsu.
4. Deteksi port jangan hanya mengandalkan `ss`/`lsof`/`fuser` -- di WSL polos
   bisa tak satu pun ada, lalu skrip melapor "port bebas" padahal terpakai.
   Baca `/proc/net/tcp` (st `0A` = LISTEN, port heksadesimal, kolom 10 =
   inode), petakan inode -> pid lewat `/proc/*/fd`.

## Kekhususan WSL & PC kelas

- systemd --user sering TIDAK aktif di WSL -- tangani anggun, tapi file unit
  tetap disapu (bisa bangkit saat systemd dinyalakan lewat /etc/wsl.conf).
- Distro WSL terdaftar PER AKUN WINDOWS (HKCU\...\Lxss). "OpenClaw hilang"
  setelah ganti akun Windows = home Linux yang berbeda, bukan hilang.
  Dua sesi login Windows bisa REBUTAN penerusan port 18789; uji pembeda:
  `curl -sI http://127.0.0.1:18789` DI DALAM WSL -- kalau jalan di WSL tapi
  tidak di browser Windows, itu masalah penerusan port, JANGAN pasang ulang.
- Setelah bersih-bersih: tutup semua terminal / `wsl --shutdown` supaya PATH
  dan proses benar-benar segar.
- CLI OpenClaw bisa sangat lambat di PC kelas (13-91 detik) -- beri timeout
  longgar, jangan polling CLI.
- Refresh token Codex/OpenAI DIROTASI sekali pakai: dua instalasi dengan satu
  akun OpenAI saling menjatuhkan sesi. Satu akun OpenAI per murid.

## Aturan keamanan penghapusan (fungsi buang())

- Tolak: path kosong, `/`, `$HOME` sendiri, `..`, `.`, dan SEMUA path di luar
  HOME kecuali di-whitelist eksplisit per pemanggilan.
- Folder `~/openclaw-backup-*` DILINDUNGI -- tidak boleh dihapus oleh mesin
  uninstall (dipakai /reset).
- Jangan jalan sebagai root; bagian root lewat `--sudo` per item, dengan
  penjelasan ke pengguna.
- Symlink `~/.local/bin/{node,npm,npx}`: hapus HANYA kalau menunjuk ke
  ~/.hermes atau menggantung. Node sistem/nvm milik user jangan disentuh.
