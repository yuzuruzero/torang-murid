# RANCANGAN — Installer-Orkestrator OpenClaw + Hermes

> Dokumen rancangan Fase 2. Ditulis 19 Agustus 2026.
> Belum ada satu baris kode pun ditulis — dokumen ini yang disetujui dulu.
> Semua keputusan arsitektur di tugas induk dianggap TERKUNCI dan tidak diubah di sini.

---

## 0. Ringkasan satu paragraf

Kita membuat **orkestrator**, bukan installer dari nol. Skrip kita memeriksa prasyarat,
mengunduh lalu menjalankan installer resmi OpenClaw dan Hermes, memverifikasi hasilnya,
dan menawarkan rollback bila gagal. Di Windows semua instalasi terjadi **di dalam WSL**,
supaya satu PC punya satu instalasi otoritatif yang bisa diurus perkakas
`openclaw-cleanup` kita yang berbasis Ubuntu. Pengguna Windows hanya perlu tahu satu hal:
klik kanan `PASANG.bat` → Run as Administrator, ulangi setelah restart sampai muncul
SELESAI.

---

## 1. Berkas yang akan dibuat (Fase 3)

Semua di folder `openclaw-installer/`. Tidak ada file lama yang disentuh.

| Berkas | Peran | EOL |
|---|---|---|
| `pasang-inti.sh` | **Otak.** Semua logika instal OpenClaw + Hermes. Dipakai identik oleh WSL, Mac, VPS. | LF |
| `PASANG.bat` | Pintu Windows: panggil `pasang.ps1`. | CRLF |
| `pasang.ps1` | Pintu Windows: CEK 0–4, penyiapan WSL, lalu panggil `pasang-inti.sh` di distro terpilih. | CRLF |
| `pasang-mac.sh` | Pintu Mac: prasyarat (Xcode CLT/Homebrew), lalu panggil inti. | LF |
| `verifikasi.sh` | Pemeriksa read-only pasca-instal. Dipanggil inti, bisa juga dijalankan sendiri. | LF |
| `pasang.sh` | Pintu satu-baris Mac/VPS/WSL: deteksi OS → unduh ke file → jalankan. | LF |
| `bootstrap.ps1` | Pintu satu-baris Windows: unduh ke `%LOCALAPPDATA%\torang-installer\` → jalankan. | CRLF |
| `README.md` | Halaman folder di GitHub. | — |
| `VERSI-TERUJI.md` | Catatan versi + **tanggal verifikasi dokumentasi resmi**. | — |
| `PANDUAN-PASANG.md` | Panduan pengguna. | — |
| `CARA-UJI-INSTALLER.md` | Rencana uji manual + status teruji/belum. | — |
| `log-pasang.txt` | Dibuat saat runtime, tidak ikut repo. | — |

Catatan EOL: repo `torang-murid` sudah punya `.gitattributes` yang memaksa
`*.sh` = LF dan `*.bat`/`*.ps1` = CRLF, jadi aturan ini terjaga otomatis saat commit.

VPS tidak punya berkas sendiri — VPS menjalankan `pasang-inti.sh` langsung.

---

## 2. Pintu WINDOWS — `PASANG.bat`

### 2.1 Diagram alur

```
                        ┌──────────────────────────────────┐
                        │ Klik kanan PASANG.bat            │
                        │ → Run as Administrator           │
                        └───────────────┬──────────────────┘
                                        │
                    ┌───────────────────▼───────────────────┐
                    │ CEK 0  Hak akses                      │
                    │ Belum elevated? → minta elevasi       │
                    │ sendiri (ShellExecute -Verb RunAs),   │
                    │ jendela lama tutup                    │
                    └───────────────────┬───────────────────┘
                                        │ elevated
                    ┌───────────────────▼───────────────────┐
                    │ Baca state.json + kondisi NYATA        │
                    │ Cocokkan nama user Windows             │
                    │   beda user? → BERHENTI, jelaskan      │
                    │   jebakan dua-akun                     │
                    └───────────────────┬───────────────────┘
                                        │
                    ┌───────────────────▼───────────────────┐
                    │ CEK 1  Virtualisasi CPU (butuh admin)  │
                    └───────┬───────────────────────┬───────┘
                            │ MATI                  │ HIDUP
              ┌─────────────▼──────────────┐        │
              │ Deteksi merek/model laptop │        │
              │ Tampilkan panduan BIOS     │        │
              │ Tulis penanda state.json   │        │
              │ BERHENTI — user ke BIOS    │        │
              │ lalu jalankan PASANG.bat   │        │
              │ lagi                       │        │
              └────────────────────────────┘        │
                                                    │
                    ┌───────────────────────────────▼───────┐
                    │ CEK 2  Fitur Windows (butuh admin)     │
                    │  FASE A (sebelum restart):             │
                    │   - Microsoft-Windows-Subsystem-Linux  │
                    │   - VirtualMachinePlatform             │
                    │   - wsl --install --no-distribution    │
                    │   - wsl --update                       │
                    │   - wsl --set-default-version 2        │
                    └───────┬───────────────────────┬───────┘
                            │ perlu restart          │ sudah aktif
              ┌─────────────▼──────────────┐        │
              │ Tulis state.json:          │        │
              │ tahap=fitur, perlu_restart │        │
              │ BERHENTI — user restart    │        │
              │ lalu jalankan lagi         │        │
              └────────────────────────────┘        │
                                                    │
              ╔═════════════════════════════════════▼═══════╗
              ║  TURUN HAK AKSES — lanjut sebagai USER ASLI  ║
              ║  (CEK 3 dst TIDAK BOLEH elevated: PowerShell ║
              ║   admin membaca daftar WSL akun lain)        ║
              ╚═════════════════════════════════════┬═══════╝
                                                    │
                    ┌───────────────────────────────▼───────┐
                    │ CEK 3  Distro Ubuntu (FASE B)          │
                    │ wsl --list --all --verbose             │
                    │ cari SEMUA entri mengandung "ubuntu"   │
                    ├────────────────────────────────────────┤
                    │ 0 entri  → pasang Ubuntu-24.04         │
                    │ 1 sehat  → PAKAI, set default, SELESAI │
                    │ 1 macet  → coba selesaikan penyiapan   │
                    │ 2+       → user MEMILIH satu           │
                    │ WSL1     → tawarkan --set-version 2    │
                    └───────────────────┬───────────────────┘
                                        │
                    ┌───────────────────▼───────────────────┐
                    │ CEK 3b Uji hidup distro                │
                    │  wsl -d X -- echo ok      → "ok"       │
                    │  wsl -d X -- id -un       → non-root   │
                    │  gagal → cocokkan tabel error WSL      │
                    │  (§9), tampilkan solusi, BERHENTI      │
                    └───────────────────┬───────────────────┘
                                        │ LULUS → state.json: distro selesai
                    ┌───────────────────▼───────────────────┐
                    │ CEK 4  Jaringan & disk                 │
                    │  openclaw.ai + hermes-agent... + 4 GB  │
                    └───────────────────┬───────────────────┘
                                        │
                    ┌───────────────────▼───────────────────┐
                    │ RINGKASAN status semua cek             │
                    │ (LULUS / DIPERBAIKI-OTOMATIS /         │
                    │  PERLU-TINDAKAN-USER)                  │
                    └───────────────────┬───────────────────┘
                                        │
                    ┌───────────────────▼───────────────────┐
                    │ wsl -d <distro-dari-state> --          │
                    │     bash pasang-inti.sh                │
                    │ (SELALU eksplisit -d)                  │
                    └───────────────────┬───────────────────┘
                                        │
                                   ┌────▼────┐
                                   │ SELESAI │
                                   └─────────┘
