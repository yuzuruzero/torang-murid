# torang-installer — pemasang OpenClaw + Hermes

Pemasang satu pintu untuk **OpenClaw** dan **Hermes Agent**, dibuat untuk laptop
Windows milik pemula yang belum punya Linux. Jalan juga di macOS dan VPS Linux.

Ini **bukan** installer dari nol. Ini **orkestrator**: ia memeriksa prasyarat,
menjalankan installer **resmi** kedua produk dengan urutan yang benar, memverifikasi
hasilnya, lalu menawarkan pembatalan bersih kalau ada yang gagal di tengah.

Kembarannya ada di repo yang sama: [`openclaw-cleanup/`](../openclaw-cleanup) yang
mencabut sampai bersih. Yang ini memasang.

---

## Untuk siapa

- **Murid dan fasilitator kelas Torang** — ini jalur pemasangan resmi kelas.
- **Siapa pun** yang ingin memasang OpenClaw + Hermes di Windows tanpa harus paham
  WSL, BIOS, atau baris perintah.

Di Windows, semua instalasi terjadi **di dalam WSL (Ubuntu)**, bukan Windows langsung.
Itu disengaja: seluruh perkakas kelas kami (pemeriksa, pembersih, pemulih) berbasis
Ubuntu, dan instalasi sisi Windows tidak bisa diurus dari sana.

---

## CARA UTAMA — untuk murid

1. Di halaman depan repo ini, klik tombol hijau **Code** → **Download ZIP**
2. Ekstrak ZIP-nya
3. Masuk ke folder **`openclaw-installer`**
4. **Klik kanan `PASANG.bat` → Run as Administrator**
5. Kalau diminta **restart**: restart komputer, lalu jalankan **file yang sama** lagi
6. Ulangi sampai muncul tulisan **SELESAI**

Itu saja. Tidak ada perintah berbeda untuk komputer yang sudah punya Ubuntu dan yang
belum — skrip yang memeriksa sendiri dan memilih jalannya.

**Taruh foldernya di drive lokal** (mis. `C:\torang\`), bukan drive jaringan.

> Satu belokan yang perlu diketahui: di tengah jalan layar akan menyuruh menjalankan
> `PASANG.bat` lagi dengan **dobel-klik biasa**, bukan Run as Administrator. Itu
> disengaja — penjelasannya ada di [PANDUAN-PASANG.md](PANDUAN-PASANG.md).

---

## Cara alternatif — satu baris perintah

**Windows**, di PowerShell:

```powershell
irm https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/openclaw-installer/bootstrap.ps1 | iex
```

**Mac, VPS Linux, atau dari dalam Ubuntu WSL**, di Terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/openclaw-installer/pasang.sh)
```

Keduanya mengunduh berkas ke disk dulu (lengkap dengan catatan ukuran dan sidik jari
SHA-256), baru menjalankannya — bukan `curl | bash` buta.

Kalau jaringan sekolah memblokir `raw.githubusercontent.com`, kedua perintah ini akan
gagal. Itu bukan kerusakan — pakai cara ZIP di atas.

---

## Status kejujuran — BACA INI

**Versi 0.1.0. Sudah teruji di sandbox Linux, BELUM diuji di Windows, WSL, Mac, maupun
VPS sungguhan.**

| Sudah terbukti (sandbox Linux) | Belum diuji (butuh mesin nyata) |
|---|---|
| Sintaks semua skrip | Seluruh CEK 1–3 di Windows |
| `verifikasi.sh` jalan utuh, 9 kelompok | Pencegahan Ubuntu terpasang dua kali |
| Deteksi versi Node | Pembacaan daftar WSL di PowerShell 5.1 asli |
| Pra-cek berhenti tanpa mengubah apa pun | Panduan BIOS per merek laptop |
| Deteksi flag alat pencabut | Jalur rollback sungguhan |
| Aturan akhir baris (LF/CRLF) | macOS (bash 3.2) dan VPS |

Rincian per skenario, beserta apa yang harus dicatat saat menguji, ada di
[CARA-UJI-INSTALLER.md](CARA-UJI-INSTALLER.md).

Kalau kamu memakainya dan ada yang gagal: kirimkan `log-pasang.txt` dari folder
installer. Di dalamnya ada perintah yang dijalankan dan keluaran mentah installer
resmi — itu yang paling berguna untuk memperbaiki.

---

## Berkas di folder ini

| Berkas | Untuk apa |
|---|---|
| [PANDUAN-PASANG.md](PANDUAN-PASANG.md) | **Panduan pengguna.** Alur per platform, tabel masalah umum, panduan BIOS, jalur manual cadangan. |
| `PASANG.bat` | Pintu Windows. Ini yang diklik. |
| `pasang.ps1` | Otak sisi Windows: cek virtualisasi, fitur Windows, Ubuntu. |
| `pasang-inti.sh` | Otak pemasangan. Sama persis di WSL, Mac, dan VPS. |
| `pasang-mac.sh` | Pintu Mac. |
| `verifikasi.sh` | Pemeriksa. Read-only, aman dijalankan kapan saja. |
| `bootstrap.ps1` / `pasang.sh` | Pintu satu-baris. |
| [VERSI-TERUJI.md](VERSI-TERUJI.md) | Versi yang pernah dibuktikan jalan. |
| [RANCANGAN.md](RANCANGAN.md) | Rancangan teknis lengkap — untuk yang mengembangkan. |
| [CARA-UJI-INSTALLER.md](CARA-UJI-INSTALLER.md) | Rencana uji + status teruji/belum. |

---

## Setelah pemasangan selesai

Pemasang **sengaja tidak** menjalankan onboarding — keduanya interaktif dan meminta
kunci API atau login akun. Dua langkah terakhir kamu sendiri yang jalankan:

```bash
openclaw onboard     # pilih cara login; pasang gateway sebagai layanan -> YA
hermes setup         # pilih penyedia model; bingung? pilih Quick Setup (Nous Portal)
bash verifikasi.sh   # pastikan semuanya beres
```

---

## Yang dipasang, dan dari mana

| Produk | Installer resmi yang dipanggil |
|---|---|
| OpenClaw | `https://openclaw.ai/install.sh` — dokumentasi: <https://docs.openclaw.ai/install> |
| Hermes Agent | `https://hermes-agent.nousresearch.com/install.sh` — dokumentasi: <https://hermes-agent.nousresearch.com/docs/getting-started/installation> |

Urutannya **OpenClaw dulu, baru Hermes** — installer Hermes memasang Node privatnya
sendiri dan menautkan `~/.local/bin/{node,npm,npx}`, jadi ia harus jadi yang terakhir
masuk.

Kalau pemasangan gagal di tengah, rollback memakai
[`openclaw-cleanup/scripts/oc-uninstall.sh`](../openclaw-cleanup/scripts/oc-uninstall.sh)
yang sudah ada di repo ini, selalu dengan pagar `--sisakan-torang --sisakan-agenlain`
supaya monitor Torang dan agen lain tidak ikut tercabut.
