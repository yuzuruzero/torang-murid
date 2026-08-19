# Cara Uji Installer — untuk penguji lapangan

Enam skenario. Tiap skenario ditandai:

- **`[SUDAH TERUJI DI SANDBOX]`** — sudah kubuktikan jalan di lingkungan Linux sandbox.
  Kamu boleh melewatinya, atau menjalankannya sekali sebagai konfirmasi.
- **`[WAJIB UJI LAPANGAN]`** — **belum pernah** dijalankan di mesin nyata. Aku tidak
  punya Windows, WSL, Mac, maupun VPS di sini. Ini tanggunganmu.

Kejujuran soal ini penting: sandbox hanya bisa membuktikan bahwa skripnya tidak salah
tulis dan logikanya jalan di Linux. Ia **tidak bisa** membuktikan apa pun tentang
PowerShell 5.1 asli, WSL, BIOS, atau perilaku installer resmi kedua produk.

---

## Ringkasan tanggung jawab

| # | Skenario | Status |
|---|---|---|
| 1 | Komputer kosong: pasang dari nol sampai SELESAI | **[WAJIB UJI LAPANGAN]** |
| 2 | **Anti-dobel Ubuntu** (paling penting) | **[WAJIB UJI LAPANGAN]** |
| 3 | Komputer yang sudah punya Ubuntu sehat | **[WAJIB UJI LAPANGAN]** |
| 4 | Virtualisasi mati → panduan BIOS per merek | **[WAJIB UJI LAPANGAN]** |
| 5 | Membaca `verifikasi.sh` + uji rollback sungguhan | sebagian `[SUDAH TERUJI DI SANDBOX]`, rollback **[WAJIB UJI LAPANGAN]** |
| 6 | Jalur R4 dan Pengaman 2 | **[WAJIB UJI LAPANGAN]** |

Yang **sudah** terbukti di sandbox, supaya tidak kamu uji dua kali:

| Hal | Bukti |
|---|---|
| Sintaks ketiga skrip bash | `bash -n` lolos semua |
| `verifikasi.sh` jalan utuh, 9 kelompok, exit 2 saat kurang | dijalankan sungguhan |
| Deteksi versi Node (22/23/24/25/26) | Node 22.23.2 dikenali benar |
| `pasang-inti.sh --kering` berhenti di pra-cek tanpa mengubah apa pun | dijalankan sungguhan, log disimpan |
| Deteksi flag `--sisakan-torang` / `--sisakan-agenlain` di oc-uninstall.sh | diuji lawan salinan v1.2 di disk |
| EOL: `.sh` LF, `.bat`/`.ps1` CRLF | dicek per berkas |
| `pasang.ps1` murni ASCII (aman untuk PowerShell 5.1 tanpa BOM) | dicek per karakter |
| Tidak ada larangan RANCANGAN bagian 12 yang dilanggar | scan pola |

---

## Persiapan sebelum uji apa pun

1. Salin **satu folder penuh** `openclaw-installer/` ke PC uji (flashdisk atau
   jaringan). Minimal harus terbawa:
   `PASANG.bat`, `pasang.ps1`, `pasang-inti.sh`, `pasang-mac.sh`, `verifikasi.sh`.