```

### 2.2 Rincian tiap cek

Setiap cek berakhir dengan salah satu status: **LULUS** / **DIPERBAIKI-OTOMATIS** /
**PERLU-TINDAKAN-USER**. Status ditulis ke `state.json` dan ke ringkasan akhir.

#### CEK 0 — Hak akses & identitas pengguna

- `PASANG.bat` memanggil `powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pasang.ps1"`.
- `pasang.ps1` memeriksa `WindowsPrincipal.IsInRole(Administrator)`. Belum elevated →
  jalankan ulang dirinya sendiri dengan `Start-Process -Verb RunAs`, lalu keluar.
- **Nama user Windows dicatat di `state.json` (`user_windows`).** Kalau `state.json` sudah
  ada dan `user_windows` berbeda dari `$env:USERNAME` sekarang → **BERHENTI**, tampilkan
  penjelasan jebakan dua-akun (rujuk `PANDUAN-DUA-AKUN-WINDOWS.md`) dan tawarkan dua
  pilihan: masuk ke akun yang tercatat, atau (sadar) memulai pemasangan baru di akun ini
  dengan mengganti nama file state — **tidak pernah lanjut diam-diam**.
- Elevasi hanya diperlukan CEK 1–2. Setelah CEK 2 selesai, skrip **turun hak akses**.

**Cara turun hak akses (rancangan, akan diuji di Fase 4):** proses elevated menulis
`state.json`, lalu menjalankan lanjutan sebagai user asli. Dua kandidat:
1. Proses elevated **berhenti** setelah CEK 2 dan menyuruh user menjalankan
   `PASANG.bat` lagi **tanpa** Run as Administrator (paling sederhana, paling jujur).
2. `runas /trustlevel:0x20000` dari proses elevated.

Rekomendasi: **pilihan 1**, dengan syarat `PASANG.bat` mendeteksi sendiri bahwa tahap
elevated sudah selesai dan **tidak lagi meminta elevasi** pada jalan berikutnya. Dengan
begitu prinsip satu-pintu tetap utuh: file yang sama, cara yang sama; skrip yang tahu
kapan butuh admin dan kapan tidak.

#### CEK 1 — Virtualisasi CPU

- Deteksi: `(Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled` dan
  `(Get-CimInstance Win32_ComputerSystem).HypervisorPresent`. Kalau `HypervisorPresent`
  = true, hypervisor sudah jalan → anggap LULUS meski
  `VirtualizationFirmwareEnabled` null (kasus umum saat Hyper-V sudah aktif).
  Cadangan: `systeminfo` baris "Virtualization Enabled In Firmware" /
  "Hyper-V Requirements".
- MATI → **tidak bisa diperbaiki skrip.** Ambil merek + model dari
  `Win32_ComputerSystem` (`Manufacturer`, `Model`), tampilkan panduan §10, tulis
  `state.json` (`bios_perlu_tindakan: true`), BERHENTI dengan status
  PERLU-TINDAKAN-USER.
- Pesan wajib menyebut **jalur utama Microsoft** (Settings → System → Recovery →
  Advanced startup) lebih dulu, baru tombol boot per merek — karena jalur Settings
  tidak bergantung pada timing tekan tombol dan berlaku di semua merek.

#### CEK 2 — Fitur Windows (FASE A)

Perintah, dijalankan elevated, masing-masing dicek dulu (idempoten):

```powershell
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
wsl --install --no-distribution      # aktifkan WSL TANPA memasang distro
wsl --update
wsl --set-default-version 2
```

**`--no-restart` wajib** supaya skrip yang mengatur restart, bukan DISM. Kalau salah satu
`Enable-WindowsOptionalFeature` mengembalikan `RestartNeeded`, tulis
`perlu_restart: true` ke `state.json` dan berhenti dengan satu instruksi saja:
"Restart komputer, lalu jalankan PASANG.bat lagi."

**LARANGAN:** jangan memakai `wsl --install` bentuk gabungan (yang sekaligus memasang
distro). Aktivasi fitur (Fase A) dan pemasangan distro (Fase B) **dipisah restart**.
`--no-distribution` adalah opsi resmi untuk itu.

Tambahan cek murah yang berguna: `bcdedit /enum | findstr -i hypervisorlaunchtype` —
kalau `Off`, jalankan `bcdedit /set hypervisorlaunchtype Auto` (butuh admin, jadi
tempatnya memang di Fase A) dan tandai perlu restart.

#### CEK 3 — Distro Ubuntu (FASE B, TANPA elevasi) — ANTI-DOBEL

Nama kanonik yang dipakai skrip: **`Ubuntu-24.04`**. Tidak pernah nama lain.

Urutan wajib **sebelum** memasang apa pun:

```powershell
wsl --list --all --verbose
```

Parse SEMUA baris; cocokkan `-imatch 'ubuntu'`; catat NAMA, STATE, VERSION apa adanya
(termasuk `Installing`, `Stopped`, `Running`, `Converting`).

> Catatan teknis parsing: keluaran `wsl.exe` adalah **UTF-16LE**. Di PowerShell 5.1 ini
> muncul sebagai teks dengan NUL di antara huruf kalau salah baca. Rancangan:
> set `[Console]::OutputEncoding = [System.Text.Encoding]::Unicode` sebelum memanggil
> `wsl.exe`, dan buang karakter NUL + CR dari hasil sebelum di-regex. Tanpa ini, deteksi
> "sudah ada Ubuntu" bisa gagal palsu → **dan gagal palsu di sini artinya Ubuntu dobel.**

| Kondisi | Tindakan |
|---|---|
| **a. 1 entri, sehat** | PAKAI. `wsl --set-default <nama>`. Catat di state.json. **JANGAN instal baru. JANGAN ubah konfigurasi apa pun.** |
| **b. 1 entri, macet** (`Installing`, atau gagal uji hidup) | Coba selesaikan penyiapannya dengan meluncurkannya (`wsl -d <nama>` interaktif → memicu pembuatan username/password). Masih gagal → diagnosa lewat tabel §9 + tampilkan opsi. Opsi `wsl --unregister` **hanya** untuk distro yang belum pernah diinisialisasi, **selalu** dengan konfirmasi eksplisit user, **tidak pernah otomatis**. |
| **c. 2+ entri** | Tampilkan daftar + status. User MEMILIH satu sebagai target. `wsl --set-default`, catat di state.json. **JANGAN hapus apa pun otomatis.** Boleh menampilkan cara `wsl --unregister` manual, disertai peringatan bahwa itu memusnahkan seluruh isi distro. |
| **d. 0 entri** | `wsl --install --distribution Ubuntu-24.04 --no-launch`, lalu luncurkan sekali untuk pembuatan user. Bila Microsoft Store bermasalah: ulangi dengan `--web-download`. |
| **e. Ada tapi WSL1** | Tawarkan `wsl --set-version <nama> 2`. Peringatkan: konversi bisa lama dan bisa gagal; sarankan backup. Tidak pernah otomatis. |

