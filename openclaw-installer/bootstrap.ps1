# =====================================================================
#  TORANG -- PINTU SATU-BARIS (Windows)  v1.0
#
#  PAKAI, di PowerShell:
#    irm https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/openclaw-installer/bootstrap.ps1 | iex
#
#  Ini BUKAN pemasangnya. Ini pengambil: ia membuat folder tetap,
#  mengunduh berkas pemasang KE DISK, lalu menjalankannya.
#
#  KENAPA HARUS KE DISK, BUKAN DIJALANKAN DI MEMORI:
#  Pemasangan WSL butuh beberapa kali RESTART komputer. Setelah restart,
#  perintah yang tadi kamu ketik sudah hilang dari memori -- yang tersisa
#  hanya berkas di disk dan catatan state.json. Karena itu semuanya
#  disimpan permanen di:
#
#      %LOCALAPPDATA%\torang-installer\
#
#  Setelah restart kamu punya DUA cara melanjutkan, dua-duanya benar:
#    1. Jalankan lagi perintah irm ... | iex yang sama (paling gampang
#       -- ia akan mendeteksi berkas yang sudah ada dan tidak mengunduh
#       ulang), atau
#    2. Buka folder di atas, klik kanan PASANG.bat > Run as Administrator
#
#  IDEMPOTEN: dijalankan berulang kali tidak pernah menggandakan apa pun
#  dan tidak pernah menghapus state.json.
#
#  PILIHAN (hanya untuk keadaan khusus):
#    $env:TORANG_PAKSA_UNDUH = '1'   -> paksa unduh ulang semua berkas
#    $env:TORANG_BASE_URL = '...'    -> ambil berkas dari sumber lain
# =====================================================================

$ErrorActionPreference = 'Stop'

$Versi   = '1.0'
$BaseUrl = if ($env:TORANG_BASE_URL) { $env:TORANG_BASE_URL } else {
             'https://raw.githubusercontent.com/yuzuruzero/torang-murid/main/openclaw-installer' }
$Rumah   = Join-Path $env:LOCALAPPDATA 'torang-installer'
$Penanda = Join-Path $Rumah 'via-bootstrap.txt'
$LogFile = Join-Path $Rumah 'log-unduh.txt'

# Berkas yang WAJIB ada supaya pemasang bisa jalan utuh.
# pasang-inti.sh dan verifikasi.sh ikut karena pasang.ps1 memanggil
# keduanya sebagai tetangga di folder yang sama.
$Berkas = @('PASANG.bat', 'pasang.ps1', 'pasang-inti.sh', 'verifikasi.sh')

# raw.githubusercontent menyajikan berkas persis seperti tersimpan di repo,
# dan repo menyimpan SEMUA berkas teks dengan akhir baris LF. Untuk .bat itu
# salah: cmd.exe bisa salah membaca berkas .bat ber-LF. Jadi setelah diunduh,
# .bat dan .ps1 dikembalikan ke CRLF di disk.
#
# Jalur ZIP tidak kena masalah ini -- tombol Download ZIP memakai git archive
# yang memulihkan CRLF sesuai .gitattributes. Yang perlu diperbaiki hanya
# jalur unduh satu-baris ini.
#
# Berkas .sh JANGAN disentuh: itu dijalankan di dalam WSL dan CRLF di sana
# menghasilkan "bad interpreter: /usr/bin/env bash^M".
function Jadikan-CRLF($path) {
  try {
    $isi = [System.IO.File]::ReadAllText($path)
    $isi = ($isi -replace "`r`n", "`n") -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText($path, $isi)
    return $true
  } catch { return $false }
}

function Catat($teks) {
  $baris = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $teks
  try { Add-Content -Path $LogFile -Value $baris -Encoding UTF8 } catch { }
}
function Ok  ($m) { Write-Host "  [ OK ] " -ForegroundColor Green  -NoNewline; Write-Host $m; Catat "OK   $m" }
function Bad ($m) { Write-Host "  [GAGAL]" -ForegroundColor Red    -NoNewline; Write-Host " $m"; Catat "GAGAL $m" }
function Warn($m) { Write-Host "  [ ?  ] " -ForegroundColor Yellow -NoNewline; Write-Host $m; Catat "?    $m" }
function Obat($m) { Write-Host "         -> $m" -ForegroundColor DarkGray }

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " TORANG -- pengambil pemasang OpenClaw + Hermes  v$Versi" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------------
#  1. Siapkan folder tetap
# ---------------------------------------------------------------------
if (-not (Test-Path $Rumah)) {
  New-Item -ItemType Directory -Path $Rumah -Force | Out-Null
  Ok "folder dibuat: $Rumah"
} else {
  Ok "folder sudah ada: $Rumah"
}
Catat "--- bootstrap v$Versi dijalankan, sumber $BaseUrl ---"

