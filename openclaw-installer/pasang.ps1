# =====================================================================
#  TORANG -- PEMASANG OpenClaw + Hermes  (pintu Windows, otak)  v1.0
#
#  Dipanggil oleh PASANG.bat. JANGAN dijalankan langsung oleh pengguna
#  awam -- PASANG.bat yang jadi pintunya.
#
#  Tugas berkas ini HANYA menyiapkan WSL sampai sehat. Pemasangan
#  OpenClaw dan Hermes yang sebenarnya dikerjakan pasang-inti.sh
#  DI DALAM WSL -- file yang sama persis dengan yang dipakai Mac dan VPS.
#
#  ALUR (rinci di RANCANGAN.md bagian 2):
#     CEK 0  hak akses + identitas akun Windows
#     CEK 1  virtualisasi CPU            ] butuh Administrator
#     CEK 2  fitur Windows (Fase A)      ]
#     -- turun hak akses, jalankan ulang TANPA Administrator --
#     CEK 3  distro Ubuntu (Fase B, anti-dobel)
#     CEK 3b kesehatan distro
#     CEK 4  jaringan & disk
#     -> wsl -d <distro> -- bash pasang-inti.sh
#
#  KENAPA CEK 3 TIDAK BOLEH ELEVATED: distro WSL terdaftar per akun
#  Windows (HKCU\...\Lxss). PowerShell yang dinaikkan haknya bisa membaca
#  daftar milik akun LAIN -- persis pada masalah yang sedang kita cari.
#  Salah baca di titik itu ujungnya Ubuntu terpasang dua kali.
# =====================================================================

$ErrorActionPreference = 'Continue'

$Versi         = '1.0'
$DistroKanonik = 'Ubuntu-24.04'
$DiskMinMB     = 4096
$StateDir      = Join-Path $env:LOCALAPPDATA 'torang-installer'
$StateFile     = Join-Path $StateDir 'state.json'
$FolderSkrip   = Split-Path -Parent $MyInvocation.MyCommand.Path

# Penanda dari bootstrap.ps1 (jalur satu-baris PowerShell). Kalau ada,
# pesan "jalankan lagi" menyebutkan cara yang sesuai untuk jalur itu.
$ViaBootstrap  = Test-Path (Join-Path $StateDir 'via-bootstrap.txt')

$Gagal = 0

# Baris tambahan untuk setiap pesan "jalankan lagi", hanya bila pengguna
# datang lewat perintah satu-baris.
function Baris-Lanjut {
  if (-not $ViaBootstrap) { return @() }
  return @(
    "",
    "Kamu memakai perintah PowerShell satu-baris, jadi ada DUA cara",
    "melanjutkan -- dua-duanya benar:",
    "  a. jalankan lagi perintah  irm ... | iex  yang sama",
    "     (tidak mengunduh ulang, langsung lanjut), atau",
    "  b. buka folder ini lalu klik kanan PASANG.bat:",
    "     $StateDir"
  )
}