**Pendampingan pembuatan user Linux (kasus d).** Tampilkan di layar SEBELUM jendela
Ubuntu muncul:

- Ubuntu akan minta username dan password Linux — ini **bukan** password Windows.
- **Password tidak terlihat saat diketik.** Layar tidak bergerak. Itu normal, bukan
  keyboard rusak.
- Username huruf kecil semua, tanpa spasi.
- Ingat password-nya: dipakai untuk `sudo`.

#### CEK 3b — Kesehatan distro (DEFINISI SELESAI)

```powershell
wsl -d Ubuntu-24.04 -- echo ok          # harus mengembalikan tepat "ok"
wsl -d Ubuntu-24.04 -- id -un           # harus mengembalikan user NON-ROOT
```

Kedua uji harus lulus. Uji kedua wajib karena distro yang belum diinisialisasi bisa
menjawab `echo ok` sebagai root, padahal user Linux belum pernah dibuat — dan seluruh
instalasi kita mengandaikan user biasa (skrip `oc-*` menolak root).

**Sebelum kedua uji ini lulus, `state.json` TIDAK BOLEH menandai tahap distro selesai.**

Gagal → tangkap kode error, cocokkan dengan tabel §9, tampilkan solusi berbahasa awam.
**JANGAN pernah reset/hapus distro otomatis.**

#### CEK 4 — Jaringan & disk

- Jaringan: `Test-NetConnection openclaw.ai -Port 443` dan
  `hermes-agent.nousresearch.com -Port 443` (atau `Invoke-WebRequest -Method Head`).
  Gagal → pesan menyebut kemungkinan proxy sekolah/firewall, dan bahwa instalasi
  **tidak akan dimulai** (lebih baik gagal di depan daripada separuh jalan).
- Disk: ruang kosong drive sistem **minimal 4 GB**. Alasan angka: OpenClaw + Hermes +
  Chromium Playwright ≈ 3 GB terukur di lapangan (`torang-cek-siap-pasang.sh`), + 1 GB
  margin untuk VHDX WSL yang tumbuh.
- Catatan: kurang dari 4 GB → PERLU-TINDAKAN-USER, bukan peringatan yang bisa dilewati.

### 2.3 Semua titik restart-dan-lanjut

| Titik | Pemicu | Yang ditulis ke state.json | Kalimat ke user |
|---|---|---|---|
| R1 | Virtualisasi CPU mati | `bios_perlu_tindakan: true`, `tahap: "bios"` | "Restart, masuk BIOS, aktifkan virtualisasi, lalu jalankan PASANG.bat lagi." |
| R2 | `Enable-WindowsOptionalFeature` minta restart | `tahap: "fitur"`, `perlu_restart: true` | "Restart komputer, lalu jalankan PASANG.bat lagi." |
| R3 | `wsl --update` / kernel baru terpasang | `tahap: "fitur"`, `perlu_restart: true` | sama seperti R2 |
| R4 | Selesai tahap elevated, lanjutan harus non-elevated | `tahap: "distro"`, `butuh_elevasi: false` | "Jalankan PASANG.bat lagi — kali ini **tanpa** Run as Administrator." |

Pada tiap titik, jalan berikutnya membaca `state.json` **dan kondisi nyata**, lalu
melanjutkan dari cek berikutnya. Kondisi nyata selalu menang: kalau state.json bilang
"fitur selesai" tapi `Get-WindowsOptionalFeature` bilang Disabled, skrip mengerjakan
ulang fitur.

---

## 3. Pintu MAC — `pasang-mac.sh`

```
bash pasang-mac.sh
   │
   ├─ 1. Cek macOS + arsitektur (arm64/x86_64), catat ke log
   ├─ 2. Cek Command Line Tools (xcode-select -p); belum ada →
   │     tampilkan `xcode-select --install`, BERHENTI (butuh klik user)
   ├─ 3. Cek git & curl (biasanya dari CLT)
   ├─ 4. Homebrew: cek `brew --version`.
   │     Tidak ada → JANGAN pasang diam-diam. Tampilkan perintah resmi
   │     Homebrew + tanya y/ya. Installer OpenClaw memang memasang Homebrew
   │     sendiri bila butuh Node/Git, jadi Homebrew di sini opsional.
   ├─ 5. Cek jaringan (openclaw.ai, hermes-agent.nousresearch.com) + disk 4 GB
   └─ 6. bash pasang-inti.sh   ← otak yang sama
```

Catatan Mac: layanan latar belakang OpenClaw memakai **LaunchAgent**, bukan systemd.
`verifikasi.sh` harus mengenali keduanya (lihat §7).

---

## 4. Pintu VPS

Tidak ada berkas khusus. Di server Linux:

```bash
bash pasang-inti.sh
```

`pasang-inti.sh` mendeteksi sendiri bahwa ia bukan di WSL dan bukan di Mac
(`/proc/sys/kernel/osrelease` tidak memuat `microsoft`; `uname -s` = Linux), lalu:

- Tetap menolak root (konsisten dengan `oc-*`). Di VPS yang hanya punya root, pesan
  jelas: buat user biasa dulu (`adduser`), atau jalankan dengan sadar sebagai user
  layanan.
- Melewati semua hal khusus WSL (cek interop `/mnt/`, `wsl.conf`).
- Menyarankan `sudo loginctl enable-linger <user>` bila gateway harus hidup setelah
  logout (dari dokumentasi Hermes).

---

## 5. `pasang-inti.sh` — daftar fungsi & urutan eksekusi

### 5.1 Urutan eksekusi

```
 0. pra_cek()            lingkungan, root, HOME, tty, jaringan, disk
 1. potret_awal()        verifikasi.sh --potret  → apa yang sudah ada?
 2. pasang_openclaw()    unduh install.sh ke file → catat → jalankan
 3. verifikasi_openclaw()  WAJIB LULUS sebelum lanjut
 4. pasang_hermes()      unduh install.sh ke file → catat → jalankan
 5. hash -r + verifikasi_openclaw() ULANG   ← anti-pembajakan npm oleh Hermes
 6. migrasi_claw()       hanya bila ~/.openclaw berisi data lama; BEST-EFFORT
 7. verifikasi_akhir()   verifikasi.sh penuh
 8. laporan()            ringkasan + blok "LANGKAH BERIKUTNYA"
```

Langkah 3 dan 5 adalah **dua verifikasi OpenClaw yang berbeda**, keduanya wajib ada.
Alasan: installer Hermes memasang Node privat di `~/.hermes/node` dan menautkan
`~/.local/bin/{node,npm,npx}` ke sana, serta bisa menulis prefix npm ke `~/.npmrc`.
Kalau OpenClaw rusak akibat itu, kita harus tahu **saat itu juga**, bukan nanti di kelas.

### 5.2 Daftar fungsi

