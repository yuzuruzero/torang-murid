# Panduan Pasang — OpenClaw + Hermes

Pemasang ini memakai installer **resmi** dari kedua produk. Tugasnya memeriksa
prasyarat, menjalankan installer resmi dengan urutan yang benar, memverifikasi
hasilnya, dan menawarkan pembatalan bersih kalau ada yang gagal di tengah.

---

## 0. Cara mendapatkan installer

### Cara utama — unduh ZIP (paling aman, jalan di semua kondisi)

1. Buka <https://github.com/yuzuruzero/torang-murid>
2. Klik tombol hijau **Code** → **Download ZIP**
3. Ekstrak ZIP-nya, lalu masuk ke folder **`openclaw-installer`**

Taruh folder itu di **drive lokal** (mis. `C:\torang\` atau `D:\torang\`), bukan di
drive jaringan — WSL tidak selalu bisa membaca drive jaringan.

Bawa **satu folder penuh**, bukan satu file. Isinya minimal:

```
PASANG.bat   pasang.ps1   pasang-inti.sh   pasang-mac.sh   verifikasi.sh
```

### Cara cepat — satu baris perintah

**Windows**, di PowerShell:

```powershell
irm https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/openclaw-installer/bootstrap.ps1 | iex
```

Perintah itu mengunduh berkas pemasang ke `%LOCALAPPDATA%\torang-installer\` lalu
menjalankannya. Berkasnya disimpan **permanen** di sana — memang harus begitu, karena
pemasangan WSL butuh beberapa kali restart dan setelah restart perintah tadi sudah
hilang dari memori. Kalau diminta restart, kamu punya dua cara melanjutkan, dua-duanya
benar: jalankan lagi perintah yang sama, atau buka folder itu dan klik kanan
`PASANG.bat`.

**Mac, VPS Linux, atau dari dalam Ubuntu WSL**, di Terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/openclaw-installer/pasang.sh)
```

Berkas diunduh ke `~/.torang-installer/`, dicatat di `log-unduh.txt` lengkap dengan
ukuran dan sidik jari SHA-256, baru dijalankan.

> Kalau jaringan sekolah memblokir `raw.githubusercontent.com`, kedua perintah satu
> baris ini akan gagal. Itu bukan kerusakan — pakai cara ZIP di atas.

---

## A. WINDOWS — satu cara untuk semua komputer

**Klik kanan `PASANG.bat` → Run as Administrator.**

Kalau diminta restart: **restart, lalu jalankan file yang sama lagi.**
Ulangi sampai muncul tulisan **SELESAI**.

Itu saja. Tidak ada perintah berbeda untuk komputer yang sudah punya Ubuntu dan yang
belum — skrip yang memeriksa sendiri dan memilih jalannya.

### Satu belokan yang perlu kamu tahu

Di satu titik, layar akan berkata:

> Bagian yang butuh hak Administrator sudah selesai. Sekarang TUTUP jendela ini, lalu
> jalankan PASANG.bat lagi dengan **DOBEL-KLIK BIASA** — jangan klik kanan, jangan Run
> as Administrator.

Ini disengaja, bukan kesalahan. Alasannya satu kalimat: Ubuntu (WSL) terdaftar
**per akun Windows**, dan jendela Administrator bisa membaca daftar Ubuntu milik akun
lain. Kalau installer salah baca di titik itu, komputer bisa berakhir punya **dua
Ubuntu** yang saling berebut.

Kalau kamu terlanjur klik kanan lagi, tidak apa-apa — skrip akan mengingatkan dan keluar
tanpa merusak apa pun. `PASANG.bat` aman dijalankan berulang kali dengan cara apa pun.

### Yang akan terjadi, urutannya

| Tahap | Yang dikerjakan | Perlu kamu? |
|---|---|---|
| 1 | Cek akun Windows & hak akses | tidak |
| 2 | Cek virtualisasi CPU | hanya kalau mati (lihat §D) |
| 3 | Aktifkan fitur Windows untuk WSL | **restart** |
| 4 | (jalankan lagi, tanpa Administrator) | dobel-klik |
| 5 | Pasang / pilih Ubuntu | buat username + password Linux |
| 6 | Uji kesehatan Ubuntu | tidak |
| 7 | Cek jaringan & ruang disk | tidak |
| 8 | Pasang OpenClaw lalu Hermes | tidak |
| 9 | Verifikasi | tidak |

### Saat Ubuntu minta username dan password

Ini bagian yang paling sering bikin bingung:

- Yang diminta adalah username dan password **Linux**, bukan password Windows.
- **Password tidak terlihat saat diketik.** Layarnya diam saja — tidak ada titik, tidak
  ada bintang. Itu normal. Ketik saja, lalu Enter.
- Username: huruf kecil semua, tanpa spasi.
- **Ingat password-nya.** Nanti dipakai untuk perintah `sudo`.

---

## B. MAC

Buka Terminal, masuk ke folder installer, lalu:

```bash
bash pasang-mac.sh
```

Kalau diminta memasang **Command Line Tools**, jalankan `xcode-select --install`, tunggu
sampai selesai (bisa belasan menit), lalu jalankan `pasang-mac.sh` lagi.

Homebrew tidak wajib. Kalau perlu, installer resmi OpenClaw memasangnya sendiri. Kami
sengaja tidak memasang Homebrew diam-diam.

---

## C. VPS / SERVER LINUX

```bash
bash pasang-inti.sh
```

Jalankan sebagai **user biasa**, bukan root. Kalau VPS-mu hanya punya root, buat user
dulu:

```bash
adduser namamu
usermod -aG sudo namamu
su - namamu
```

Kalau gateway harus tetap hidup setelah kamu logout:

```bash
sudo loginctl enable-linger namamu
```

---

## D. Kalau virtualisasi mati di BIOS

Ini satu-satunya bagian yang **tidak bisa** diperbaiki skrip — setelannya ada di
firmware komputer, di luar jangkauan Windows. Skrip akan mendeteksi merek laptopmu dan
menampilkan panduan yang sesuai. Ringkasnya:

### Cara masuk BIOS — jalur paling gampang (semua merek)

1. **Settings → System → Recovery** (Windows 10: Update & Security → Recovery)
2. Di **Advanced startup**, klik **Restart now**
3. **Troubleshoot → Advanced options → UEFI Firmware Settings → Restart**

Komputer masuk BIOS sendiri. Tidak perlu menekan tombol cepat-cepat.

### Cara masuk BIOS — tombol saat menyalakan (cadangan)

| Merek | Tombol | Nama setelan yang dicari |
|---|---|---|
| ASUS | `F2` (sebagian `Del`) | Advanced → CPU Configuration → **Intel Virtualization Technology** / **SVM Mode** |
| Acer | `F2` | Main / Advanced → **Intel(R) Virtualization Technology** |
| Lenovo | `F1` (ThinkPad) · `F2` atau tombol **Novo** (IdeaPad) | Security → Virtualization → **Intel Virtualization Technology** |
| HP | `F10` | Security / System Configuration → **Virtualization Technology (VTx)** |
| Dell | `F2` | Virtualization Support → **Virtualization** |
| MSI | `Del` | OC → CPU Features → **SVM Mode** / **Intel Virtualization Tech** |

Ubah jadi **Enabled**, simpan dengan **F10**, lalu jalankan `PASANG.bat` lagi.

Halaman resmi tiap merek (dari Microsoft):
[Acer](https://community.acer.com/kb/articles/14750) ·
[Asus](https://www.asus.com/support/FAQ/1043181) ·
[Dell](https://www.dell.com/support/kbdoc/000195978/) ·
[HP](https://support.hp.com/us-en/document/ish_5637142-5637191-16) ·
[Lenovo](https://support.lenovo.com/solutions/ht500006)

**Kalau setelan itu tidak ada sama sekali:** BIOS dikunci pabrikan/admin IT, CPU-nya
tidak mendukung, atau BIOS perlu di-update. Tanyakan ke yang mengurus komputer itu.

---

## E. Setelah SELESAI — dua langkah yang harus kamu jalankan sendiri

Pemasang **sengaja tidak** menjalankan onboarding. Keduanya interaktif dan meminta kunci
API atau login akun — itu harus keputusanmu, bukan skrip.

Buka Ubuntu (atau Terminal di Mac), lalu:

### 1. OpenClaw

```bash
openclaw onboard
```

Yang akan ditanya:

- **Cara login** — kunci API OpenAI, atau langganan yang kamu punya.
- **Pasang gateway sebagai layanan?** → jawab **YA**. Ini yang membuat OpenClaw hidup
  sendiri tanpa perlu dijalankan manual tiap kali.

### 2. Hermes

```bash
hermes setup
```

Yang akan ditanya:

- **Penyedia model** dan kunci/akunnya. Kalau bingung, pilih **Quick Setup (Nous
  Portal)** — satu login, tidak perlu mengurus kunci API satu per satu.

### 3. Pastikan semuanya beres

```bash
bash verifikasi.sh
```

Keluar dengan **0** berarti lengkap. Keluar dengan **2** berarti ada yang kurang — tiap
baris bertanda `KURANG` menyebutkan apa yang kurang dan apa yang harus dilakukan.

---

## F. Masalah umum dan solusinya

| Yang kamu lihat | Kemungkinan besar | Yang harus dilakukan |
|---|---|---|
| `PASANG.bat` minta Run as Administrator terus | Kotak izin Windows diklik "No" | Klik kanan → Run as Administrator, jawab **Yes** |
| Layar bilang "jalankan lagi tanpa Administrator" | Titik belokan normal (§A) | Tutup jendela, **dobel-klik** PASANG.bat |
| Berhenti dengan "akun Windows berbeda" | Pemasangan dimulai di akun lain | Sign out (**jangan** Switch user), masuk akun yang disebutkan |
| Error `0x80370102` | Virtualisasi mati di BIOS | Lihat §D |
| Error `0x8007019e` | Fitur WSL belum aktif | Restart, jalankan `PASANG.bat` lagi |
| Error `0x1bc` saat menyiapkan WSL | Kernel WSL2 perlu update (pesannya menyesatkan; sering di Windows non-Inggris) | `wsl --update`, lalu ulangi |
| "no more endpoints available from the endpoint mapper" | Layanan ICS (`SharedAccess`) dimatikan kebijakan admin | Kembalikan ke **Manual (Trigger Start)**, atau minta admin IT |
| "no installed distributions" padahal dulu pernah pasang | Instalasinya di **akun Windows lain** | Masuk ke akun itu. **Jangan** pasang ulang di sini |
| Ubuntu muncul dua di `wsl -l -v` | Kasus Ubuntu-dobel | Jalankan `PASANG.bat`, pilih satu saat diminta — installer menampilkan daftarnya dan tidak menghapus apa pun |
| Password Linux "tidak masuk" | Password memang tidak terlihat saat diketik | Ketik saja sampai selesai, lalu Enter |
| `openclaw: command not found` setelah pemasangan | PATH belum segar di terminal ini | Tutup terminal, buka baru. Atau: `source ~/.bashrc` |
| Gateway "running" tapi dashboard tak mau terbuka di browser Windows | Masalah **penerusan port**, bukan OpenClaw | Di dalam WSL: `curl -sI http://127.0.0.1:18789`. Kalau jalan di WSL tapi tidak di browser → jangan pasang ulang; lihat `PANDUAN-DUA-AKUN-WINDOWS.md` |
| Ruang disk kurang | Butuh minimal 4 GB | Kosongkan dulu. Lebih baik berhenti sekarang daripada gagal di tengah |
| Pemasangan berhenti di tengah | Bisa banyak sebab | Skrip menawarkan **rollback**. Terima tawaran itu, lalu pasang lagi dari awal |

**Semua yang terjadi tercatat di `log-pasang.txt`** di folder installer. Kalau melapor
masalah, kirim file itu — di dalamnya ada perintah yang dijalankan dan keluaran mentah
installer resmi.

---

## G. Jalur manual — cadangan kalau pemasang bermasalah

Semua di bawah ini adalah perintah **resmi** dari masing-masing produk. Jalankan dari
dalam Ubuntu (WSL), Terminal Mac, atau VPS.

### OpenClaw

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

Pin versi tertentu:

```bash
curl -fsSL https://openclaw.ai/install.sh -o oc.sh
bash oc.sh --version <versi> --no-onboard
```

### Hermes

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
source ~/.bashrc
```

Hemat ~1 GB dengan melewati Chromium (fitur browser jadi tidak bisa dipakai):

```bash
bash hermes-install.sh --skip-browser
```

### Membersihkan sebelum pasang ulang

Jangan pernah memasang di atas sisa pasangan lama — itu sumber "gateway error / token
tidak ke-generate / dashboard tak mau terbuka".

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/openclaw-cleanup/scripts/oc-total.sh)
```

### Installer desktop — hanya untuk keadaan khusus

Kedua produk punya jalur Windows-native dan aplikasi desktop:

- OpenClaw: Windows Hub, dan `iwr -useb https://openclaw.ai/install.ps1 | iex`
- Hermes: Hermes Desktop installer di https://hermes-agent.nousresearch.com/

**Pemasang kami tidak pernah memilih jalur ini secara otomatis, dan itu disengaja.**
Semua perkakas kelas Torang (pemeriksa, pembersih, pemulih) berbasis Ubuntu dan bekerja
di dalam WSL. Instalasi sisi Windows tidak bisa diurus dari sana — bahkan `sudo` pun
tidak membantu; harus lewat `cmd.exe /c "npm rm -g openclaw"`.

Kalau kamu memasang lewat jalur Windows-native, kamu keluar dari jalur yang didukung
perkakas kami. Pakai hanya kalau WSL benar-benar tidak mungkin di komputer itu — dan
catat baik-baik bahwa PC tersebut berbeda dari yang lain.

---

## H. Berkas di folder ini

| Berkas | Untuk apa |
|---|---|
| `PASANG.bat` | Pintu Windows. Ini yang kamu klik. |
| `pasang.ps1` | Otak sisi Windows: cek BIOS, fitur, Ubuntu. |
| `pasang-inti.sh` | Otak pemasangan. Sama persis di WSL, Mac, dan VPS. |
| `pasang-mac.sh` | Pintu Mac. |
| `verifikasi.sh` | Pemeriksa. Tidak mengubah apa pun, aman kapan saja. |
| `VERSI-TERUJI.md` | Versi yang pernah kami buktikan jalan. |
| `pasang.sh` | Pintu satu-baris untuk Mac / VPS / di dalam WSL. |
| `bootstrap.ps1` | Pintu satu-baris untuk Windows. |
| `RANCANGAN.md` | Rancangan teknis lengkap (untuk yang mengembangkan). |
| `CARA-UJI-INSTALLER.md` | Rencana uji + status jujur mana yang sudah/belum teruji. |
| `log-pasang.txt` | Muncul sendiri setelah pemasangan pertama. Kirim ini saat melapor. |
