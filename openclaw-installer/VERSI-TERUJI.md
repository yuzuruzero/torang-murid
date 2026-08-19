# VERSI TERUJI

Catatan versi yang pernah kami pasang dan buktikan jalan.

**Cara membaca tabel ini.** Kolom yang paling sering terlupa bukan nomor versinya,
melainkan **tanggal dokumentasi resmi terakhir dicocokkan**. Riset 19 Agustus 2026
menemukan **6 selisih** antara catatan kami (dibuat Juli) dan dokumentasi resmi — hanya
dalam sekitar empat minggu. Kedua produk bergerak cepat. Nomor versi tanpa tanggal
tidak banyak artinya.

**Skrip memperingatkan, bukan menggagalkan.** Kalau versi terpasang berbeda dari tabel
ini, `verifikasi.sh` hanya mencatat. Instalasi tetap dianggap sah.

---

## Tabel versi

| Produk | Versi teruji | Tanggal diuji | Dokumentasi resmi terakhir dicocokkan | Catatan |
|---|---|---|---|---|
| OpenClaw | _(belum diisi)_ | — | **2026-08-19** | Diisi setelah uji lapangan pertama. Ambil dari `openclaw --version`. |
| Hermes Agent | _(belum diisi)_ | — | **2026-08-19** | Ambil dari `hermes version` — salin **beserta commit hash**-nya. |
| Node.js | — | — | 2026-08-19 | Didukung: 22.22.3+, 24.15+, 25.9+. **Node 23 tidak didukung.** Node 26 = bawaan installer OpenClaw di Linux/Mac. |
| Ubuntu WSL | Ubuntu-24.04 | — | 2026-08-19 | Nama kanonik yang dipakai skrip. Jangan pernah nama lain. |
| npm | — | — | 2026-08-19 | Sejak 11.16 lifecycle script diblokir; lihat "Jebakan npm" di bawah. |
| openclaw-cleanup | v1.2 / plugin 0.2.0 (di disk) · v1.1 di GitHub main | 2026-08-18 | — | Dipakai untuk rollback. v1.1 **belum punya** `--sisakan-agenlain`; `pasang-inti.sh` mendeteksi ini sendiri. |

> Kedua baris teratas sengaja dikosongkan. Mengisi nomor versi yang belum pernah
> benar-benar dipasang akan membuat tabel ini berbohong sejak hari pertama.
> Isi setelah uji lapangan pertama (lihat `CARA-UJI-INSTALLER.md`).

---

## Cara mengisi tabel ini setelah uji lapangan

Di mesin yang baru selesai dipasang:

```bash
openclaw --version
hermes version
node -v
npm --version
```

Salin apa adanya ke tabel, isi tanggalnya, lalu **tambah baris baru** — jangan menimpa
baris lama. Riwayat versi itu yang membuat kita bisa menjawab "dulu jalan, sekarang
tidak, apa yang berubah?"

---

## Jebakan npm (relevan hanya untuk pin versi OpenClaw)

Sejak **npm 11.16**, npm memblokir lifecycle script paket yang tidak disetujui eksplisit.
Bentuk perintahnya jadi berbeda:

| Versi npm | Perintah yang benar |
|---|---|
| ≤ 11.15 | `npm install -g openclaw@<versi>` |
| ≥ 11.16 (termasuk 12) | `npm install -g openclaw@<versi> --allow-scripts=openclaw` |

Catatan penting:

- `npm approve-scripts openclaw` **tidak bekerja** untuk instalasi global — gagal dengan
  `ENOMATCH No installed packages match: openclaw`.
- Versi npm tidak terbaca → **berhenti, jangan menebak**. Menebak di sini menghasilkan
  OpenClaw yang "terpasang" tapi tidak berfungsi.
- Kalau memakai `install.sh --version <versi>`, installer resmi menangani jebakan ini
  sendiri. Jalur npm langsung hanya untuk keadaan khusus (`--npm-langsung`).

---

## Pin versi: apa yang bisa dan tidak bisa

| Produk | Bisa di-pin? | Caranya |
|---|---|---|
| **OpenClaw** | **Ya** | `bash pasang-inti.sh --versi-openclaw <versi>` → diteruskan ke `install.sh --version`. |
| **Hermes** | **Tidak** (disengaja) | Hermes dipasang sebagai git checkout, installernya tidak punya flag versi. Pin lewat `git checkout` berarti mereplikasi logika installer resmi dan mudah patah. Kami **deteksi + catat + peringatkan** saja. |

Jalur pin manual Hermes (darurat, di luar skrip):

```bash
cd ~/.hermes/hermes-agent
git checkout vX.Y.Z
uv pip install -e ".[all]"
hermes config check          # WAJIB: versi lama bisa menolak config baru
```

Dokumentasi resmi Hermes memperingatkan sendiri bahwa rollback bisa menimbulkan opsi
config yang tidak dikenali. Kalau itu terjadi, hapus opsi asing dari `config.yaml`.

---

## Riwayat perubahan file ini

| Tanggal | Perubahan |
|---|---|
| 2026-08-19 | Dibuat bersama installer-orkestrator v1.0. Baris OpenClaw dan Hermes sengaja kosong sampai uji lapangan pertama. |
