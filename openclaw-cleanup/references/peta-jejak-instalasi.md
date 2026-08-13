# Peta jejak instalasi OpenClaw + Hermes + Torang Event (Ubuntu/WSL)

Sumber kebenaran untuk semua jejak yang ditinggalkan ketiga komponen.
Dipakai skrip plugin; baca ini kalau harus improvisasi manual.

## Cara masing-masing biasanya terpasang

| Komponen | Jalur resmi | Metode lain yang mungkin |
|---|---|---|
| OpenClaw | `curl -fsSL https://openclaw.ai/install.sh \| bash` (memasang paket npm global + gateway sebagai unit systemd USER) | `npm i -g openclaw`, pnpm/bun global, pipx/pip, biner manual di ~/.local/bin atau /usr/local/bin, Docker |
| Hermes Agent | `curl -fsSL https://hermes-agent.nousresearch.com/install.sh \| bash` lalu `cd ~/.hermes/hermes-agent && uv pip install -e ".[web,pty]"` | pipx/pip, Docker |
| Torang Event | installer torang-murid: `bash <(curl .../torang-murid/main/install.sh)` (monitor + plugin torang-events) | pemasangan manual dari repo |

Uninstaller RESMI OpenClaw: `openclaw uninstall --all --yes --non-interactive`
-- selalu coba ini dulu, sapuan manual tinggal memungut sisa.

## OpenClaw

- State dir: `${OPENCLAW_STATE_DIR:-~/.openclaw}` (hormati env!). Isi penting:
  `openclaw.json` (termasuk `gateway.auth.token`), `credentials/`, `agents/`
  (identitas per agent; `agents/*/sessions/` = sesi), `workspace/` (hasil kerja
  murid), `state/openclaw.sqlite` (DB task global).
- Config path alternatif: env `OPENCLAW_CONFIG_PATH`.
- Dir lain: `~/.config/openclaw`, `~/.cache/openclaw`, `~/.local/share/openclaw`,
  `~/.local/state/openclaw`, `/etc/openclaw` (jarang; root).
- Gateway: unit systemd USER `openclaw-gateway.service` (varian profil
  `openclaw-gateway-<profil>.service`) di `~/.config/systemd/user/`.
  Port `${OPENCLAW_GATEWAY_PORT:-18789}`; dashboard
  `http://127.0.0.1:18789/#token=...`.
- Biner: `~/.local/bin/openclaw`, `~/.npm-global/bin/openclaw`, `~/bin/openclaw`,
  `~/.hermes/node/bin/openclaw` (kalau npm-nya milik Hermes!),
  `/usr/local/bin/openclaw`, `/usr/bin/openclaw` (root).
- Paket global: `npm ls -g --depth=0`, `pnpm list -g --depth=0`, `bun pm ls -g`.
- Plugin OpenClaw milik Torang: terdaftar sebagai `torang-events`
  (`openclaw plugins disable torang-events` sebelum gateway stop).

## Hermes

- Rumah: `~/.hermes` -- termasuk `hermes-agent/` (repo), `memories/`,
  `sessions/`, dan **Node privatnya sendiri** di `~/.hermes/node/`.
- Tautan yang DIA buat di `~/.local/bin/`: `hermes`, `node`, `npm`, `npx`
  (kadang `uv`) -> menunjuk ke `~/.hermes/...`. HANYA hapus tautan yang
  menunjuk ke ~/.hermes atau menggantung; node sistem/nvm JANGAN disentuh.
- `~/.hermes/node/etc/npmrc` + baris di `~/.npmrc` yang mengalihkan prefix npm
  global ke Hermes.
- Menulis PATH ke sampai 6 file rc: `.bashrc`, `.bash_profile`, `.profile`,
  `.zshrc`, `.zprofile`, `.config/fish/config.fish`.
- Cache: `~/.cache/ms-playwright` (Chromium besar), `~/.cache/uv`.
- Paket apt yang ikut terpasang (ripgrep, ffmpeg, git, build-essential)
  JANGAN dicabut -- dipakai hal lain.
- **URUTAN WAJIB: Torang -> OpenClaw -> Hermes.** Hermes dicabut TERAKHIR
  karena npm bisa milik Hermes; kalau Hermes duluan, npm hilang dan
  `npm rm -g openclaw` gagal.

## Torang Event

- Monitor murid: `~/.torang/` (monitor-client.js, config.env, start.sh,
  start.lock, monitor.log) + `~/.torang-monitor/` (config.json, `client_id` --
  client_id menentukan karakter murid; backup kalau ingin karakter tetap).
- Auto-start: baris di `~/.bashrc` (pola `.torang/start.sh`, komentar
  `# Torang`); unit systemd user `torang-monitor.service` (di mesin Hadi).
- Plugin OpenClaw: `~/.torang-plugin/torang-events/` (WAJIB di FS Linux, bukan
  /mnt) + log `~/torang-events.log` + env fallback `~/.torang-events.env`.
- Sisi GURU (hanya dengan --guru): `~/.torang-guru/`, `~/torang-office/`
  (office Flask `python3 backend/app.py`, port `${TORANG_PORT:-19000}`,
  `agents-state.json` = pairing karakter). Sisi WINDOWS PC guru (portproxy,
  firewall, scheduled task TorangOfficeLAN/TorangGuruBoot) TIDAK terjangkau
  dari WSL -- pakai TORANG-Pulihkan-PC-Guru.bat di Windows.

## Jejak lintas komponen

- systemd USER: `~/.config/systemd/user/*{openclaw,hermes,torang}*` -- sapu
  filenya juga walau systemd tidak aktif (WSL polos), supaya tidak bangkit
  saat systemd dinyalakan lewat /etc/wsl.conf.
- systemd SISTEM: `/etc/systemd/system/*` (root; `daemon-reload` +
  `reset-failed` setelah hapus).
- Cron user (`crontab -l`), autostart desktop (`~/.config/autostart/*.desktop`),
  `/etc/wsl.conf` (baris boot terkait; root).
- Log sistem: `/var/log/{openclaw,hermes,torang}*` (root).
- Cache manajer paket: `npm cache clean --force` (fallback hapus
  `~/.npm/_cacache`), `pip cache purge` (fallback `~/.cache/pip`).
- Docker: container/image/volume yang namanya memuat openclaw|hermes|torang.

## Yang TIDAK bisa dibersihkan dari dalam PC

1. Bot Telegram murid -- masih hidup di server Telegram. BotFather ->
   `/deletebot`.
2. API key OpenAI kelas -- rotate/cabut dari dasbor OpenAI.
3. Karakter/pairing basi di office guru -- `torang-sapu-agent.sh` atau hapus
   `~/torang-office/agents-state.json`.
4. Sisi Windows PC guru (lihat bagian Torang di atas).
