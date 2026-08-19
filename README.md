# torang-murid

Perkakas kelas AI-agent Torang: pemasang, pembersih, dan monitor untuk PC murid.

| Folder | Isi |
|---|---|
| [`openclaw-installer/`](openclaw-installer) | **torang-installer** — pemasang OpenClaw + Hermes untuk Windows (lewat WSL), macOS, dan VPS. Orkestrator: menjalankan installer resmi, memverifikasi, menawarkan rollback bila gagal. |
| [`openclaw-cleanup/`](openclaw-cleanup) | Pembersih OpenClaw + Hermes + Torang Event sampai bersih, plus plugin Claude Code (uninstall / reset / verify). |
| [`torang-events/`](torang-events) | Plugin OpenClaw untuk telemetri kelas. |

Pemasangan murid (monitor + plugin): `install.sh`.
Panduan lengkap ada di dalam masing-masing folder.