# ---------------------------------------------------------------------
#  Tampilan
# ---------------------------------------------------------------------
function Judul($m) { Write-Host ""; Write-Host $m -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "  [ OK ] " -ForegroundColor Green  -NoNewline; Write-Host $m }
function Bad  ($m) { Write-Host "  [GAGAL]" -ForegroundColor Red    -NoNewline; Write-Host " $m"; $script:Gagal++ }
function Warn ($m) { Write-Host "  [ ?  ] " -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Obat ($m) { Write-Host "         -> $m" -ForegroundColor DarkGray }
function Kotak($m, $warna) {
  Write-Host ""
  Write-Host ("=" * 62) -ForegroundColor $warna
  foreach ($b in $m) { Write-Host "  $b" -ForegroundColor $warna }
  Write-Host ("=" * 62) -ForegroundColor $warna
  Write-Host ""
}

# ---------------------------------------------------------------------
#  state.json  -- ditulis atomik (state setengah jadi lebih berbahaya
#  daripada tidak ada state sama sekali)
# ---------------------------------------------------------------------
function Baca-State {
  if (-not (Test-Path $StateFile)) { return $null }
  try { return (Get-Content -Raw -Path $StateFile | ConvertFrom-Json) }
  catch {
    Warn "state.json tidak bisa dibaca (rusak?) -- dianggap belum ada."
    Obat "Isinya diabaikan; pemeriksaan diulang dari kondisi nyata."
    return $null
  }
}

function Tulis-State($obj) {
  if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
  $obj.diperbarui = (Get-Date -Format 'o')
  $sementara = "$StateFile.baru"
  # WriteAllText = UTF-8 tanpa BOM. Set-Content -Encoding UTF8 di
  # PowerShell 5.1 menambah BOM, dan file ber-BOM bikin pembaca JSON lain
  # tersedak. Ini pelajaran dari insiden nyata di perkakas kelas kami.
  [System.IO.File]::WriteAllText($sementara, ($obj | ConvertTo-Json -Depth 8))
  Move-Item -Force -Path $sementara -Destination $StateFile
}

function State-Baru {
  $o = [ordered]@{
    versi_state         = 1
    versi_installer     = $Versi
    user_windows        = $env:USERNAME
    komputer            = $env:COMPUTERNAME
    dibuat              = (Get-Date -Format 'o')
    diperbarui          = (Get-Date -Format 'o')
    tahap               = 'mulai'
    perlu_restart       = $false
    butuh_elevasi       = $true
    cek                 = [ordered]@{}
    bios_perlu_tindakan = $false
    catatan_terakhir    = ''
  }
  return ([pscustomobject]$o)
}

function Set-Cek($state, $nama, $status, $tambahan) {
  $isi = [ordered]@{ status = $status; waktu = (Get-Date -Format 'o') }
  if ($tambahan) { foreach ($k in $tambahan.Keys) { $isi[$k] = $tambahan[$k] } }
  # ConvertFrom-Json menghasilkan PSCustomObject; tambah properti dengan aman
  if ($state.cek -is [System.Management.Automation.PSCustomObject]) {
    $state.cek | Add-Member -NotePropertyName $nama -NotePropertyValue ([pscustomobject]$isi) -Force
  } else {
    $state.cek[$nama] = [pscustomobject]$isi
  }
}

function Status-Cek($state, $nama) {
  if (-not $state) { return $null }
  if (-not $state.cek) { return $null }
  $p = $state.cek.PSObject.Properties[$nama]
  if (-not $p) { return $null }
  return $p.Value.status
}

# ---------------------------------------------------------------------
#  Memanggil wsl.exe DENGAN BENAR
#  Keluaran wsl.exe adalah UTF-16LE. Dibaca sebagai teks biasa, hasilnya
#  penuh karakter NUL dan -match 'ubuntu' gagal. Gagal palsu di sini
#  artinya skrip menyimpulkan "belum ada Ubuntu" lalu memasang yang
#  kedua -- persis kerusakan yang sedang kita cegah.
# ---------------------------------------------------------------------
function Wsl-Keluaran {
  param([string[]]$Argumen)
  $encLama = [Console]::OutputEncoding
  $keluaran = @()
  try {
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    $keluaran = & wsl.exe @Argumen 2>&1
  } catch {
    $keluaran = @("$_")
  } finally {
    try { [Console]::OutputEncoding = $encLama } catch { }
  }
  $bersih = @()
  foreach ($b in $keluaran) {
    $t = ("$b" -replace "`0", '').Trim()
    if ($t -ne '') { $bersih += $t }
  }
  return $bersih
}

# ---------------------------------------------------------------------
#  Tabel error WSL -- sumber: docs Microsoft (lihat RANCANGAN.md bagian 9 dan 16)
# ---------------------------------------------------------------------
function Jelaskan-ErrorWsl($teks) {
  $t = "$teks"
  if ($t -match '0x80370102') {
    Bad "WSL tidak bisa menyalakan mesin virtualnya (0x80370102)."
    Obat "Kenapa biasanya: virtualisasi mati di BIOS, atau fitur"
    Obat "Virtual Machine Platform belum aktif."
    Obat "Kalau CEK 1 tadi lulus, coba di PowerShell Administrator:"
    Obat "  bcdedit /set hypervisorlaunchtype Auto   lalu restart"
    Obat "Kalau ada VMware/VirtualBox lama, matikan dulu atau update."
    return $true
  }
  if ($t -match '0x8007019e') {
    Bad "Komponen Windows Subsystem for Linux belum aktif (0x8007019e)."
    Obat "Artinya CEK 2 belum tuntas."
    Obat "Restart komputer, lalu jalankan PASANG.bat lagi -- skrip akan"
    Obat "mengaktifkannya sendiri."
    return $true
  }
  if ($t -match '0x80070003') {
    Bad "WSL hanya bisa jalan di drive sistem (0x80070003)."
    Obat "Buka Settings > System > Storage > Advanced storage settings >"
    Obat "'Where new content is saved', dan pastikan aplikasi baru"
    Obat "disimpan di drive C:."
    return $true
  }
  if ($t -match '0x80040154') {
    Bad "Fitur WSL kemungkinan dimatikan oleh Windows Update (0x80040154)."
    Obat "Jalankan PASANG.bat lagi -- CEK 2 akan mengaktifkannya kembali."
    return $true
  }
  if ($t -match '0x1bc') {
    Bad "Kernel WSL2 perlu diperbarui (0x1bc)."
    Obat "Pesan aslinya menyesatkan; ini sering muncul di Windows yang"
    Obat "bahasanya bukan Inggris."
    Obat "Lakukan: wsl --update, lalu jalankan PASANG.bat lagi."
    return $true
  }
  if ($t -match 'no more endpoints|endpoint mapper') {
    Bad "Layanan Internet Connection Sharing (ICS) dimatikan."
    Obat "WSL2 membutuhkannya. Di komputer sekolah/kantor ini biasanya"
    Obat "kebijakan admin, bukan kerusakan."
    Obat "Kembalikan layanan 'SharedAccess' ke Manual (Trigger Start),"
    Obat "atau minta admin IT membuka kebijakannya."
    return $true
  }
  if ($t -match 'referenced assembly could not be found') {
    Bad "Windows menolak mengaktifkan fitur: berkas komponennya tidak lengkap."
    Obat "Coba lewat jendela biasa: Start > ketik 'Turn Windows features"
    Obat "on or off' > centang 'Windows Subsystem for Linux'."
    Obat "Kalau tetap gagal: jalankan Windows Update sampai tuntas."
    return $true
  }
  if ($t -match 'virtual disk system limitation') {
    Bad "Folder distro dikompresi/dienkripsi NTFS, jadi tidak bisa dipakai."
    Obat "Cari folder LocalState distro itu > klik kanan > Properties >"
    Obat "Advanced > hilangkan centang 'Compress contents to save disk"
    Obat "space' dan 'Encrypt contents to secure data' > pilih"
    Obat "'just this folder'."
    return $true
  }
  if ($t -match 'no installed distributions') {
    Bad "WSL bilang tidak ada distro terpasang untuk akun ini."
    Obat "Kalau kamu yakin pernah memasang, kemungkinan besar itu di AKUN"
    Obat "WINDOWS LAIN. Distro WSL terdaftar per akun."
    Obat "Akun yang sedang dipakai sekarang: $env:USERNAME"
    Obat "Jangan pasang ulang di sini -- masuk dulu ke akun yang benar."
    return $true
  }
  if ($t -match '0x800701bc') {
    Bad "Paket kernel WSL2 usang atau tidak cocok (0x800701bc)."
    Obat "(Sumber non-resmi -- laporan komunitas, bukan dokumen Microsoft.)"
    Obat "Lakukan: wsl --update, lalu restart, lalu jalankan PASANG.bat lagi."
    return $true
  }
  if ($t -match '0x8000FFFF') {
    Bad "WSL gagal dengan error umum (0x8000FFFF)."
    Obat "Urutan yang disarankan Microsoft, satu per satu:"
    Obat "  1. wsl --update"
    Obat "  2. wsl --shutdown"
    Obat "  3. SFC /SCANNOW                              (lama, sabar)"
    Obat "  4. DISM /Online /Cleanup-Image /RestoreHealth (lama, sabar)"
    Obat "Kami sengaja TIDAK menjalankan 3 dan 4 sendiri -- keduanya lama"
    Obat "dan sebaiknya kamu yang mengawasi."
    return $true
  }
  return $false
}

# ---------------------------------------------------------------------
#  Panduan BIOS per merek
# ---------------------------------------------------------------------
function Panduan-Bios($merek, $model) {
  $m = "$merek".ToUpper()
  $tombol = 'F2'; $menu = 'Advanced > CPU Configuration > Intel Virtualization Technology (Intel) atau SVM Mode (AMD)'
  if     ($m -match 'ASUS')            { $tombol = 'F2 (tahan saat menyalakan); sebagian model Del'; $menu = 'Advanced > CPU Configuration > Intel Virtualization Technology, atau SVM Mode untuk AMD. Kalau layarnya sederhana, tekan F7 dulu untuk Advanced Mode.' }
  elseif ($m -match 'ACER')            { $tombol = 'F2'; $menu = 'Main atau Advanced > Intel(R) Virtualization Technology / VT-d' }
  elseif ($m -match 'LENOVO')          { $tombol = 'F1 (ThinkPad), atau F2 / tombol Novo kecil di sisi bodi (IdeaPad)'; $menu = 'Security > Virtualization > Intel Virtualization Technology, atau Configuration > Intel Virtual Technology' }
  elseif ($m -match 'HEWLETT|HP')      { $tombol = 'F10'; $menu = 'Security atau System Configuration > Virtualization Technology (VTx)' }
  elseif ($m -match 'DELL')            { $tombol = 'F2'; $menu = 'Virtualization Support > Virtualization (centang Enable Intel Virtualization Technology)' }
  elseif ($m -match 'MSI|MICRO-STAR')  { $tombol = 'Del'; $menu = 'OC / Overclocking > CPU Features > SVM Mode (AMD) atau Intel Virtualization Tech (Intel)' }

  Write-Host ""
  Write-Host "  Laptop terdeteksi: $merek $model" -ForegroundColor White
  Write-Host ""
  Write-Host "  CARA 1 (paling gampang, jalan di semua merek):" -ForegroundColor Yellow
  Write-Host "    Settings > System > Recovery"
  Write-Host "    (Windows 10: Update & Security > Recovery)"
  Write-Host "    Di bagian 'Advanced startup' klik 'Restart now'"
  Write-Host "    Lalu: Troubleshoot > Advanced options > UEFI Firmware Settings > Restart"
  Write-Host "    Komputer masuk BIOS sendiri. Tidak perlu menekan tombol apa pun"
  Write-Host "    dengan cepat-cepat."
  Write-Host ""
  Write-Host "  CARA 2 (kalau menu 'UEFI Firmware Settings' tidak muncul):" -ForegroundColor Yellow
  Write-Host "    Matikan komputer. Nyalakan lagi sambil menekan berulang: $tombol"
  Write-Host ""
  Write-Host "  DI DALAM BIOS, cari:" -ForegroundColor Yellow
  Write-Host "    $menu"
  Write-Host "    Ubah jadi Enabled."
  Write-Host "    Simpan dengan F10 (Save & Exit)."
  Write-Host ""
  Write-Host "  Kalau setelan itu TIDAK ADA sama sekali:" -ForegroundColor DarkGray
  Write-Host "    BIOS-nya dikunci pabrikan/admin, CPU-nya tidak mendukung, atau"
  Write-Host "    BIOS perlu di-update. Tanyakan ke yang mengurus komputer ini."
}

# =====================================================================
#  MULAI
# =====================================================================
Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " TORANG -- PEMASANG OpenClaw + Hermes  v$Versi" -ForegroundColor Cyan
Write-Host " PC: $env:COMPUTERNAME   akun: $env:USERNAME   $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan

$identitas = [Security.Principal.WindowsIdentity]::GetCurrent()
$prinsipal = New-Object Security.Principal.WindowsPrincipal($identitas)
$Elevated  = $prinsipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$state = Baca-State
if (-not $state) { $state = State-Baru }

# ---------------------------------------------------------------- CEK 0a
#  Akun Windows harus sama dengan yang tercatat.
Judul "[CEK 0] Hak akses dan akun Windows"

if ($state.user_windows -and ($state.user_windows -ne $env:USERNAME)) {
  Kotak @(
    "BERHENTI -- akun Windows berbeda.",
    "",
    "Pemasangan ini dimulai di akun : $($state.user_windows)",
    "Sekarang kamu memakai akun     : $env:USERNAME",
    "",
    "Kenapa ini penting: Ubuntu (WSL) terdaftar PER AKUN Windows.",
    "Ubuntu milik akun sebelah TIDAK terlihat dari sini, dan kalau",
    "diteruskan, komputer ini akan punya DUA Ubuntu yang saling",
    "berebut -- lalu OpenClaw terasa 'hilang' dan dashboard-nya tidak",
    "mau terbuka.",
    "",
    "Yang harus kamu lakukan -- pilih satu:",
    " 1. Sign out (JANGAN Switch user), masuk ke akun '$($state.user_windows)',",
    "    lalu jalankan PASANG.bat di sana.",
    " 2. Kalau memang sengaja mau memasang di akun ini juga, hapus dulu",
    "    catatan lamanya secara sadar:",
    "    $StateFile",
    "",
    "Rujukan lengkap: PANDUAN-DUA-AKUN-WINDOWS.md di torang-murid."
  ) 'Red'
  exit 1
}
Ok "akun Windows: $env:USERNAME"

# ---------------------------------------------------------------- CEK 0b
#  Sudahkah tahap yang butuh Administrator selesai?
$st1 = Status-Cek $state 'cek1_virtualisasi'
$st2 = Status-Cek $state 'cek2_fitur'
$TahapAdminSelesai = ($st1 -eq 'LULUS') -and (($st2 -eq 'LULUS') -or ($st2 -eq 'DIPERBAIKI-OTOMATIS'))

$PesanR4 = @(
  "Bagian yang butuh hak Administrator sudah selesai.",
  "",
  "Sekarang TUTUP jendela ini, lalu jalankan PASANG.bat lagi dengan",
  "DOBEL-KLIK BIASA -- JANGAN klik kanan, JANGAN Run as Administrator.",
  "",
  "Kenapa: supaya installer membaca daftar Ubuntu milik akun Windows-mu",
  "sendiri, bukan daftar milik akun lain."
)
if ($ViaBootstrap) {
  # Jalur satu-baris: perintah irm ... | iex TIDAK menaikkan hak akses
  # sendiri, jadi menjalankannya lagi memang cara yang benar di sini.
  $PesanR4 += @(
    "",
    "Kamu memakai perintah PowerShell satu-baris. Untuk melanjutkan,",
    "jalankan lagi perintah  irm ... | iex  yang sama di jendela",
    "PowerShell BIASA (bukan yang Run as Administrator).",
    "Berkasnya sudah ada, jadi tidak akan diunduh ulang."
  )
}

if ($TahapAdminSelesai -and $Elevated) {
  # PENGAMAN 2 -- user refleks klik kanan lagi. Jangan lanjut CEK 3
  # dalam kondisi elevated; keluar dengan bersih, bukan error.
  Ok "cek yang butuh Administrator sudah lulus sebelumnya"
  Kotak $PesanR4 'Yellow'
  exit 0
}

if (-not $TahapAdminSelesai -and -not $Elevated) {
  # Naikkan hak akses sendiri, lalu jendela ini tutup.
  Warn "cek berikutnya butuh hak Administrator -- meminta izin sekarang"
  Obat "Jendela baru akan terbuka. Jawab 'Yes' pada kotak izin Windows."
  try {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($MyInvocation.MyCommand.Path)`""
    ) | Out-Null
    exit 0
  } catch {
    Bad "Windows menolak menaikkan hak akses."
    Obat "Apa yang gagal : kotak izin Administrator tidak muncul / ditolak."
    Obat "Kenapa biasanya: akun ini bukan Administrator, atau kotak izinnya"
    Obat "                 diklik 'No'."
    Obat "Lakukan        : klik kanan PASANG.bat > Run as Administrator,"
    Obat "                 lalu jawab Yes."
    exit 1
  }
}

if ($Elevated) { Ok "berjalan sebagai Administrator (untuk CEK 1 dan CEK 2)" }
else           { Ok "berjalan sebagai pengguna biasa (benar untuk CEK 3 ke atas)" }

Set-Cek $state 'cek0_hak_akses' 'LULUS' @{ elevated = $Elevated }
Tulis-State $state

# =====================================================================
#  BAGIAN A -- yang butuh Administrator  (CEK 1 dan CEK 2)
# =====================================================================
if (-not $TahapAdminSelesai) {

  # -------------------------------------------------------------- CEK 1
  Judul "[CEK 1] Virtualisasi CPU"

  $cpu = $null; $cs = $null
  try { $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1 } catch { }
  try { $cs  = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch { }

  $merek = if ($cs) { "$($cs.Manufacturer)" } else { '(tidak terbaca)' }
  $model = if ($cs) { "$($cs.Model)" }        else { '' }
  $vfe   = if ($cpu) { $cpu.VirtualizationFirmwareEnabled } else { $null }
  $hyp   = if ($cs)  { $cs.HypervisorPresent }              else { $null }
  $slat  = if ($cpu) { $cpu.SecondLevelAddressTranslationExtensions } else { $null }

  Write-Host "         merek/model : $merek $model" -ForegroundColor DarkGray
  Write-Host "         VirtualizationFirmwareEnabled = $vfe ; HypervisorPresent = $hyp" -ForegroundColor DarkGray

  if ($slat -eq $false) {
    # Jalan buntu yang sesungguhnya. Jangan kirim orang ke BIOS untuk
    # setelan yang tidak akan menyelesaikan apa pun.
    Bad "Prosesor komputer ini tidak mendukung SLAT."
    Obat "Artinya WSL2 TIDAK AKAN BISA jalan di sini, sekalipun semua"
    Obat "setelan BIOS sudah benar. Ini batas perangkat kerasnya."
    Obat "Pilihan yang tersisa: pakai komputer lain, atau pasang OpenClaw"
    Obat "dan Hermes di VPS/Mac (lihat PANDUAN-PASANG.md)."
    Set-Cek $state 'cek1_virtualisasi' 'PERLU-TINDAKAN-USER' @{ merek = $merek; model = $model; slat = $false }
    $state.catatan_terakhir = 'CPU tidak mendukung SLAT -- WSL2 tidak mungkin.'
    Tulis-State $state
    exit 1
  }

  if ($hyp -eq $true) {
    Ok "virtualisasi aktif (hypervisor sudah berjalan)"
    Set-Cek $state 'cek1_virtualisasi' 'LULUS' @{ merek = $merek; model = $model; hypervisor_present = $true }
  }
  elseif ($vfe -eq $true) {
    Ok "virtualisasi aktif di firmware"
    Set-Cek $state 'cek1_virtualisasi' 'LULUS' @{ merek = $merek; model = $model; firmware_enabled = $true }
  }
  elseif ($vfe -eq $false) {
    Bad "Virtualisasi MATI di BIOS komputer ini."
    Obat "Ini satu-satunya bagian yang TIDAK BISA diperbaiki oleh skrip --"
    Obat "setelannya ada di firmware, di luar jangkauan Windows."
    Panduan-Bios $merek $model
    $state.bios_perlu_tindakan = $true
    Set-Cek $state 'cek1_virtualisasi' 'PERLU-TINDAKAN-USER' @{ merek = $merek; model = $model; firmware_enabled = $false }
    $state.tahap = 'bios'
    $state.catatan_terakhir = 'Menunggu virtualisasi diaktifkan di BIOS.'
    Tulis-State $state
    Kotak (@(
      "LANGKAH BERIKUTNYA",
      "",
      "1. Restart komputer dan masuk BIOS (lihat cara di atas).",
      "2. Aktifkan virtualisasi, simpan (F10).",
      "3. Setelah Windows menyala lagi, jalankan PASANG.bat lagi.",
      "",
      "Installer akan melanjutkan sendiri dari cek berikutnya --",
      "tidak mengulang dari nol."
    ) + (Baris-Lanjut)) 'Yellow'
    exit 1
  }
  else {
    Warn "status virtualisasi tidak terbaca di komputer ini."
    Obat "Ini bisa normal. Pemasangan dilanjutkan; kalau nanti WSL gagal"
    Obat "menyala dengan kode 0x80370102, artinya memang virtualisasinya"
    Obat "mati dan kamu perlu masuk BIOS."
    Set-Cek $state 'cek1_virtualisasi' 'LULUS' @{ merek = $merek; model = $model; catatan = 'tidak terbaca, dilanjutkan' }
  }
  Tulis-State $state

  # -------------------------------------------------------------- CEK 2
  Judul "[CEK 2] Fitur Windows untuk WSL"
  $perluRestart = $false
  $adaPerbaikan = $false

  foreach ($fitur in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
    $f = $null
    try { $f = Get-WindowsOptionalFeature -Online -FeatureName $fitur -ErrorAction Stop } catch { }
    if (-not $f) {
      Warn "fitur '$fitur' tidak bisa dibaca -- dicoba diaktifkan saja"
    }
    if ($f -and $f.State -eq 'Enabled') {
      Ok "fitur sudah aktif: $fitur"
      continue
    }
    Write-Host "         mengaktifkan: $fitur ..." -ForegroundColor DarkGray
    try {
      # -NoRestart WAJIB: kita yang mengatur kapan restart, bukan DISM.
      $hasil = Enable-WindowsOptionalFeature -Online -FeatureName $fitur -All -NoRestart -ErrorAction Stop
      $adaPerbaikan = $true
      Ok "fitur diaktifkan: $fitur"
      if ($hasil -and $hasil.RestartNeeded) { $perluRestart = $true }
    } catch {
      $pesan = "$_"
      Bad "gagal mengaktifkan fitur '$fitur'."
      if (-not (Jelaskan-ErrorWsl $pesan)) {
        Obat "Pesan Windows: $pesan"
        Obat "Kenapa biasanya: Windows perlu di-update, atau kebijakan"
        Obat "                 admin IT memblokir perubahan fitur."
        Obat "Lakukan: jalankan Windows Update sampai tuntas, lalu ulangi."
      }
      Set-Cek $state 'cek2_fitur' 'PERLU-TINDAKAN-USER' @{ fitur_gagal = $fitur }
      Tulis-State $state
      exit 1
    }
  }

  # hypervisorlaunchtype: kalau Off, WSL2 tidak akan menyala walau semua
  # fitur aktif. Ini butuh Administrator, jadi tempatnya memang di sini.
  try {
    $bcd = (& bcdedit /enum 2>&1 | Out-String)
    if ($bcd -match 'hypervisorlaunchtype\s+Off') {
      Write-Host "         hypervisorlaunchtype = Off -> diubah ke Auto" -ForegroundColor DarkGray
      & bcdedit /set hypervisorlaunchtype Auto 2>&1 | Out-Null
      $adaPerbaikan = $true
      $perluRestart = $true
      Ok "hypervisor diaktifkan di konfigurasi boot"
    } else {
      Ok "konfigurasi boot hypervisor wajar"
    }
  } catch {
    Warn "tidak bisa membaca konfigurasi boot (bcdedit) -- dilewati"
  }

  # PENTING: JANGAN memakai `wsl --install` bentuk gabungan di sini.
  # Aktivasi fitur (Fase A) dan pemasangan distro (Fase B) harus dipisah
  # oleh restart. Bentuk gabungan sering putus sambungannya setelah
  # restart, distro tertinggal di status Installing, lalu orang mengulang
  # dengan nama paket berbeda -- dan Ubuntu jadi dobel.
  Write-Host "         menyiapkan WSL tanpa memasang distro ..." -ForegroundColor DarkGray
  $o = Wsl-Keluaran @('--install', '--no-distribution')
  if ($o) { $o | ForEach-Object { Write-Host "         | $_" -ForegroundColor DarkGray } }

  Write-Host "         wsl --update ..." -ForegroundColor DarkGray
  $o = Wsl-Keluaran @('--update')
  if ($o) { $o | ForEach-Object { Write-Host "         | $_" -ForegroundColor DarkGray } }

  $o = Wsl-Keluaran @('--set-default-version', '2')
  if ("$o" -match '0x1bc') {
    Warn "WSL minta kernelnya diperbarui (0x1bc)."
    Obat "Sudah dicoba lewat 'wsl --update' barusan. Kalau tetap muncul"
    Obat "setelah restart, jalankan sendiri: wsl --update"
    $perluRestart = $true
  } else {
    Ok "WSL2 dijadikan versi bawaan"
  }

  $statusCek2 = if ($adaPerbaikan) { 'DIPERBAIKI-OTOMATIS' } else { 'LULUS' }
  Set-Cek $state 'cek2_fitur' $statusCek2 @{ restart_diminta = $perluRestart }
  $state.perlu_restart = $perluRestart
  Tulis-State $state

  if ($perluRestart) {
    $state.tahap = 'fitur'
    $state.catatan_terakhir = 'Menunggu restart setelah fitur Windows diaktifkan.'
    Tulis-State $state
    Kotak (@(
      "RESTART DULU",
      "",
      "Fitur Windows untuk WSL baru saja diaktifkan. Windows perlu",
      "restart supaya fitur itu benar-benar hidup.",
      "",
      "1. Restart komputer sekarang.",
      "2. Setelah menyala lagi, jalankan PASANG.bat lagi.",
      "",
      "Installer melanjutkan sendiri dari cek berikutnya."
    ) + (Baris-Lanjut)) 'Yellow'
    exit 0
  }

  # Tahap Administrator tuntas tanpa perlu restart -> titik R4.
  $state.tahap = 'distro'
  $state.butuh_elevasi = $false
  $state.catatan_terakhir = 'Tahap Administrator selesai. Lanjutkan tanpa elevasi.'
  Tulis-State $state
  Kotak $PesanR4 'Yellow'
  exit 0
}

# =====================================================================
#  BAGIAN B -- TANPA Administrator  (CEK 3, 3b, 4, lalu pasang)
# =====================================================================
Ok "CEK 1 dan CEK 2 sudah lulus sebelumnya -- lanjut ke tahap distro"

# ---------------------------------------------------------------- CEK 3
Judul "[CEK 3] Distro Ubuntu di akun ini"

$barisWsl = Wsl-Keluaran @('--list', '--all', '--verbose')
if (-not $barisWsl) { $barisWsl = Wsl-Keluaran @('--list', '--verbose') }

$daftar = @()
foreach ($b in $barisWsl) {
  if ($b -notmatch 'ubuntu') { continue }          # header ikut tersaring di sini
  $t = ($b -replace '^\s*\*', '').Trim()
  $bagian = @($t -split '\s+' | Where-Object { $_ -ne '' })
  if ($bagian.Count -lt 1) { continue }
  $daftar += [pscustomobject]@{
    nama    = $bagian[0]
    status  = if ($bagian.Count -ge 2) { $bagian[1] } else { '?' }
    versi   = if ($bagian.Count -ge 3) { $bagian[2] } else { '?' }
    bawaan  = ($b -match '^\s*\*')
  }
}

$distro = $null
$dipasangOlehKami = $false

if ($daftar.Count -eq 0) {
  # --- kasus d: belum ada Ubuntu sama sekali ---
  Warn "belum ada Ubuntu di akun Windows ini"
  Kotak @(
    "SEBENTAR LAGI UBUNTU AKAN DIPASANG",
    "",
    "Ubuntu akan meminta kamu membuat username dan password LINUX.",
    "Itu BUKAN password Windows-mu.",
    "",
    "PENTING: password TIDAK TERLIHAT saat diketik. Layarnya diam",
    "saja. Itu normal, keyboard-mu tidak rusak. Ketik saja, lalu Enter.",
    "",
    "Username: huruf kecil semua, tanpa spasi.",
    "Ingat password-nya -- nanti dipakai untuk perintah 'sudo'."
  ) 'Cyan'
  Write-Host "  Menekan Enter akan memulai pemasangan Ubuntu ($DistroKanonik)."
  Read-Host  "  Tekan Enter kalau sudah siap" | Out-Null

  $o = Wsl-Keluaran @('--install', '--distribution', $DistroKanonik, '--no-launch')
  if ($o) { $o | ForEach-Object { Write-Host "         | $_" -ForegroundColor DarkGray } }
  if ("$o" -match 'error|gagal|0x') {
    if (-not (Jelaskan-ErrorWsl "$o")) {
      Warn "pemasangan lewat Microsoft Store bermasalah -- mencoba unduhan langsung"
    }
    $o = Wsl-Keluaran @('--install', '--distribution', $DistroKanonik, '--no-launch', '--web-download')
    if ($o) { $o | ForEach-Object { Write-Host "         | $_" -ForegroundColor DarkGray } }
  }

  Write-Host ""
  Write-Host "  Ubuntu akan terbuka sekarang untuk pembuatan username/password." -ForegroundColor Yellow
  Write-Host "  Setelah selesai, ketik: exit    lalu tekan Enter." -ForegroundColor Yellow
  Write-Host ""
  & wsl.exe -d $DistroKanonik
  $distro = $DistroKanonik
  $dipasangOlehKami = $true
}
elseif ($daftar.Count -eq 1) {
  $d = $daftar[0]
  Ok "ditemukan satu Ubuntu: $($d.nama)  (status: $($d.status), WSL$($d.versi))"
  $distro = $d.nama
  if ($d.versi -eq '1') {
    # --- kasus e: WSL1 ---
    Warn "'$($d.nama)' masih WSL versi 1. OpenClaw dan Hermes butuh WSL2."
    Obat "Konversi bisa lama dan pada distro besar bisa gagal di tengah."
    Obat "Kalau ada data penting di dalamnya, cadangkan dulu."
    $jwb = (Read-Host "  Konversi '$($d.nama)' ke WSL2 sekarang? (y = ya)").Replace("`r", '').ToLower()
    if ($jwb -eq 'y' -or $jwb -eq 'ya') {
      Write-Host "         mengkonversi (ini bisa beberapa menit) ..." -ForegroundColor DarkGray
      $o = Wsl-Keluaran @('--set-version', $d.nama, '2')
      if ($o) { $o | ForEach-Object { Write-Host "         | $_" -ForegroundColor DarkGray } }
      if ("$o" -match 'virtual disk system limitation') { Jelaskan-ErrorWsl "$o" | Out-Null }
    } else {
      Bad "dibatalkan -- pemasangan tidak bisa dilanjutkan di WSL1."
      exit 1
    }
  }
  if ($d.status -match 'Installing') {
    # --- kasus b: distro menggantung ---
    Warn "status distro ini 'Installing' -- penyiapannya belum pernah selesai."
    Obat "Biasanya karena pemasangan terputus di tengah."
    Obat "Kita coba selesaikan dengan meluncurkannya sekali."
    Write-Host ""
    Write-Host "  Ubuntu akan terbuka. Kalau diminta username/password Linux," -ForegroundColor Yellow
    Write-Host "  isi seperti biasa (password tidak terlihat saat diketik)." -ForegroundColor Yellow
    Write-Host "  Setelah selesai, ketik: exit" -ForegroundColor Yellow
    Write-Host ""
    & wsl.exe -d $d.nama
  }
}
else {
  # --- kasus c: LEBIH DARI SATU ---
  Bad "ada $($daftar.Count) Ubuntu terpasang di akun ini."
  Obat "Ini yang membuat OpenClaw terasa 'hilang' dan dashboard tidak mau"
  Obat "terbuka: tiap Ubuntu punya home Linux sendiri, dan keduanya bisa"
  Obat "berebut port yang sama."
  Obat "Penjelasan lengkap ada di PANDUAN-PASANG.md, bagian masalah umum."
  Write-Host ""
  for ($i = 0; $i -lt $daftar.Count; $i++) {
    $d = $daftar[$i]
    $tanda = if ($d.bawaan) { '  <-- sekarang jadi bawaan' } else { '' }
    Write-Host ("   [{0}] {1}   status: {2}   WSL{3}{4}" -f ($i + 1), $d.nama, $d.status, $d.versi, $tanda)
  }
  Write-Host ""
  Write-Host "  Pilih SATU yang akan dipakai untuk OpenClaw + Hermes." -ForegroundColor Yellow
  Write-Host "  Yang lain TIDAK akan disentuh dan TIDAK akan dihapus." -ForegroundColor Yellow
  Write-Host ""
  $pilih = 0
  while ($pilih -lt 1 -or $pilih -gt $daftar.Count) {
    $jwb = (Read-Host "  Nomor pilihanmu (1-$($daftar.Count))").Replace("`r", '').Trim()
    if ($jwb -match '^\d+$') { $pilih = [int]$jwb }
  }
  $distro = $daftar[$pilih - 1].nama
  Ok "dipilih: $distro"
  Write-Host ""
  Write-Host "  Kalau nanti mau membuang Ubuntu yang tidak terpakai, perintahnya:" -ForegroundColor DarkGray
  Write-Host "     wsl --unregister <nama>" -ForegroundColor DarkGray
  Write-Host "  PERINGATAN: perintah itu MEMUSNAHKAN seluruh isi distro itu --" -ForegroundColor DarkGray
  Write-Host "  semua file, semua pengaturan, tidak bisa dikembalikan." -ForegroundColor DarkGray
  Write-Host "  Kami sengaja tidak menjalankannya untukmu." -ForegroundColor DarkGray
}

if (-not $distro) {
  Bad "tidak ada distro yang bisa dipakai."
  exit 1
}

Write-Host "         menjadikan '$distro' sebagai distro bawaan ..." -ForegroundColor DarkGray
Wsl-Keluaran @('--set-default', $distro) | Out-Null

# --------------------------------------------------------------- CEK 3b
Judul "[CEK 3b] Kesehatan distro '$distro'"

$ujiEcho = Wsl-Keluaran @('-d', $distro, '--', 'echo', 'ok')
$ujiUser = Wsl-Keluaran @('-d', $distro, '--', 'id', '-un')
$namaUser = if ($ujiUser) { "$($ujiUser[-1])".Trim() } else { '' }

$sehat = $true
if ("$ujiEcho" -notmatch 'ok') {
  Bad "distro '$distro' tidak menjawab uji hidup."
  if (-not (Jelaskan-ErrorWsl "$ujiEcho")) {
    Obat "Pesan mentahnya: $ujiEcho"
    Obat "Kenapa biasanya: WSL belum benar-benar hidup setelah restart,"
    Obat "                 atau distro-nya belum selesai disiapkan."
    Obat "Coba: wsl --shutdown  lalu jalankan PASANG.bat lagi."
  }
  $sehat = $false
} else {
  Ok "distro menjawab: ok"
}

if ($sehat) {
  if (-not $namaUser) {
    Bad "tidak bisa membaca user Linux di dalam distro."
    $sehat = $false
  } elseif ($namaUser -eq 'root') {
    # Distro terpasang tapi belum pernah dibuatkan user biasa. Uji 'echo ok'
    # lolos, tapi seluruh pemasangan kita mengandaikan user biasa --
    # skrip oc-* menolak root. Distro seperti inilah yang bikin orang
    # mengulang instalasi dan berakhir punya dua Ubuntu.
    Bad "distro ini masuk sebagai 'root' -- user Linux biasa belum dibuat."
    Obat "Distro terpasang, tapi penyiapannya belum selesai."
    Obat "Lakukan: buka Ubuntu sekali dari Start Menu, buat username dan"
    Obat "         password Linux (password tidak terlihat saat diketik),"
    Obat "         lalu jalankan PASANG.bat lagi."
    Obat "JANGAN memasang Ubuntu lagi -- yang ini tinggal diselesaikan."
    $sehat = $false
  } else {
    Ok "user Linux: $namaUser (bukan root)"
  }
}

if (-not $sehat) {
  # DEFINISI SELESAI belum terpenuhi -> state TIDAK BOLEH menandai selesai.
  Set-Cek $state 'cek3_distro' 'PERLU-TINDAKAN-USER' @{ distro_terpilih = $distro }
  Set-Cek $state 'cek3b_kesehatan' 'PERLU-TINDAKAN-USER' @{ echo_ok = $false; user_linux = $namaUser }
  $state.catatan_terakhir = "Distro '$distro' belum lulus uji hidup."
  Tulis-State $state
  exit 1
}

$namaDaftar = @()
foreach ($d in $daftar) { $namaDaftar += $d.nama }
if ($namaDaftar.Count -eq 0) { $namaDaftar = @($distro) }

Set-Cek $state 'cek3_distro' 'LULUS' @{
  distro_terpilih   = $distro
  distro_terlihat   = $namaDaftar
  dipasang_oleh_kami = $dipasangOlehKami
}
Set-Cek $state 'cek3b_kesehatan' 'LULUS' @{ echo_ok = $true; user_linux = $namaUser }
$state.tahap = 'siap'
Tulis-State $state

# ---------------------------------------------------------------- CEK 4
Judul "[CEK 4] Jaringan dan ruang disk"

$jaringanOk = $true
foreach ($alamat in @('https://openclaw.ai/install.sh', 'https://hermes-agent.nousresearch.com/install.sh')) {
  try {
    Invoke-WebRequest -Uri $alamat -Method Head -TimeoutSec 20 -UseBasicParsing -ErrorAction Stop | Out-Null
    Ok "bisa menjangkau $alamat"
  } catch {
    Bad "TIDAK bisa menjangkau $alamat"
    Obat "Kenapa biasanya: internet mati, atau proxy/firewall sekolah"
    Obat "                 memblokir alamat ini."
    Obat "Lakukan: perbaiki jaringan dulu. Pemasangan tidak akan dimulai,"
    Obat "         jadi belum ada apa pun yang berubah di komputer ini."
    $jaringanOk = $false
  }
}

$diskOk = $true
$bebasMB = $null
try {
  $huruf = $env:SystemDrive.Substring(0, 1)
  $drv = Get-PSDrive -Name $huruf -ErrorAction Stop
  $bebasMB = [math]::Floor($drv.Free / 1MB)
  if ($bebasMB -lt $DiskMinMB) {
    Bad "ruang kosong drive $huruf`: hanya $bebasMB MB, butuh minimal $DiskMinMB MB."
    Obat "OpenClaw + Hermes + Chromium sekitar 3 GB, sisanya margin untuk"
    Obat "berkas disk WSL yang ikut membesar."
    Obat "Lakukan: kosongkan dulu, lalu jalankan PASANG.bat lagi."
    $diskOk = $false
  } else {
    Ok "ruang disk cukup ($bebasMB MB kosong)"
  }
} catch {
  Warn "ruang disk tidak bisa dibaca -- dilanjutkan, tapi awasi sendiri"
}

Set-Cek $state 'cek4_jaringan_disk' $(if ($jaringanOk -and $diskOk) { 'LULUS' } else { 'PERLU-TINDAKAN-USER' }) @{
  disk_bebas_mb = $bebasMB
  jaringan_ok   = $jaringanOk
}
Tulis-State $state

if (-not $jaringanOk -or -not $diskOk) {
  Kotak @("BERHENTI -- prasyarat belum terpenuhi. Belum ada yang diubah.") 'Red'
  exit 1
}

# =====================================================================
#  RINGKASAN
# =====================================================================
Judul "Ringkasan semua pemeriksaan"
foreach ($nama in @('cek0_hak_akses', 'cek1_virtualisasi', 'cek2_fitur', 'cek3_distro', 'cek3b_kesehatan', 'cek4_jaringan_disk')) {
  $s = Status-Cek $state $nama
  if (-not $s) { $s = '(tidak dijalankan di sesi ini)' }
  $warna = switch ($s) {
    'LULUS'               { 'Green' }
    'DIPERBAIKI-OTOMATIS' { 'Cyan' }
    default               { 'Yellow' }
  }
  Write-Host ("   {0,-22} {1}" -f $nama, $s) -ForegroundColor $warna
}
Write-Host ""
Write-Host "   distro yang dipakai: $distro" -ForegroundColor White

# =====================================================================
#  JALANKAN OTAKNYA DI DALAM WSL
# =====================================================================
Judul "Menjalankan pemasang OpenClaw + Hermes di dalam '$distro'"

$folderWsl = (Wsl-Keluaran @('-d', $distro, '--', 'wslpath', '-a', $FolderSkrip))
$folderWsl = if ($folderWsl) { "$($folderWsl[-1])".Trim() } else { '' }

if (-not $folderWsl) {
  Bad "tidak bisa menerjemahkan lokasi folder installer ke jalur Linux."
  Obat "Lakukan sendiri dari dalam Ubuntu:"
  Obat "  wsl -d $distro"
  Obat "  cd /mnt/<huruf-drive>/... (folder tempat PASANG.bat berada)"
  Obat "  bash pasang-inti.sh"
  exit 1
}

$adaInti = Wsl-Keluaran @('-d', $distro, '--', 'test', '-f', "$folderWsl/pasang-inti.sh", '&&', 'echo', 'ADA')
if ("$adaInti" -notmatch 'ADA') {
  # `test ... && echo` lewat argumen langsung tidak selalu jalan; coba lewat bash -c
  $adaInti = Wsl-Keluaran @('-d', $distro, '--', 'bash', '-c', "test -f '$folderWsl/pasang-inti.sh' && echo ADA")
}
if ("$adaInti" -notmatch 'ADA') {
  Bad "pasang-inti.sh tidak terlihat dari dalam Ubuntu."
  Obat "Jalur yang dicari: $folderWsl/pasang-inti.sh"
  Obat "Kenapa biasanya: folder installer ada di drive jaringan atau"
  Obat "                 lokasi yang tidak bisa dibaca WSL."
  Obat "Lakukan: pindahkan SATU FOLDER installer ini ke drive lokal"
  Obat "         (mis. D:\\ atau C:\\), lalu jalankan PASANG.bat lagi."
  exit 1
}

Write-Host "         lokasi di dalam Ubuntu: $folderWsl" -ForegroundColor DarkGray
Write-Host ""

# SELALU eksplisit -d. Jangan pernah mengandalkan distro bawaan --
# bawaan bisa berubah tanpa kita tahu.
& wsl.exe -d $distro -- bash "$folderWsl/pasang-inti.sh"
$kode = $LASTEXITCODE

$state.tahap = 'selesai'
$state.catatan_terakhir = "pasang-inti.sh selesai dengan kode $kode"
Tulis-State $state

Write-Host ""
if ($kode -eq 0) {
  Kotak @(
    "SELESAI",
    "",
    "OpenClaw dan Hermes sudah terpasang di Ubuntu ($distro).",
    "",
    "Langkah berikutnya ada di layar di atas -- dua perintah yang",
    "harus kamu jalankan sendiri (openclaw onboard, lalu hermes setup)."
  ) 'Green'
} elseif ($kode -eq 2) {
  Kotak @(
    "TERPASANG, TAPI ADA CATATAN",
    "",
    "Baca baris bertanda GAGAL di layar atas.",
    "Sebagian catatan wajar sebelum onboarding dijalankan."
  ) 'Yellow'
} else {
  Kotak @(
    "PEMASANGAN BERHENTI",
    "",
    "Baca pesan di layar atas -- di situ tertulis apa yang gagal dan",
    "apa yang perlu kamu lakukan.",
    "",
    "Catatan lengkapnya ada di file log-pasang.txt di folder ini."
  ) 'Red'
}

exit $kode