| Fungsi | Isi | Gagal → |
|---|---|---|
| `say()` / `judul()` / `warn()` | keluaran ke layar **dan** `log-pasang.txt`. Tidak memakai `tee -a … >/dev/null` (pelajaran no. 8). | — |
| `ada()` | `command -v "$1" >/dev/null 2>&1` | — |
| `tanya()` | prompt y/ya, **strip CR**, huruf kecil-besar bebas. | batal, exit 1 |
| `pra_cek()` | HOME ada & folder; **tolak root**; tolak non-tty tanpa `-y`; curl ada; disk ≥ 4 GB; dua host terjangkau. | exit 1, **belum ada yang diubah** |
| `deteksi_lingkungan()` | WSL / Mac / Linux biasa; distro; arsitektur; versi npm; ada tidaknya systemd user. | — |
| `unduh_installer()` | `curl -fsSL --proto '=https' --tlsv1.2 <url> -o <file>`; catat URL, ukuran, dan **SHA-256** ke log; **baru** dieksekusi. Tidak pernah `curl \| bash`. | exit 1 |
| `potret_awal()` | jalankan `verifikasi.sh --potret`; simpan hasil ke log sebagai pembanding. Sudah lengkap terpasang → tawarkan berhenti dini. | — |
| `pasang_openclaw()` | `bash <file-installer> --no-onboard --no-prompt --verify` (onboarding TIDAK di dalam skrip). Bila `PIN_OPENCLAW` diisi → jalur npm (§8). | tawarkan rollback |
| `verifikasi_openclaw()` | `openclaw --version` (timeout longgar), `openclaw doctor`, biner **tidak** ber-path `/mnt/`. | tawarkan rollback |
| `pasang_hermes()` | `bash <file-installer>` apa adanya. Opsi `--skip-browser` bila `TORANG_TANPA_BROWSER=1` (menghemat ~1 GB Chromium di PC kelas). | tawarkan rollback |
| `verifikasi_hermes()` | `hermes version`, `hermes doctor`. | tawarkan rollback |
| `migrasi_claw()` | **Best-effort.** Jalan hanya bila `~/.openclaw` berisi data lama. `hermes claw migrate`. Gagal / perintah tak dikenal → **peringatan saja**, instalasi tetap dianggap sukses. | peringatan, lanjut |
| `rollback()` | Panggil `oc-uninstall.sh -y --sisakan-torang --sisakan-agenlain`. **Tidak menulis ulang logika cabut.** | — |
| `laporan()` | ringkasan + blok LANGKAH BERIKUTNYA. | — |

### 5.3 Rincian yang mudah salah

**`unduh_installer()` — kenapa tidak `curl | bash`.** Kalau installer resmi gagal di
tengah, dengan pipe kita tidak punya apa pun untuk diperiksa. Dengan file: URL, ukuran,
SHA-256, dan isi skrip ada di disk; log menunjuk ke sana. Ini juga yang membuat laporan
masalah dari lapangan bisa didiagnosis tanpa mengulang instalasi.

**`migrasi_claw()` — kapan dijalankan.** Syaratnya `~/.openclaw` ada DAN memuat minimal
salah satu dari `openclaw.json`, `credentials/`, `agents/`. Pada instalasi baru yang
bersih, folder itu memang baru dibuat installer beberapa menit lalu dan isinya minimal —
jadi kondisinya tidak terpenuhi dan migrasi dilewati dengan tenang. Perilaku ini belum
pernah diuji di mesin nyata (lihat §14).

**Onboarding TIDAK di dalam skrip** (keputusan d.4). Setelah verifikasi lulus,
`pasang-inti.sh` berhenti dan menampilkan:

```
=== LANGKAH BERIKUTNYA (dikerjakan sendiri, tidak bisa otomatis) ===

1. openclaw onboard
   Akan menanyakan: cara login (API key OpenAI / langganan), lalu
   apakah gateway dipasang sebagai layanan — jawab YA.

2. hermes setup
   Akan menanyakan: penyedia model dan kunci/akun. Kalau bingung,
   pilih Quick Setup (Nous Portal).

Setelah keduanya selesai, jalankan lagi:  bash verifikasi.sh
```

---

## 6. Struktur `state.json`

Lokasi: `%LOCALAPPDATA%\torang-installer\state.json` (hanya dipakai pintu Windows).

```json
{
  "versi_state": 1,
  "versi_installer": "1.0",
  "user_windows": "Admin",
  "komputer": "KELAS-PC-03",
  "dibuat": "2026-08-19T14:03:11+07:00",
  "diperbarui": "2026-08-19T14:41:52+07:00",

  "tahap": "distro",
  "perlu_restart": false,
  "butuh_elevasi": false,

  "cek": {
    "cek0_hak_akses":  { "status": "LULUS",                "waktu": "2026-08-19T14:03:11+07:00" },
    "cek1_virtualisasi": { "status": "LULUS",              "waktu": "2026-08-19T14:03:14+07:00",
                           "merek": "ASUSTeK COMPUTER INC.", "model": "X441UA" },
    "cek2_fitur":      { "status": "DIPERBAIKI-OTOMATIS",  "waktu": "2026-08-19T14:05:02+07:00",
                           "wsl_feature": true, "vmp_feature": true,
                           "default_version": 2, "restart_diminta": true },
    "cek3_distro":     { "status": "LULUS",                "waktu": "2026-08-19T14:38:20+07:00",
                           "distro_terpilih": "Ubuntu-24.04",
                           "distro_terlihat": ["Ubuntu-24.04"],
                           "dipasang_oleh_kami": true },
    "cek3b_kesehatan": { "status": "LULUS",                "waktu": "2026-08-19T14:40:03+07:00",
                           "echo_ok": true, "user_linux": "murid" },
    "cek4_jaringan_disk": { "status": "LULUS",             "waktu": "2026-08-19T14:41:52+07:00",
                           "disk_bebas_mb": 41230,
                           "openclaw_ai": true, "hermes_host": true }
  },

  "bios_perlu_tindakan": false,
  "catatan_terakhir": "Distro sehat. Siap menjalankan pasang-inti.sh."
}
```

Aturan pemakaian:

1. **Kondisi nyata selalu menang.** `state.json` mempercepat, tidak memutuskan.
2. `distro_terpilih` **wajib** dipakai sebagai argumen `-d`. Tidak pernah mengandalkan
   distro default.
3. `dipasang_oleh_kami` menentukan apakah rollback boleh menawarkan `wsl --unregister`
   sama sekali. Kalau `false`, opsi itu tidak pernah ditampilkan.
4. `user_windows` beda → berhenti (§2.2 CEK 0).
5. File ditulis **atomik**: tulis ke `state.json.baru`, lalu ganti nama. State setengah
   tertulis lebih berbahaya daripada tidak ada state.
6. `versi_state` supaya versi installer berikutnya bisa membaca/mengabaikan state lama
   dengan sadar.

---

## 7. `verifikasi.sh` — daftar pemeriksaan

Diturunkan dari `oc-verify.sh` (yang memeriksa **kebersihan**); versi kita memeriksa
**keterpasangan**. Read-only, tidak pernah mengubah apa pun. Exit `0` = lengkap,
`2` = ada yang kurang.