2. Taruh di **drive lokal** (mis. `C:\torang\` atau `D:\torang\`), bukan drive jaringan.
   WSL tidak selalu bisa membaca drive jaringan.
3. Catat kondisi awal PC sebelum mulai:

   ```powershell
   wsl --list --all --verbose
   wsl --status
   Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
   Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
   ```

4. Kalau ingin mengulang uji dari nol pada PC yang sama, hapus catatan state-nya:

   ```
   %LOCALAPPDATA%\torang-installer\state.json
   ```

   Ini file kecil buatan installer sendiri, aman dihapus. **Menghapus file ini TIDAK
   menghapus Ubuntu** — hanya membuat installer memeriksa ulang dari awal.

---

## Skenario 1 — Komputer kosong, dari nol sampai SELESAI

**`[WAJIB UJI LAPANGAN]`**

PC Windows yang belum pernah punya WSL sama sekali.

### Langkah

1. Klik kanan `PASANG.bat` → **Run as Administrator**.
2. Ikuti apa pun yang diminta layar. Kalau diminta restart → restart, lalu jalankan
   `PASANG.bat` lagi.
3. Ulangi sampai muncul **SELESAI**.

### Yang harus terjadi

| Jalan ke- | Yang diharapkan |
|---|---|
| 1 | CEK 0–1 lulus → CEK 2 mengaktifkan fitur → **minta restart** |
| 2 (setelah restart) | CEK 0–2 lulus dari state → **pesan R4**: tutup jendela, jalankan lagi tanpa Administrator |
| 3 (dobel-klik biasa) | CEK 3 memasang Ubuntu-24.04 → minta username/password Linux → CEK 3b lulus → CEK 4 lulus → `pasang-inti.sh` jalan → SELESAI |

Jumlah jalan bisa berbeda (kadang restart perlu dua kali). Yang penting: **tidak pernah
buntu**, dan tiap layar selalu menyebutkan satu tindakan berikutnya.

### Catat

- Berapa kali harus restart, dan pada tahap apa.
- Apakah pesan "password tidak terlihat saat diketik" muncul **sebelum** Ubuntu terbuka.
- Isi `%LOCALAPPDATA%\torang-installer\state.json` di akhir.
- `log-pasang.txt` dari folder installer.

### Gagal berarti apa

Kalau installer berhenti tanpa memberi tahu tindakan berikutnya — itu **bug**, bukan
kesalahanmu. Kirim isi layar + `state.json` + `log-pasang.txt`.

---

## Skenario 2 — UJI ANTI-DOBEL (paling penting)

**`[WAJIB UJI LAPANGAN]`**

Ini alasan utama installer ini dibuat. Kalau hanya satu skenario yang sempat diuji,
uji yang ini.

### Langkah

1. Jalankan Skenario 1 sampai tahap CEK 2 selesai dan komputer di-restart.
2. Setelah restart, jalankan `PASANG.bat` **dua kali berturut-turut** — jalan pertama
   sampai Ubuntu terpasang dan SELESAI, lalu langsung jalankan lagi tanpa mengubah
   apa pun.
3. Periksa:

   ```powershell
   wsl --list --all --verbose
   ```

### Yang harus terjadi

- **Hasil akhir: TETAP SATU Ubuntu.** Namanya `Ubuntu-24.04`.
- Jalan kedua harus **mengenali** Ubuntu yang sudah ada, menjadikannya default, dan
  langsung lanjut ke pemasangan OpenClaw/Hermes tanpa memasang distro baru.
- `pasang-inti.sh` pada jalan kedua boleh melaporkan "sudah terpasang dan lolos
  pemeriksaan" dan menawarkan berhenti — itu benar.

### Gagal berarti apa

Kalau muncul **dua** baris Ubuntu (mis. `Ubuntu` dan `Ubuntu-24.04`), berarti deteksi
CEK 3 gagal. Penyebab yang paling mungkin: **parsing UTF-16LE**. Kirimkan keluaran
mentah ini supaya bisa kuperbaiki:

```powershell
$out = & wsl.exe --list --all --verbose
$out | ForEach-Object { [System.Text.Encoding]::UTF8.GetBytes($_) -join ',' } | Select-Object -First 5
```

**Jangan hapus Ubuntu yang kedua sendiri** sebelum keluarannya kukirimi — datanya
justru yang kubutuhkan untuk memperbaiki deteksinya.

### Variasi tambahan (kalau ada waktu)

Pada PC yang sudah punya Ubuntu, sengaja pasang satu lagi dengan nama berbeda:

```powershell
wsl --install -d Ubuntu --no-launch
```

Lalu jalankan `PASANG.bat`. Harapan: skrip **menampilkan daftar keduanya**, memintamu
memilih satu, dan **tidak menghapus apa pun**. Setelah uji, kamu boleh membuang yang
tidak terpakai sendiri dengan `wsl --unregister <nama>` — installer sengaja tidak
melakukannya untukmu.

---

## Skenario 3 — Komputer yang sudah punya Ubuntu sehat

**`[WAJIB UJI LAPANGAN]`**

PC yang WSL-nya sudah jalan dan Ubuntu-nya sudah dipakai.

### Langkah

1. Catat kondisi awal:

   ```powershell
   wsl --list --all --verbose
   wsl --status
   ```

2. Klik kanan `PASANG.bat` → Run as Administrator.

### Yang harus terjadi

- CEK 1 dan CEK 2 **lewat sebagai verifikasi saja** — statusnya LULUS, dan **tidak ada
  fitur Windows yang diaktifkan ulang**, tidak ada `wsl --update`, tidak ada restart
  yang diminta.
- CEK 3 menemukan Ubuntu yang ada, memakainya, **tidak memasang apa pun**.
- Langsung masuk ke pemasangan OpenClaw + Hermes.

### Catat

Bandingkan `wsl --list --all --verbose` sebelum dan sesudah — **harus identik**, kecuali
tanda `*` (default) yang boleh berpindah ke distro terpilih.

### Gagal berarti apa

Kalau installer mengaktifkan ulang fitur Windows atau meminta restart di PC yang sudah
sehat, itu melanggar prinsip "jangan mengubah konfigurasi WSL yang sudah berfungsi".

---

## Skenario 4 — Virtualisasi mati → panduan BIOS

**`[WAJIB UJI LAPANGAN]`**

### Cara mensimulasikan

Cara paling jujur: pinjam laptop yang virtualisasinya memang belum pernah diaktifkan
(laptop konsumen baru sering begitu). Kalau tidak ada, matikan sengaja lewat BIOS pada
satu PC uji, lalu nyalakan lagi setelah selesai.

**Jangan** mensimulasikan dengan `bcdedit /set hypervisorlaunchtype Off` — itu menguji
jalur yang berbeda (CEK 2), bukan CEK 1.

### Yang harus terjadi

1. CEK 1 melapor **GAGAL: Virtualisasi MATI di BIOS**.
2. Muncul merek dan model laptop yang **benar**.
3. Muncul **CARA 1** (Settings → System → Recovery → Advanced startup → Troubleshoot →
   Advanced options → UEFI Firmware Settings) — ini jalur utama.
4. Muncul **CARA 2** dengan tombol yang **sesuai merek** (ASUS `F2`, HP `F10`,
   Lenovo `F1`/Novo, Dell `F2`, Acer `F2`, MSI `Del`).
5. Muncul nama menu yang dicari, menyebut **Intel Virtualization Technology / VT-x**
   dan **SVM Mode** untuk AMD.
6. `state.json` berisi `bios_perlu_tindakan: true` dan `tahap: "bios"`.
7. Setelah virtualisasi diaktifkan dan `PASANG.bat` dijalankan lagi → **lanjut ke CEK 2**,
   tidak mengulang dari nol.

### Catat

Merek/model yang terbaca vs merek/model sebenarnya. Kalau `Win32_ComputerSystem`
mengembalikan sesuatu yang aneh (mis. "System manufacturer"), kirim hasilnya — tabelnya
perlu ditambah.

### Cabang jalan buntu

Kalau PC-nya sangat tua dan skrip berkata **"Prosesor komputer ini tidak mendukung
SLAT"**, itu perilaku yang benar. Skrip harus **berhenti**, bukan mengirimmu ke BIOS.

---

## Skenario 5 — Membaca `verifikasi.sh` dan menguji rollback

### 5a. Membaca hasil verifikasi — **`[SUDAH TERUJI DI SANDBOX]`**

Di dalam Ubuntu, dari folder installer:

```bash
bash verifikasi.sh
```

Cara membacanya:

| Tanda | Artinya | Perlu tindakan? |
|---|---|---|
| `OK` (hijau) | Beres | tidak |
| `i` (kuning) | Catatan. Sering hanya berarti "wajar karena onboarding belum dijalankan" | tidak |
| `KURANG` (merah) | Ada yang benar-benar kurang | ya — barisnya menyebut apa yang harus dilakukan |

Kode keluar: **0** = lengkap, **2** = ada yang kurang. Cek dengan `echo $?`.

**Sebelum onboarding**, wajar kalau muncul: port 18789 masih bebas, unit gateway belum
ada, `openclaw.json` belum ada, `hermes/config.yaml` belum ada. Itu semua bertanda `i`,
bukan `KURANG`.

Mode lain:

```bash
bash verifikasi.sh --potret          # ringkas, dipakai pasang-inti.sh sendiri
bash verifikasi.sh --openclaw-saja   # hanya kelompok OpenClaw
bash verifikasi.sh --dengan-torang   # ikut periksa monitor Torang
```

### 5b. Uji rollback sungguhan — **`[WAJIB UJI LAPANGAN]`**

Cara menggagalkan instalasi di tengah **dengan sengaja dan aman**: putuskan internet
tepat setelah OpenClaw selesai dipasang, sebelum Hermes.

1. Jalankan di dalam Ubuntu:

   ```bash
   bash pasang-inti.sh
   ```

2. Begitu layar menunjukkan **TAHAP 4/8 -- pasang Hermes**, matikan Wi-Fi / cabut kabel.
3. Installer Hermes akan gagal. Skrip harus:
   - menampilkan 30 baris terakhir log,
   - menjelaskan bahwa berhenti dengan OpenClaw saja itu **keadaan yang sah**,
   - menawarkan **rollback**.
4. Jawab **y**.

### Yang harus terjadi saat rollback

- Skrip mencari `oc-uninstall.sh` — di PC kelas biasanya tidak ada salinan lokal, jadi
  ia mengunduh dari GitHub.
- Sebelum menjalankan, ia **memeriksa isi berkas** apakah mendukung `--sisakan-torang`
  dan `--sisakan-agenlain`.

  > Catatan penting: `oc-uninstall.sh` di GitHub `main` saat ini masih **v1.1**, yang
  > **belum punya** `--sisakan-agenlain`. Skrip harus mengenali itu dan menjalankan
  > tanpa flag tersebut — bukan berhenti dengan "Pilihan tak dikenal".
  > **Ini titik uji yang paling spesifik di skenario ini.** Kalau v1.2 sudah kamu push
  > ke main, ujilah sebelum dan sesudah push kalau sempat.

- Konfirmasi minta `y`/`ya`.
- Setelah selesai, jalankan sendiri untuk memastikan:

  ```bash
  bash <(curl -fsSL https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/openclaw-cleanup/scripts/oc-verify.sh)
  ```

### Yang TIDAK boleh terjadi

- Monitor Torang (`~/.torang`, `~/.torang-monitor`) ikut tercabut.
- `~/.codex`, `~/.cua-driver`, `~/.agent-browser` ikut tercabut (kecuali pencabutnya
  memang v1.1 yang tidak punya tahap itu — maka memang tidak akan tersentuh).
- Rollback berjalan **tanpa** konfirmasi.

### 5c. Uji `hermes claw migrate` — **`[WAJIB UJI LAPANGAN]`**

Ini yang **paling tidak pasti** di seluruh proyek. Referensi CLI Hermes hanya memuat
satu baris `hermes claw` = "OpenClaw migration helpers"; tidak ada halaman rinci, dan
`--dry-run` tidak tertulis di mana pun.

Setelah pemasangan sukses di PC yang **memang punya data OpenClaw lama**, jalankan:

```bash
hermes claw --help
hermes claw migrate --help
```

Kirimkan keluaran kedua perintah itu apa adanya. Dari situ baru bisa kuputuskan apakah
migrasi layak dinaikkan dari best-effort jadi langkah beneran.

Sementara itu perilakunya sudah aman: kalau perintahnya gagal atau tidak dikenal,
`pasang-inti.sh` hanya memberi peringatan dan **tetap** menganggap pemasangan sukses.

---

## Skenario 6 — Jalur R4 dan Pengaman 2

**`[WAJIB UJI LAPANGAN]`**

Menguji titik belokan hak akses — satu-satunya tempat di seluruh alur Windows yang
instruksinya berbeda dari "restart lalu jalankan lagi".

**Prasyarat:** PC yang CEK 1 dan CEK 2 sudah LULUS. Pastikan dulu:

```powershell
type %LOCALAPPDATA%\torang-installer\state.json
```

`cek1_virtualisasi` harus `LULUS` dan `cek2_fitur` harus `LULUS` atau
`DIPERBAIKI-OTOMATIS`.

### 6a. Arah yang benar — dobel-klik biasa

1. **Dobel-klik** `PASANG.bat` (jangan klik kanan).
2. Yang harus terjadi:
   - Skrip **tidak** meminta elevasi.
   - Layar berkata: `berjalan sebagai pengguna biasa (benar untuk CEK 3 ke atas)`.
   - Lanjut ke **CEK 3**.
   - Daftar Ubuntu yang tampil adalah milik akun Windows yang sedang dipakai.

### 6b. Arah sebaliknya — Pengaman 2

1. Klik kanan `PASANG.bat` → **Run as Administrator** (refleks yang wajar, karena itu
   yang tertulis di panduan untuk jalan pertama).
2. Yang harus terjadi:
   - Skrip **BERHENTI sebelum CEK 3**.
   - Muncul kotak kuning berisi persis:

     ```
     Bagian yang butuh hak Administrator sudah selesai.

     Sekarang TUTUP jendela ini, lalu jalankan PASANG.bat lagi dengan
     DOBEL-KLIK BIASA -- JANGAN klik kanan, JANGAN Run as Administrator.

     Kenapa: supaya installer membaca daftar Ubuntu milik akun Windows-mu
     sendiri, bukan daftar milik akun lain.
     ```

   - **Keluar bersih**: kode keluar **0**, bukan error.

3. Periksa bahwa **state tidak berubah**:

   ```powershell
   copy %LOCALAPPDATA%\torang-installer\state.json %TEMP%\state-sebelum.json
   rem  jalankan PASANG.bat sebagai Administrator, tunggu Pengaman 2 muncul
   fc %TEMP%\state-sebelum.json %LOCALAPPDATA%\torang-installer\state.json
   ```

   `fc` harus melaporkan **tidak ada perbedaan**, kecuali field `diperbarui` dan
   `cek0_hak_akses` — keduanya memang ditulis di CEK 0, sebelum Pengaman 2 aktif.

   > Kalau ada field lain yang berubah (terutama apa pun di `cek3_*`), itu bug:
   > artinya skrip sempat menyentuh tahap distro dalam kondisi elevated.

### 6c. Idempoten — bolak-balik

Jalankan bergantian: dobel-klik → klik kanan → dobel-klik → klik kanan. Setiap kali,
skrip harus memberi tahu langkah yang benar dan **tidak pernah merusak apa pun**. Di
akhir, `wsl --list --all --verbose` harus tetap menunjukkan jumlah Ubuntu yang sama.

---

## Uji Mac dan VPS (kalau sempat)

**`[WAJIB UJI LAPANGAN]`** keduanya.

### Mac

```bash
bash pasang-mac.sh --kering    # rencana dulu
bash pasang-mac.sh             # sungguhan
```

Yang perlu diperhatikan khusus Mac:

- Bash bawaan macOS masih **3.2**. Skrip ditulis untuk itu (tanpa `${v,,}`, tanpa
  `declare -A`, `timeout` diberi pengganti). Kalau muncul error sintaks aneh, kirim
  barisnya — berarti ada yang lolos.
- `timeout` tidak ada di macOS. `batas_waktu()` seharusnya menjalankan perintah langsung
  tanpa batas waktu. Efeknya: kalau CLI menggantung, skrip ikut menunggu. Catat kalau
  ini terjadi.
- Verifikasi kelompok [5] harus mencari **LaunchAgent**, bukan systemd.

### VPS

```bash
bash pasang-inti.sh
```

- Harus **menolak** kalau dijalankan sebagai root, dengan saran `adduser`.
- Setelah selesai, cek saran `sudo loginctl enable-linger <user>` muncul di verifikasi
  kelompok [5].

---

## Cara melaporkan hasil

Untuk tiap skenario yang dijalankan, kirim:

1. **Nomor skenario** dan hasilnya: lulus / gagal / sebagian.
2. **`log-pasang.txt`** dari folder installer — beri nama yang menyebut PC dan
   tanggalnya, mis. `log-pasang-kelaspc03-20260901.txt`.
3. **`state.json`** dari `%LOCALAPPDATA%\torang-installer\`.
4. **Foto/salinan layar** pada titik yang gagal — teks lebih berguna daripada foto
   kalau bisa disalin.
5. Untuk kegagalan WSL: keluaran mentah `wsl --list --all --verbose`.

Kalau installer berhenti **tanpa memberi tahu langkah berikutnya**, itu selalu bug —
laporkan walaupun kamu sudah tahu cara mengakalinya sendiri.

---

## Setelah uji lapangan pertama

1. Isi baris OpenClaw dan Hermes di `VERSI-TERUJI.md` (sengaja kosong — mengisi versi
   yang belum pernah dipasang akan membuat tabel itu berbohong sejak hari pertama).
2. Catat kegagalan baru yang belum pernah tercatat, supaya bisa masuk ke catatan
   pengetahuan lapangan dan ke tabel masalah umum di `PANDUAN-PASANG.md`.
3. Catat skenario mana yang sudah lulus, tanggalnya, dan di PC apa.