# ---------------------------------------------------------------------
#  2. Apakah perlu mengunduh?
#     Idempoten: kalau semua berkas sudah ada dan tidak dipaksa,
#     lewati unduhan dan langsung lanjut.
# ---------------------------------------------------------------------
$semuaAda = $true
foreach ($b in $Berkas) {
  $p = Join-Path $Rumah $b
  if (-not (Test-Path $p) -or ((Get-Item $p).Length -eq 0)) { $semuaAda = $false }
}
$adaState = Test-Path (Join-Path $Rumah 'state.json')
$paksa    = ($env:TORANG_PAKSA_UNDUH -eq '1')

if ($semuaAda -and -not $paksa) {
  Ok "berkas pemasang sudah lengkap -- tidak diunduh ulang"
  if ($adaState) {
    Ok "catatan kemajuan (state.json) ditemukan -- melanjutkan dari tahap terakhir"
  }
} else {
  if ($paksa) { Warn "TORANG_PAKSA_UNDUH=1 -- semua berkas diunduh ulang" }

  # TLS 1.2 wajib disebut eksplisit di Windows lama; tanpa ini unduhan
  # dari GitHub gagal dengan pesan yang membingungkan.
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  } catch { }

  $gagal = 0
  foreach ($b in $Berkas) {
    $url    = "$BaseUrl/$b"
    $tujuan = Join-Path $Rumah $b
    $tmp    = "$tujuan.baru"
    Write-Host ("  mengunduh {0,-16} ... " -f $b) -NoNewline
    try {
      Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
      if ((Get-Item $tmp).Length -le 0) { throw "berkas kosong" }
      Move-Item -Force -Path $tmp -Destination $tujuan
      $ukuran = (Get-Item $tujuan).Length
      $sidik  = (Get-FileHash -Path $tujuan -Algorithm SHA256).Hash
      Write-Host "OK" -ForegroundColor Green
      Catat "unduh $b url=$url size=$ukuran sha256=$sidik"
    } catch {
      Write-Host "GAGAL" -ForegroundColor Red
      Catat "GAGAL unduh $b url=$url pesan=$_"
      if (Test-Path $tmp) { Remove-Item -Force $tmp -ErrorAction SilentlyContinue }
      $gagal++
    }
  }

  if ($gagal -gt 0) {
    Write-Host ""
    Bad "$gagal berkas gagal diunduh."
    Obat "Kenapa biasanya: internet terputus, atau proxy/firewall sekolah"
    Obat "                 memblokir raw.githubusercontent.com."
    Obat "Belum ada apa pun yang dipasang di komputer ini."
    Obat ""
    Obat "Jalur cadangan yang selalu bisa dipakai:"
    Obat "  1. Buka https://github.com/yuzuruzero/torang-murid"
    Obat "  2. Klik Code > Download ZIP, lalu ekstrak"
    Obat "  3. Masuk folder openclaw-installer"
    Obat "  4. Klik kanan PASANG.bat > Run as Administrator"
    exit 1
  }
  Ok "semua berkas pemasang siap"
}

# Kembalikan akhir baris .bat dan .ps1 ke CRLF. Dijalankan SELALU, juga saat
# unduhan dilewati -- aman diulang, hasilnya sama.
foreach ($b in @('PASANG.bat', 'pasang.ps1')) {
  $p = Join-Path $Rumah $b
  if (Test-Path $p) {
    if (Jadikan-CRLF $p) { Catat "eol $b -> CRLF" }
    else { Warn "tidak bisa merapikan akhir baris $b (biasanya tidak fatal)" }
  }
}

# Penanda: dipakai pasang.ps1 untuk tahu bahwa pengguna datang lewat
# jalur satu-baris, supaya pesan lanjutannya menyebut cara yang sesuai.
try {
  [System.IO.File]::WriteAllText($Penanda, "bootstrap v$Versi $(Get-Date -Format 'o')")
} catch { }

# ---------------------------------------------------------------------
#  3. Jalankan pemasangnya
# ---------------------------------------------------------------------
$Ps1 = Join-Path $Rumah 'pasang.ps1'
if (-not (Test-Path $Ps1)) {
  Bad "pasang.ps1 tidak ditemukan setelah unduhan."
  Obat "Coba lagi dengan: `$env:TORANG_PAKSA_UNDUH='1'; irm $BaseUrl/bootstrap.ps1 | iex"
  exit 1
}

Write-Host ""
Write-Host "  Berkas tersimpan permanen di:" -ForegroundColor DarkGray
Write-Host "     $Rumah" -ForegroundColor DarkGray
Write-Host "  Kalau nanti diminta restart, jalankan lagi perintah yang sama," -ForegroundColor DarkGray
Write-Host "  atau klik kanan PASANG.bat di folder itu > Run as Administrator." -ForegroundColor DarkGray
Write-Host ""

# Dijalankan sebagai proses PowerShell terpisah, bukan dot-source.
# Alasannya: pasang.ps1 memakai $MyInvocation.MyCommand.Path untuk
# menemukan folder dirinya sendiri dan untuk menaikkan hak akses. Kalau
# di-dot-source dari `irm | iex`, jalur itu kosong dan skrip tidak bisa
# menemukan berkas tetangganya.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Ps1
$kode = $LASTEXITCODE

Catat "pasang.ps1 selesai dengan kode $kode"
exit $kode