| # | Kelompok | Yang diperiksa | Sumber logika |
|---|---|---|---|
| 1 | **Biner & PATH** | `openclaw` dan `hermes` ada. `type -aP` (BUKAN `command -v -a`). **Menolak biner ber-path `/mnt/`** — itu instalasi sisi Windows, bukan milik kita; tampilkan obat `cmd.exe /c "npm rm -g openclaw"`. | `oc-verify.sh` [4] |
| 2 | **Versi** | `openclaw --version`, `hermes version`. Bandingkan dengan `VERSI-TERUJI.md`. Beda → **PERINGATAN, bukan gagal**. | keputusan #5 |
| 3 | **Node** | `node -v` memenuhi 22.22.3+ / 24.15+ / 25.9+. Node 23 = tidak didukung. Catat node mana yang menang di PATH (sistem vs `~/.hermes/node`). | docs OpenClaw |
| 4 | **Konfigurasi** | `~/.openclaw/openclaw.json` ada & JSON valid. `~/.hermes/config.yaml` ada. `~/.hermes/.env` ada (boleh kosong). | peta-jejak + docs Hermes |
| 5 | **Layanan** | Linux/WSL: unit `openclaw-gateway.service` di `~/.config/systemd/user/`. Mac: LaunchAgent `ai.openclaw.gateway`. `systemd --user` mati di WSL → **catatan, bukan gagal**. | peta-jejak, docs uninstall |
| 6 | **Port gateway** | 18789: siapa yang memegang, lewat `/proc/net/tcp` (`ss`/`lsof`/`fuser` belum tentu ada). Sebelum onboarding, port bebas itu **wajar** — laporkan sebagai info. | pelajaran no. 7 |
| 7 | **Doctor bawaan** | `openclaw doctor` dan `hermes doctor`. Keluarannya disalin ke log apa adanya. Timeout longgar (CLI bisa 13–91 detik di PC kelas). | docs + pengetahuan-lapangan |
| 8 | **Kewarasan pasca-Hermes** | `~/.local/bin/{node,npm,npx}` menunjuk ke mana; `~/.npmrc` memuat prefix apa; tidak ada symlink menggantung (`[ -L ] && [ ! -e ]`). | peta-jejak, pelajaran no. 3 |
| 9 | **Torang (opsional)** | Hanya bila `--dengan-torang`: `~/.torang/`, `~/.torang-monitor/client_id`. | peta-jejak |

Mode:

- `verifikasi.sh` — laporan penuh
- `verifikasi.sh --potret` — ringkas, dipakai `pasang-inti.sh` di langkah 1
- `verifikasi.sh --openclaw-saja` — dipakai di langkah 3 dan 5

---

## 8. Usulan mekanisme pin versi per produk

### 8.1 OpenClaw — pin NYATA lewat npm

Installer resmi mendukung pin langsung, jadi kita tidak menulis ulang apa pun:

```bash
bash install.sh --version <versi> --no-onboard --no-prompt --verify
# atau: OPENCLAW_VERSION=<versi> bash install.sh --no-onboard --no-prompt
```

**Jebakan npm yang wajib ditangani.** Sejak npm 11.16, npm memblokir lifecycle script
paket yang tidak disetujui. Bentuk perintah berbeda per versi npm:

| Versi npm | Bentuk perintah |
|---|---|
| ≤ 11.15 | `npm install -g openclaw@<versi>` — **tanpa** flag |
| ≥ 11.16 (termasuk 12) | `npm install -g openclaw@<versi> --allow-scripts=openclaw` |

Deteksi: `npm --version` → bandingkan mayor.minor. **Versi npm tidak terbaca → berhenti,
jangan menebak** (installer resmi pun berhenti di titik yang sama). `npm approve-scripts
openclaw` TIDAK bekerja untuk instalasi global — jangan disarankan.

Catatan: `openclaw@main` bukan target `--version` yang sah untuk npm; untuk kode dari
git harus `--install-method git --version main`. Kita tidak memakai jalur itu.

### 8.2 Hermes — deteksi + catat + peringatkan (keputusan d.3)

