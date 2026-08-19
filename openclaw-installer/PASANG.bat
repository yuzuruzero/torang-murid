@echo off
rem ====================================================================
rem  TORANG -- PEMASANG OpenClaw + Hermes  (pintu Windows)
rem
rem  SATU CARA UNTUK SEMUA KOMPUTER WINDOWS:
rem     klik kanan file ini -> Run as Administrator
rem
rem  Kalau diminta restart: restart, lalu jalankan file YANG SAMA lagi.
rem  Ulangi sampai muncul tulisan SELESAI.
rem
rem  File ini aman dijalankan berulang kali. Ia tidak pernah menggandakan
rem  apa pun; ia melanjutkan dari tempat berhenti.
rem
rem  Isinya cuma pemanggil. Semua logikanya ada di pasang.ps1 di folder
rem  yang sama -- termasuk keputusan kapan butuh hak Administrator dan
rem  kapan JUSTRU tidak boleh.
rem ====================================================================
setlocal

if not exist "%~dp0pasang.ps1" (
  echo.
  echo   GAGAL: file pasang.ps1 tidak ada di folder ini.
  echo.
  echo   Apa yang gagal : pemasang tidak menemukan otak skripnya.
  echo   Kenapa biasanya: PASANG.bat disalin sendirian, tanpa file lain.
  echo   Yang harus kamu lakukan: salin SATU FOLDER penuh, bukan satu file.
  echo   Folder itu minimal harus berisi:
  echo       PASANG.bat  pasang.ps1  pasang-inti.sh  verifikasi.sh
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pasang.ps1"
set KODE=%ERRORLEVEL%

echo.
if not "%KODE%"=="0" echo   (kode keluar: %KODE%)
pause
exit /b %KODE%