Hermes dipasang sebagai **git checkout**, bukan paket npm. Installer resminya tidak punya
flag versi. Pin sungguhan berarti kita mengerjakan sendiri
`git checkout <tag> && uv pip install -e ".[all]"` — itu mereplikasi logika installer
resmi (melanggar keputusan #1) dan mudah patah karena Hermes bergerak cepat.

Maka:

- Setelah instalasi, catat `hermes version` dan commit hash yang muncul di sana ke
  `log-pasang.txt`.
- Bandingkan dengan `VERSI-TERUJI.md`. Beda → **PERINGATAN** dengan kalimat jelas:
  "Versi Hermes di PC ini berbeda dari versi yang pernah kami uji. Biasanya tidak
  masalah. Kalau ada yang aneh, catat versi ini saat melapor."
- **Tidak pernah** menurunkan/menaikkan versi otomatis.

Jalur pin manual tetap didokumentasikan di `PANDUAN-PASANG.md` sebagai cadangan darurat
(`git checkout vX.Y.Z` + `uv pip install -e ".[all]"`), lengkap dengan peringatan
dokumentasi resmi bahwa rollback bisa menimbulkan config yang tidak dikenali
(`hermes config check`).

### 8.3 `VERSI-TERUJI.md`

Kolom wajib: produk · versi teruji · **tanggal versi itu diuji** · **tanggal dokumentasi
resmi terakhir dicocokkan** · catatan. Kolom terakhir yang paling sering terlupa, padahal
riset Fase 1 menemukan 6 selisih hanya dalam ~4 minggu.

---

## 9. Tabel error WSL umum

Sumber: halaman troubleshooting resmi Microsoft (lihat §16). Kolom "solusi" adalah
ringkasan berbahasa awam dari instruksi Microsoft, bukan terjemahan harfiah.

| Kode / pesan | Penyebab menurut Microsoft | Yang dilakukan skrip / dikatakan ke user |
|---|---|---|
| **0x80370102** — "The virtual machine could not be started because a required feature is not installed." | Virtual Machine Platform belum aktif, atau **virtualisasi mati di BIOS**. Bisa juga: hypervisorlaunchtype Off, hypervisor pihak ketiga (VMware <15.5.5 / VirtualBox <6), VM bersarang, Azure Trusted Launch. | Ini yang paling sering di laptop pemula. Skrip: pastikan VirtualMachinePlatform aktif → cek `bcdedit /enum \| findstr -i hypervisorlaunchtype`, kalau `Off` set `Auto` → kalau tetap gagal, tampilkan panduan BIOS §10. |
| **0x80370102 + 0x80070003** (saat instal) | CPU tidak mendukung **SLAT**. "Older CPUs (such as the Intel Core 2 Duo) will not be able to run WSL2, even if the Virtual Machine Platform is successfully installed." | Kalau merek/model laptop sangat tua: katakan jujur bahwa PC ini tidak bisa menjalankan WSL2, dan hentikan. Jangan menyuruh user bolak-balik ke BIOS untuk sesuatu yang tidak bisa diperbaiki. |
| **0x80070003** (Installation failed) | "The Windows Subsystem for Linux only runs on your system drive (usually this is your `C:` drive)." | Cek "Where new content is saved" di Settings → Storage; distro harus di drive sistem. |
| **0x8007019e** — WslRegisterDistribution failed | Komponen opsional Windows Subsystem for Linux **belum aktif**. | Ini berarti CEK 2 belum tuntas. Skrip kembali ke Fase A, aktifkan fitur, minta restart. |
| **0x80040154** (setelah Windows Update) | "The Windows Subsystem for Linux feature may be disabled during a Windows update." | Aktifkan ulang fitur WSL. Jalankan `PASANG.bat` lagi — CEK 2 idempoten, akan memperbaiki sendiri. |
| **0x8000FFFF** — unexpected failure | Kegagalan "katastrofik" umum; banyak sebab. | Urutan yang disarankan Microsoft: pastikan user yang benar → `wsl --update` → `wsl --shutdown` → `SFC /SCANNOW` → `DISM /Online /Cleanup-Image /RestoreHealth`. Skrip menampilkan urutan ini, **tidak** menjalankannya sendiri (SFC/DISM lama dan berisiko membingungkan). |
| **0x1bc** (saat `wsl --set-default-version 2`) | "This may happen when 'Display Language' or 'System Locale' setting is not English." Arti sebenarnya: kernel WSL2 perlu di-update. | Jalankan `wsl --update`. Ini kasus khas PC Indonesia — pesan aslinya menyesatkan. |
| **"WSL 2 requires an update to its kernel component"** | Paket kernel hilang dari `%SystemRoot%\system32\lxss\tools`. | `wsl --update`. Kalau tetap gagal: uninstall lalu install ulang MSI kernel dari Add/Remove Programs. |
| **"This update only applies to machines with the Windows Subsystem for Linux."** | WSL belum aktif, atau sudah diaktifkan **tapi belum restart**. | Skrip: pastikan Fase A selesai, lalu minta restart (R2). |
| **"The referenced assembly could not be found."** (saat mengaktifkan fitur) | "This error is related to being in a bad install state." | Coba lewat GUI "Turn Windows features on or off"; lalu Windows Update. Kalau tetap gagal, Microsoft menyarankan reinstall Windows "Keep Everything" — skrip **hanya menyampaikan**, tidak melakukan apa pun. |
| **"There are no more endpoints available from the endpoint mapper."** | Layanan **Internet Connection Sharing (ICS / SharedAccess)** dimatikan — sering oleh Group Policy di komputer sekolah/kantor. ICS adalah komponen wajib WSL2. | Kembalikan layanan SharedAccess ke Manual (Trigger Start). Sebutkan bahwa ini biasanya kebijakan admin, bukan kerusakan. |
| **"The requested operation could not be completed due to a virtual disk system limitation…"** | Folder `LocalState` distro dikompresi/dienkripsi NTFS. | Properties → Advanced → hilangkan centang "Compress contents" dan "Encrypt contents", pilih "just this folder". Setelah itu `wsl --set-version` bisa jalan. |
| **`Invalid command line option: wsl --set-version …`** | WSL belum aktif, atau Windows build < 18362. | Aktifkan fitur WSL; kalau build terlalu tua, PC ini tidak bisa WSL2 — katakan jujur. |
| **`'wsl' is not recognized…`** | Komponen opsional belum terpasang; atau proses 32-bit memanggil tool 64-bit. | Aktifkan fitur; jalankan dari PowerShell/CMD (bukan PowerShell ISE ARM64); jalur alternatif `C:\Windows\Sysnative\wsl.exe`. |
| **"Windows Subsystem for Linux has no installed distributions."** | Tiga sebab; salah satunya: **"you aren't accidentally running the built-in Administrator account… This is a separate user account and will not show any installed WSL distributions by design."** | **Ini persis insiden 2 Agu kita.** Skrip: tampilkan nama akun yang sedang dipakai + isi `user_windows` di state.json, dan rujuk §CEK 0. |
| **0x800701bc** (dilaporkan luas di forum, tidak ada di halaman resmi MS) | Paket kernel WSL2 usang/tidak cocok. | `wsl --update`; kalau gagal, pasang paket kernel WSL2 manual. Ditandai di panduan sebagai **sumber non-resmi**. |

**Yang TIDAK ada di halaman resmi Microsoft** (jangan mengaku bersumber dari sana):
"Element not found", "Insufficient system resources", `dism.exe /online /enable-feature`,
dan penanganan **disk penuh** — halaman troubleshooting WSL tidak membahas kehabisan
ruang disk sama sekali. Karena itu CEK 4 kita adalah pencegahan buatan sendiri, bukan
kutipan Microsoft.

**Catatan penyalinan:** di satu tempat halaman Microsoft menulis `wsl.exe –shutdown`
dengan **en-dash**, bukan dua tanda hubung. Bentuk yang benar: `wsl --shutdown`. Jangan
menyalin mentah dari halaman itu ke dalam skrip.

---

## 10. Panduan BIOS per merek laptop

### 10.1 Jalur UTAMA — sama untuk semua merek (tampilkan ini dulu)

Microsoft menyediakan jalur masuk UEFI dari dalam Windows. Ini **lebih andal** daripada
menekan tombol saat boot, karena tidak bergantung pada timing dan tidak terganggu Fast
Startup:

1. **Settings → System → Recovery** (Windows 10: Update & Security → Recovery)
2. Di **Advanced startup**, klik **Restart now**
3. **Troubleshoot → Advanced options → UEFI Firmware Settings → Restart**
4. Komputer masuk BIOS/UEFI sendiri

Kalau menu **UEFI Firmware Settings** tidak muncul, komputer memakai BIOS lama
(bukan UEFI) → pakai tombol boot di tabel bawah.

### 10.2 Tombol boot & nama menu per merek

Tombol ditekan berulang segera setelah komputer dinyalakan, sebelum logo Windows.

| Merek | Tombol BIOS/UEFI | Tombol boot menu | Lokasi & nama setelan virtualisasi (khas) |
|---|---|---|---|
| **ASUS** | `F2` (tahan saat menyalakan), sebagian model `Del` | `Esc` | Advanced → CPU Configuration → **Intel Virtualization Technology** · AMD: **SVM Mode**. Model notebook sering perlu Advanced Mode (`F7`) dulu. |
| **Acer** | `F2` | `F12` | Main atau Advanced → **Intel(R) Virtualization Technology** / **VT-d**. Sebagian model perlu set Supervisor Password dulu agar menu bisa diubah. |
| **Lenovo** | `F1` (ThinkPad), `F2` atau tombol **Novo** kecil di sisi bodi (IdeaPad) | `F12` | Security → Virtualization → **Intel Virtualization Technology** (+ **VT-d**), atau Configuration → **Intel Virtual Technology**. |
| **HP** | `F10` | `F9` | Security atau System Configuration → **Virtualization Technology (VTx)** / **VTx/VTd**. |
| **Dell** | `F2` | `F12` | Virtualization Support → **Virtualization** (centang "Enable Intel Virtualization Technology"). BIOS baru: Advanced → Virtualization. |
| **MSI** | `Del` | `F11` | OC / Overclocking → CPU Features → **SVM Mode** (AMD) atau **Intel Virtualization Tech / VT-d** (Intel). |

Setelah diaktifkan: **F10 = Save & Exit** di hampir semua merek.

### 10.3 Kalau setelannya tidak ada sama sekali

Tiga kemungkinan, sampaikan apa adanya: BIOS dikunci oleh pabrikan/admin IT, CPU-nya
memang tidak mendukung, atau BIOS perlu di-update. **Skrip tidak menawarkan solusi
yang tidak ada** — arahkan ke halaman resmi merek (tautan ada di `PANDUAN-PASANG.md`,
diambil dari halaman Microsoft "Enable virtualization on Windows").

---

## 11. Titik kegagalan & perilaku skrip saat gagal

Prinsip: **gagal di depan lebih baik daripada gagal di tengah.** Semua yang bisa dicek
sebelum ada perubahan, dicek dulu.

| # | Titik gagal | Sudah ada yang berubah? | Perilaku skrip |
|---|---|---|---|
| F1 | Virtualisasi mati | Tidak | Panduan BIOS §10 + state.json + BERHENTI. Tidak ada rollback (belum ada yang dipasang). |
| F2 | `Enable-WindowsOptionalFeature` gagal | Mungkin sebagian | Tampilkan kode error → cocokkan §9. Jangan mengulang membabi buta. Sarankan restart lalu jalankan lagi. |
| F3 | Distro macet / gagal uji hidup | Distro mungkin sudah terpasang | Diagnosa §9. **Tidak pernah unregister otomatis.** Tawarkan opsi manual dengan peringatan keras kalau distro belum pernah dipakai. |
| F4 | Jaringan/disk gagal (CEK 4) | Tidak | BERHENTI dengan pesan jelas. Belum ada satu paket pun diunduh. |
| F5 | Unduh installer resmi gagal | Tidak | BERHENTI. Log memuat URL dan pesan curl. Sarankan cek proxy sekolah. |
| F6 | Installer OpenClaw error | **Ya** | Tampilkan 30 baris terakhir log installer → tawarkan **rollback**: `oc-uninstall.sh -y --sisakan-torang --sisakan-agenlain`. Jawab tidak → jelaskan sistem dalam keadaan setengah jadi dan apa artinya. Tidak pernah diam. |
| F7 | Verifikasi OpenClaw gagal (langkah 3) | Ya | Sama seperti F6. **Hermes tidak pernah dipasang di atas OpenClaw yang belum terbukti sehat.** |
| F8 | Installer Hermes error | Ya (OpenClaw sudah sehat) | Tawarkan dua pilihan: (a) rollback keduanya, (b) **berhenti di sini** dengan OpenClaw saja yang terpasang — jelaskan bahwa itu keadaan yang sah dan Hermes bisa dipasang lagi nanti. |
| F9 | Verifikasi ulang OpenClaw gagal SETELAH Hermes (langkah 5) | Ya | Kasus pembajakan npm. Tampilkan hasil pemeriksaan §7 no. 8 (symlink & npmrc) — di situlah jawabannya. Tawarkan rollback. |
| F10 | `hermes claw migrate` gagal | Tidak (best-effort) | **Peringatan saja.** Instalasi tetap SUKSES. Catat perintah + keluarannya di log. |
| F11 | Verifikasi akhir menemukan kekurangan | Ya | Laporkan per item, exit 2. Jangan menawarkan rollback otomatis — sebagian "kekurangan" wajar sebelum onboarding (mis. port gateway masih bebas). |

**Aturan rollback:**

1. Selalu `--sisakan-torang --sisakan-agenlain`. Kita tidak pernah mencabut monitor
   Torang, Codex, cua-driver, atau agent-browser yang bukan kita pasang.
2. Rollback **selalu** minta konfirmasi (`y`/`ya`), tidak pernah otomatis.
3. Rollback memakai `oc-uninstall.sh` dari plugin `openclaw-cleanup`. Kalau skrip itu
   tidak ada di mesin, unduh dari GitHub (jalur `bash <(curl …)` yang sudah ada) —
   **jangan menulis ulang logika cabut.**
4. Setelah rollback, jalankan `oc-verify.sh` dan tampilkan hasilnya. User berhak tahu
   apakah mesinnya benar-benar kembali bersih.

---

## 12. Daftar larangan (bug lama yang tidak boleh terulang)

Semua ini pernah menggigit di lapangan. Berlaku untuk semua skrip yang kita tulis.

| # | Larangan | Yang benar |
|---|---|---|
| 1 | `pgrep -f "openclaw"` polos — ikut menemukan shell pemanggil, skrip membunuh terminalnya sendiri | Kecualikan **seluruh rantai leluhur** (walk `/proc/<pid>/status` → PPid), bukan cuma `$$`/`$PPID`, + pola nama skrip sendiri |
| 2 | Menganggap `grep -v` rc=1 sebagai kegagalan | rc ≤ 1 itu aman saat menyunting file rc |
| 3 | `command -v -a` | `type -aP` |
| 4 | Deteksi port hanya lewat `ss`/`lsof`/`fuser` | Baca `/proc/net/tcp` (st `0A` = LISTEN, port heksadesimal, kolom 10 = inode → pid via `/proc/*/fd`) |
| 5 | `read` tanpa membersihkan CR | `JWB="${JWB//$'\r'/}"` di **semua** prompt, lalu `${JWB,,}` |
| 6 | `readlink -f` untuk mendeteksi symlink menggantung | `[ -L "$p" ] && [ ! -e "$p" ]` |
| 7 | `\| tee -a "$LOG" >/dev/null` untuk daftar yang harus dilihat user | Layar **dan** log; jangan telan keluaran |
| 8 | `curl \| bash` | Unduh ke file → catat URL/ukuran/SHA-256 → baru eksekusi |
| 9 | Polling CLI OpenClaw dengan timeout pendek | CLI bisa 13–91 detik di PC kelas; beri timeout longgar |
| 10 | `rm -rf` ke path variabel | Tidak ada penghapusan data user otomatis, titik. Rollback lewat `oc-uninstall.sh` yang pagarnya sudah teruji |
| 11 | `wsl --install` bentuk gabungan | Fase A `--no-distribution`, Fase B `--distribution Ubuntu-24.04 --no-launch` |
| 12 | Mengandalkan distro default WSL | Selalu `-d <nama-dari-state.json>` |
| 13 | Membaca keluaran `wsl.exe` sebagai teks biasa | UTF-16LE — set `[Console]::OutputEncoding` dan buang NUL sebelum regex |
| 14 | `$pid` sebagai nama variabel di PowerShell | Variabel otomatis read-only; pakai `$procId` |
| 15 | `Set-Content -Encoding UTF8` untuk file yang dibaca Node/JSON | Menambah BOM → parse gagal. Pakai `[System.IO.File]::WriteAllText` |

---

## 13. Standar penulisan kode

- **Idempoten.** Setiap langkah cek dulu apakah sudah terpasang. Dijalankan dua kali
  tidak merusak apa pun dan tidak menggandakan apa pun.
- **Log.** `log-pasang.txt` di folder installer. Memuat: waktu, user, mesin, lingkungan,
  setiap perintah yang dijalankan, dan keluaran installer resmi apa adanya.
- **Bahasa.** Semua pesan dan komentar dalam bahasa Indonesia awam. Setiap pesan error
  menyebut tiga hal: **apa yang gagal**, **kenapa kemungkinan besar**, **apa yang harus
  user lakukan**.
- **Konfirmasi.** `y`/`ya`, besar-kecil bebas, CR dibuang. Satu kata kerja per kalimat
  prompt. Tidak ada kata kapital khusus.
- **Root.** Skrip bash menolak root. Bagian yang butuh root lewat `--sudo` per item.
- **Non-tty.** Menolak berjalan tanpa terminal kecuali diberi `-y`.
- **EOL.** `.sh` = LF, `.bat`/`.ps1` = CRLF. CRLF pada `.sh` menghasilkan
  `bad interpreter: /usr/bin/env bash^M`; LF pada `.bat` bisa salah dibaca cmd.exe.
- **Tidak ada file yang ditimpa.** Berlaku juga untuk skrip: kalau menulis config,
  buat cadangan `<nama>.backup-<tanggal>` dulu.

---

## 14. Yang BELUM terverifikasi (jujur, untuk diuji di Fase 4)

1. **`hermes claw migrate`** — perilaku, flag, dan apakah `--dry-run` ada. Referensi CLI
   Hermes hanya memuat satu baris `hermes claw` = "OpenClaw migration helpers". Rancangan
   kita memperlakukannya sebagai best-effort. **Masuk `CARA-UJI-INSTALLER.md`.**
2. **Turun hak akses di Windows** — pilihan 1 (berhenti lalu jalankan lagi tanpa admin)
   belum pernah diuji di PC nyata.
3. **Parsing `wsl --list --all --verbose`** — bentuk keluaran di Windows berbahasa
   Indonesia belum pernah kita lihat. Kolom STATE bisa saja diterjemahkan.
4. **Deteksi virtualisasi** — `VirtualizationFirmwareEnabled` sering `null` di mesin yang
   hypervisor-nya sudah aktif. Kombinasi dengan `HypervisorPresent` perlu dibuktikan di
   beberapa laptop.
5. **`openclaw doctor` pada instalasi yang belum di-onboard** — mungkin melaporkan
   "belum dikonfigurasi" sebagai kegagalan. Verifikasi harus membedakan "belum
   dikonfigurasi" dari "rusak".
6. **Jalur `--skip-browser` Hermes** — menghemat ~1 GB, tapi belum diuji apakah
   memengaruhi fitur yang dipakai kelas.

---

## 15. Yang TIDAK dikerjakan rancangan ini

- Tidak menulis ulang logika installer resmi.
- Tidak menulis ulang logika cabut (`oc-uninstall.sh` / `oc-reset.sh`).
- Tidak menjalankan onboarding (keputusan d.4).
- Tidak memakai jalur Windows-native atau Hermes Desktop secara otomatis — keduanya
  hanya muncul di `PANDUAN-PASANG.md` sebagai cadangan manual (keputusan d.5).
- Tidak menyentuh berkas mana pun di luar folder `openclaw-installer/` — termasuk
  seluruh isi `openclaw-cleanup/` dan `torang-events/` di repo yang sama.

---

## 15b. AMANDEMEN §2.2 — cara turun hak akses (disetujui 19 Agu 2026)

Dipilih **opsi 1**: proses elevated berhenti setelah CEK 2; lanjutan dijalankan sebagai
user asli. `runas /trustlevel` ditolak — terlalu rapuh untuk dipertaruhkan di tangan
pemula. Dua pengaman wajib supaya titik R4 tidak jadi titik kebingungan:

**Pengaman 1 — pesan R4 harus beda dari restart biasa.** Bunyi persisnya:

```
Bagian yang butuh hak Administrator sudah selesai.

Sekarang TUTUP jendela ini, lalu jalankan PASANG.bat lagi dengan
DOBEL-KLIK BIASA — JANGAN klik kanan, JANGAN Run as Administrator.

Kenapa: supaya installer membaca daftar Ubuntu milik akun Windows-mu
sendiri, bukan daftar milik akun lain.
```

**Pengaman 2 — penjaga arah sebaliknya.** Kalau `PASANG.bat` dijalankan **ter-elevasi**
padahal `state.json` menunjukkan CEK 1 dan CEK 2 sudah LULUS (user refleks klik kanan →
Run as Administrator lagi), skrip **tidak boleh melanjutkan CEK 3 dalam kondisi
elevated**. Tampilkan pesan yang sama persis dengan Pengaman 1, lalu keluar dengan
bersih (exit 0, bukan error).

Idempoten tetap terjaga: dijalankan dengan cara apa pun, `PASANG.bat` tidak pernah
merusak. Paling buruk ia hanya memberi tahu cara yang benar.

---

## 16. Sumber

Dokumentasi resmi, diambil dan dicocokkan **19 Agustus 2026**:

- OpenClaw — Install: https://docs.openclaw.ai/install
- OpenClaw — Installer internals (flag, env, pin versi, jebakan npm): https://docs.openclaw.ai/install/installer
- OpenClaw — Uninstall (scope `--service/--state/--workspace/--app`): https://docs.openclaw.ai/install/uninstall
- OpenClaw — Migrating from Hermes: https://docs.openclaw.ai/install/migrating-hermes
- Hermes — Quickstart: https://hermes-agent.nousresearch.com/docs/getting-started/quickstart
- Hermes — Installation (layout, prasyarat, `--skip-browser`): https://hermes-agent.nousresearch.com/docs/getting-started/installation
- Hermes — Updating & Uninstalling (git checkout, rollback, `hermes uninstall`): https://hermes-agent.nousresearch.com/docs/getting-started/updating
- Hermes — CLI commands (`hermes claw` = OpenClaw migration helpers): https://hermes-agent.nousresearch.com/docs/reference/cli-commands
- Microsoft — Troubleshooting WSL (semua kode error §9): https://learn.microsoft.com/en-us/windows/wsl/troubleshooting
- Microsoft — Basic commands for WSL (`--no-distribution`, `--no-launch`, `--web-download`): https://learn.microsoft.com/en-us/windows/wsl/basic-commands
- Microsoft — Enable Virtualization on Windows (jalur Settings + tautan resmi per merek): https://support.microsoft.com/en-us/windows/enable-virtualization-on-windows-c5578302-6e43-4b4b-a449-8ced115f58e1

Sumber internal (dibaca, tidak diubah) — perkakas kelas Torang yang sudah teruji:

- Plugin `openclaw-cleanup/` di repo ini — `references/peta-jejak-instalasi.md`,
  `references/pengetahuan-lapangan.md`, `scripts/oc-verify.sh`,
  `scripts/oc-uninstall.sh`, `scripts/oc-reset.sh`. Ini sumber kebenaran untuk jejak
  instalasi, bug lapangan, dan logika rollback.
- Perkakas kelas Windows & WSL — pemeriksa PC Windows (jebakan dua akun, rebutan port
  18789, rentang port terkunci) dan pemeriksa siap-pasang di dalam WSL.
- Perkakas panggung Torang — pola installer `.bat` + `.ps1`, pemasang jembatan
  OpenClaw di WSL, dan aturan EOL `.sh` LF / `.bat` `.ps1` CRLF.

Sumber non-resmi, ditandai sebagai non-resmi di tabel §9: laporan komunitas untuk
0x800701bc (forum & GitHub issue microsoft/WSL), dan rangkuman tombol BIOS per merek
(dikonfirmasi silang dengan tautan resmi tiap merek yang dirujuk halaman Microsoft).
