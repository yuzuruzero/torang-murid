#!/usr/bin/env node
/**
 * Torang Class Monitor — guest client (v3.9 · main SIBUK tak pernah balik Ruang Tamu)
 * ================================================================
 * FIX v3.9 (bug "main bolak-balik web->tamu->data->tamu; tulis laporan malah ke Tamu"):
 *   • Sebab: satu-satunya sinyal ruang datang dari tool cari/olah (web_search/web_fetch/
 *     memory_search). Saat main pakai `bash` (menyusun file, git, MENGIRIM laporan ke
 *     user) tak ada tool yang terpetakan -> ruang aktivitas kedaluwarsa -> v3.8 jatuh ke
 *     'tamu'. Itulah yang bikin main "mental" ke Ruang Tamu di sela-sela kerja.
 *   • Perbaikan: main yang SEDANG SIBUK tak pernah lagi ke Ruang Tamu. Kalau lagi tak
 *     ada aktivitas cari/olah -> dianggap fase "sampaikan/hasilkan" -> RUANG CS.
 *     Jadi: cari(web) -> olah(data) -> sampaikan/laporan(CS). Ruang Tamu HANYA untuk
 *     main yang BELUM pernah kerja & benar-benar nganggur; kalau sudah pernah kerja &
 *     nganggur -> Standby (bukan Tamu). Worker tak berubah (fallback ke ruang identitasnya).
 * ================================================================
 * BARU v3.8 (Cara A — main/worker pindah ruang sesuai APA yang dikerjakan):
 *   • Baca `openclaw audit --kind tool_action --json` (metadata-only): tahu tiap agent
 *     lagi pakai tool apa (bukan isinya) -> petakan ke ruang.
 *       cari/internet (web_search, web_fetch) -> WEB
 *       olah/baca (memory_search, sessions_history, read, grep, …) -> DATA
 *       hasilkan/kirim (apply_patch, sessions_send, …) -> CS
 *   • Main yang KERJA SENDIRI kini PINDAH ke ruang aktivitasnya (keluar Ruang Tamu),
 *     bukan lagi "kerja di dalam Ruang Tamu".
 *   • Tak butuh plugin / restart Gateway. Kalau `openclaw audit` tak ada -> degrade
 *     ke perilaku lama (aman). Peta tool->ruang bisa dioverride via config `toolRoom`.
 *   • DEBUG `activity` cetak {agent, room, tool, umur} + daftar tool "belum_dipetakan".
 * ================================================================
 * FIX v3.7 (bug "main kerja SENDIRI tetap tak gerak walau v3.4"):
 *   • Deteksi "main sibuk" tak lagi hardcode id 'main'. Id main asli diambil dari
 *     agents list (isDefault) -> `cachedMainBusy = set.has(idMainAsli)`. Dulu kalau
 *     id main bukan 'main', solo-work tak terdeteksi (delegasi tetap jalan via teamBusy).
 *   • DEBUG `busy` kini cetak {mainId, mainBusy} biar gampang dicek.
 *   • CATATAN: ini bikin main solo TERDETEKSI kerja (animasi kerja di Ruang Tamu).
 *     Untuk main PINDAH ke ruang sesuai aktivitas (Web/Data/CS) butuh plugin aktivitas.
 * ================================================================
 * BARU v3.6:
 *   • Awalan nama guest murid kini pakai USERNAME Ubuntu (lebih enak dibaca),
 *     bukan nama device. Kalau username tak ada / 'root' -> fallback nama device.
 *     Override tetap bisa via TORANG_LABEL / config.label.
 * ================================================================
 * FIX v3.5 (bug "main selesai menemani tim malah balik ke Ruang Tamu"):
 *   • Main yang SUDAH pernah kerja, saat selesai & nganggur kini ke STANDBY
 *     (samain dgn worker), bukan Ruang Tamu. Ruang Tamu tetap hanya utk yg BELUM
 *     pernah kerja (baru lahir). Main melacak `hasWorked` seperti worker.
 * ================================================================
 * FIX v3.4 (main sibuk karena KERJA SENDIRI, mis. mereview hasil agent lain):
 *   • Deteksi "sibuk" tak lagi kalah oleh mtime file sesi yang BASI — kini ambil tanda
 *     TERSEGAR dari SEMUA sinyal sesi (mtime file, updatedAt, lastInteractionAt, dll),
 *     plus status sesi ('running/active/generating'). -> main yang lagi mereview/kerja
 *     sendiri ikut terdeteksi, bukan cuma saat delegasi.
 *   • Debug `busy` kini mencetak rincian tiap sesi {agent, status, umur} biar gampang dicek.
 * ================================================================
 * FIX v3.3 (bug "worker cuma nongol sebentar lalu standby; main tak gerak"):
 *   • MAIN ikut sibuk saat TIM-nya sibuk (ada task jalan / worker sibuk) -> main
 *     bergerak & "mengawasi" ruang aktif, tak lagi diam di Ruang Tamu.
 *   • JEDA-KERJA (WORK_LINGER_MS): sekali terdeteksi kerja, worker tetap di ruangnya
 *     beberapa detik walau deteksi sela kosong -> tak "langsung standby" (kerja OpenClaw
 *     berdenyut/burst; file sesi worker sering baru di-flush saat hasil keluar).
 *   • Jendela "sibuk" (MAIN_BUSY_MS) dilebarkan 25->40s biar denyut singkat tertangkap.
 *   • Task JALAN yang belum keklasifikasi ruangnya tetap dihitung -> main tetap gerak.
 *   • CATATAN: WSL yang dibatasi RAM/CPU bikin query `openclaw` lambat -> denyut lebih
 *     sering meleset. Batas RAM cuma perlu di PC GURU (yang menjalankan office).
 * ================================================================
 * FIX v3.2 (bug "semua agent tiba-tiba hilang"):
 *   • Saat exit TIDAK lagi mengeluarkan semua guest (restart/loop dulu bikin semua hilang).
 *   • Push kena 404 (office lupa agent) -> otomatis JOIN ulang tick berikutnya.
 *   • Hasil `agents list` transien kosong TAK mengosongkan roster.
 *   • CATATAN: naikkan `maxConcurrent` di join-keys.json office (default cuma 3!).
 * ================================================================
 * BARU v3.1: "sedang bekerja" dideteksi PER-AGENT dari mtime file sesi tiap agent
 *   (`sessions --all-agents`). Menangkap pemanggilan agent LANGSUNG (bukan cuma
 *   sub-agent task) -> worker & main BENAR-BENAR bergerak saat dipakai. Saat main
 *   bekerja, ia ikut ke ruang kerja yang sedang aktif (mengawasi tim); jika tak ada
 *   ruang spesifik -> tetap di Ruang Tamu (mejanya).
 * ================================================================
 * BARU v3.0:
 *   • PC MURID kini membaca 4 agent (main + 3 worker) dari OpenClaw-nya sendiri &
 *     push SEMUA sebagai guest (nama asli OpenClaw, awalan LABEL=nama komputer),
 *     client_id unik per-PC -> tim tiap murid TAK merge. (dulu cuma 1 karakter hostname)
 *   • main-busy dibaca dari MTIME file sesi .jsonl (real-time) -> karakter main
 *     beranimasi saat diperintah (dulu pakai sessions --active yang sering telat).
 * ================================================================
 * BARU v2.9: worker agent bernama (business_analyst/customer_service/desainer_etalase)
 *   SELALU tampil di office (dari `agents list`): nganggur -> STANDBY, kerja -> ruangnya
 *   (CS/Data/Web). "Kerja" = ada sub-agent task RUNNING yg jenisnya cocok ruang itu.
 *   Jadi office tak lagi kosong walau tak ada task — tim-mu terlihat menunggu.
 * ================================================================
 * BARU v2.8 (dari diagnosa oc-diag.txt):
 *   • KUCING TENGAH kini ikut "kerja" saat MAIN agent kerja langsung — dibaca dari
 *     `sessions list --agent main --active 2` (status "running"). (Dulu cuma nyala saat sub-agent.)
 *   • Sub-agent dibaca dari `tasks list` biasa + filter ownerKey "...:subagent:..."
 *     (CATATAN penting: `tasks list --runtime subagent` SELALU kosong di OpenClaw ini).
 *   • Status resmi dipakai apa adanya: queued->Tamu, running->ruang kerja, terminal->Standby.
 * ================================================================
 * BARU v2.7 (spec Hadi): sub-agent pindah ruang mengikuti SIKLUS kerjanya:
 *   baru lahir/belum jelas -> RUANG TAMU ; kerja web/cs/analisis -> WEB/CS/DATA ;
 *   selesai/menunggu -> STANDBY. (Area Logo = tempat logo Torang, bukan ruang agent.)
 *   Jenis kerja dikenali dari nama/teks tugas (web/website/frontend, cs/customer/support,
 *   analis/analisis/data). Butuh fork Star-Office #2 (terima field `room`).
 * FIX v2.7 (temuan agent OpenClaw): task TERMINAL (succeeded/failed/…) TAK dianggap aktif,
 *   dan TIDAK ada lagi fallback ke seluruh riwayat task. Tak ada task berjalan -> tak ada
 *   guest "kerja" palsu (dulu status basi dikirim ulang tiap 15s dan tak pernah balik idle).
 *
 * BARU v2.5 (topologi "PC guru"): saat TORANG_TARGET=star-office pilih PERAN:
 *   • TORANG_SO_ROLE=teacher (DEFAULT, PC tempat office dipasang):
 *       - MAIN agent OpenClaw  -> KUCING TENGAH (POST /set_state: idle=duduk, kerja=animasi).
 *       - tiap SUB-AGENT aktif  -> satu GUEST (join/push/leave, avatar stabil dari id sub).
 *   • TORANG_SO_ROLE=student (PC murid, office jarak jauh):
 *       - MAIN agent murid ini -> satu GUEST di office guru (perilaku v2.4).
 *   Kucing tengah = agent isMain office; guest = agent non-main. Persis desain Star-Office.
 *
 * v2.4: mode target ganda lewat TORANG_TARGET.
 *   • TORANG_TARGET=star-office  -> fork Star-Office kita (torang-office).
 *   • TORANG_TARGET=torang (default) -> kontrak mock kita (join_key/agent_name/sub_agent).
 *   Ganti target TANPA ubah kode monitor — cukup env/config.
 *
 * Warisan v2.3 (CLI OpenClaw ASINKRON + cache): pemanggilan `openclaw` (cold-start
 * lambat) dibuat ASINKRON dan DI-CACHE, sehingga loop join/push tak pernah terblok.
 *   • M.1 nama agent  : refresh async `openclaw agents list --json` (identityName), cache.
 *   • M.2 sub-agent   : refresh async `openclaw tasks list --runtime subagent --json`, cache.
 *   • Timeout CLI longgar (default 20s) + tak menumpuk (satu in-flight per jenis).
 *   • Uji tanpa sub-agent nyata: TORANG_SIMULATE_SUBAGENT=web_designer|customer_service|
 *     business_analyst  -> paksa state, lihat karakter pindah ruangan.
 *
 * BATAS TEGAS (spec v2 §I): lapor HANYA aktivitas AGENT. TIDAK baca file/screenshot/
 * browser/keylog. telemetry gagal != agent gagal. Zero dependency (Node>=18).
 * WAJIB dijalankan DI WSL (tempat OpenClaw hidup).
 * ================================================================ */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { execFile } = require('child_process');

/* 0) DIR & CONFIG ----------------------------------------------------------- */
const HOME = process.env.HOME || process.env.USERPROFILE || '.';
const CONFIG_DIR = process.env.TORANG_CONFIG_DIR || path.join(HOME, '.torang-monitor');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.json');
const PID_FILE = path.join(CONFIG_DIR, 'daemon.pid');
const CLIENT_ID_FILE = path.join(CONFIG_DIR, 'client_id');
try { fs.mkdirSync(CONFIG_DIR, { recursive: true }); } catch (_) {}
function readJsonSafe(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (_) { return {}; } }
const FILECFG = readJsonSafe(CONFIG_FILE);

// [TORANG] v3.6: awalan nama murid = USERNAME Ubuntu (lebih enak dibaca);
// kalau username tak ada / 'root' -> pakai nama device (hostname).
function soLabelDefault() {
  try { const u = os.userInfo().username; if (u && u !== 'root') return u; } catch (_) {}
  const e = process.env.USER || process.env.USERNAME || '';
  return (e && e !== 'root') ? e : os.hostname();
}

const CONFIG = {
  OFFICE_URL: process.env.TORANG_OFFICE_URL || FILECFG.officeUrl || '<<OFFICE_URL>>',
  JOIN_KEY:   process.env.TORANG_JOIN_KEY   || FILECFG.joinKey   || '<<JOIN_KEY>>',
  AGENT_NAME: process.env.TORANG_AGENT_NAME || FILECFG.agentName || '',
  AGENT_ID:   process.env.TORANG_AGENT_ID   || FILECFG.agentId   || '',
  HEARTBEAT_MS: Number(process.env.TORANG_HEARTBEAT_MS || FILECFG.heartbeatMs || 15000),
  REFRESH_MS:   Number(process.env.TORANG_REFRESH_MS   || FILECFG.refreshMs   || 4000),  // cek + tick tiap 4s (sub-agent cepat ~6-8s)
  CLI_TIMEOUT_MS: Number(process.env.TORANG_CLI_TIMEOUT_MS || FILECFG.cliTimeoutMs || 90000),
  SIMULATE_SUBAGENT: process.env.TORANG_SIMULATE_SUBAGENT || FILECFG.simulateSubAgent || '',
  OPENCLAW_BIN: process.env.TORANG_OPENCLAW_BIN || FILECFG.openclawBin || 'openclaw',
  POLL_NAME: process.env.TORANG_POLL_NAME === '1',                                    // default OFF (nama dari config/env)
  POLL_SUB:  process.env.TORANG_POLL_SUB !== '0' && FILECFG.pollSub !== false,        // default ON (butuh sumber cepat!)
  SUBAGENT_ALIASES: Object.assign(
    { // [TORANG] #2b — kenali JENIS KERJA dari nama/teks tugas -> peran kanonik
      web_designer: 'web_designer', web: 'web_designer', website: 'web_designer', frontend: 'web_designer', ui: 'web_designer', etalase: 'web_designer',
      customer_service: 'customer_service', cs: 'customer_service', customer: 'customer_service', support: 'customer_service', layanan: 'customer_service',
      business_analyst: 'business_analyst', analyst: 'business_analyst', analis: 'business_analyst', analisis: 'business_analyst', data: 'business_analyst' },
    FILECFG.subAgentAliases || {}),
  DEBUG: process.env.TORANG_DEBUG === '1' || !!FILECFG.debug,
  TARGET: process.env.TORANG_TARGET || FILECFG.target || 'torang',  // 'torang' (mock/kontrak kita) | 'star-office'
  SO_ROLE: (process.env.TORANG_SO_ROLE || FILECFG.soRole || 'teacher').toLowerCase(), // 'teacher' | 'student'
  // Awalan nama guest (pembeda tim antar-PC). Default: murid pakai USERNAME Ubuntu
  // (fallback ke nama device kalau username tak ada); guru kosong.
  LABEL: (process.env.TORANG_LABEL != null ? process.env.TORANG_LABEL : (FILECFG.label != null ? FILECFG.label :
           ((process.env.TORANG_SO_ROLE || FILECFG.soRole || 'teacher').toLowerCase() === 'student' ? soLabelDefault() : ''))),
  GUEST_LINGER_MS: Number(process.env.TORANG_GUEST_LINGER_MS || FILECFG.guestLingerMs || 30000), // tahan guest ~30s: sub-agent cepat tetap terlihat (mis. di Standby setelah selesai)
  MAIN_BUSY_MS: Number(process.env.TORANG_MAIN_BUSY_MS || FILECFG.mainBusyMs || 40000), // main/worker "sibuk" bila file sesi berubah dalam N ms terakhir (dilebarkan v3.3: denyut singkat tertangkap)
  WORK_LINGER_MS: Number(process.env.TORANG_WORK_LINGER_MS || FILECFG.workLingerMs || 25000), // v3.3: sekali kerja, tahan di ruangnya N ms walau deteksi sela kosong (kerja OpenClaw berdenyut)
  POLL_ACTIVITY: process.env.TORANG_POLL_ACTIVITY !== '0' && FILECFG.pollActivity !== false, // v3.8: baca `openclaw audit` -> ruang dari aktivitas tool (Cara A)
  ACTIVITY_LINGER_MS: Number(process.env.TORANG_ACTIVITY_LINGER_MS || FILECFG.activityLingerMs || 25000), // tahan di ruang aktivitas N ms setelah tool terakhir
};
const base = () => CONFIG.OFFICE_URL.replace(/\/+$/, '');
function dbg(m, x) { if (CONFIG.DEBUG) console.log(`[torang-monitor] ${m}` + (x ? ' ' + safe(x) : '')); }
function safe(o) { try { return JSON.stringify(o); } catch (_) { return String(o); } }

/* 1) SINGLETON -------------------------------------------------------------- */
function isAlive(pid) { if (!pid) return false; try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; } }
function acquireSingleton() {
  try { const prev = parseInt(fs.readFileSync(PID_FILE, 'utf8').trim(), 10);
    if (isAlive(prev) && prev !== process.pid) { console.log(`[torang-monitor] sudah jalan (pid ${prev}) — keluar.`); return false; }
  } catch (_) {}
  try { fs.writeFileSync(PID_FILE, String(process.pid), { mode: 0o600 }); } catch (_) {}
  return true;
}

/* 2) client_id -------------------------------------------------------------- */
function getClientId() {
  try {
    if (fs.existsSync(CLIENT_ID_FILE)) { const v = fs.readFileSync(CLIENT_ID_FILE, 'utf8').trim(); if (v) return v; }
    const id = crypto.randomUUID(); const tmp = CLIENT_ID_FILE + '.tmp';
    fs.writeFileSync(tmp, id, { mode: 0o600 }); fs.renameSync(tmp, CLIENT_ID_FILE); return id;
  } catch (e) {
    console.error('[torang-monitor] PERINGATAN: client_id gagal disimpan (' + e.message + ') — sementara.');
    return crypto.randomUUID();
  }
}
const CLIENT_ID = getClientId();

/* --- CLI OpenClaw ASINKRON (tak memblok loop) --- */
function ocCliAsync(args) {
  return new Promise((resolve, reject) => {
    execFile(CONFIG.OPENCLAW_BIN, args, { timeout: CONFIG.CLI_TIMEOUT_MS, maxBuffer: 8 * 1024 * 1024 },
      (err, stdout) => err ? reject(err) : resolve(stdout));
  });
}
function parseCliJson(out) { const i = String(out).search(/[[{]/); if (i < 0) throw new Error('tak ada JSON'); return JSON.parse(String(out).slice(i)); }

/* 3) HOOK #1 — NAMA AGENT (cache + refresh async) --------------------------- */
let cachedName = CONFIG.AGENT_NAME || null;
let nameInFlight = false;
function currentName() { return CONFIG.AGENT_NAME || cachedName || 'Agent Tanpa Nama'; }
async function refreshAgentName() {
  if (CONFIG.AGENT_NAME || !CONFIG.POLL_NAME || nameInFlight) return; // default: nama dari config/env (CLI 13s, jangan dipoll)
  nameInFlight = true;
  try {
    const arr = parseCliJson(await ocCliAsync(['agents', 'list', '--json']));
    if (Array.isArray(arr) && arr.length) {
      let a; if (CONFIG.AGENT_ID) a = arr.find((x) => x && x.id === CONFIG.AGENT_ID);
      if (!a) a = arr.find((x) => x && x.isDefault) || arr[0];
      const n = a.identityName || a.name || a.id;
      if (n) { if (n !== cachedName) dbg('nama agent', { name: n }); cachedName = n; }
    }
  } catch (e) { dbg('agents list gagal', { err: e.message }); }
  finally { nameInFlight = false; }
}

/* 4) HOOK #2 — SUB-AGENT AKTIF (cache + refresh async) ----------------------
 * CONFIRM(M.2): nama field taskName di record task subagent belum terlihat. */
let cachedSub = CONFIG.SIMULATE_SUBAGENT ? mapTaskName(CONFIG.SIMULATE_SUBAGENT) : null;
let subInFlight = false;
function currentSub() { return CONFIG.SIMULATE_SUBAGENT ? mapTaskName(CONFIG.SIMULATE_SUBAGENT) : cachedSub; }
async function refreshSubAgent() {
  if (CONFIG.SIMULATE_SUBAGENT || !CONFIG.POLL_SUB || subInFlight) return;
  subInFlight = true;
  try {
    const data = parseCliJson(await ocCliAsync(['tasks', 'list', '--runtime', 'subagent', '--json']));
    const arr = Array.isArray(data) ? data : (data.tasks || data.items || data.rows || data.results || []);
    const running = arr.filter((t) => { const st = String(t.status || t.state || '').toLowerCase(); return st === '' || /run|queue|active|working|start/.test(st); });
    const pick = (running.length ? running : arr).sort((a, b) => tsOf(b) - tsOf(a))[0];
    const tn = pick && (pick.taskName || pick.task_name || pick.taskname || pick.label || pick.name || pick.title || (pick.spec && pick.spec.taskName) || (pick.meta && pick.meta.taskName));
    cachedSub = tn ? mapTaskName(tn) : null;
    dbg('sub-agent', { taskName: tn || null, room: cachedSub });
  } catch (e) { dbg('tasks list gagal', { err: e.message }); }
  finally { subInFlight = false; }
}
function tsOf(t) { return Number(t.startedAt || t.createdAt || t.updatedAt || t.ts || 0) || 0; }
function mapTaskName(tn) {
  if (!tn) return null; const t = String(tn).toLowerCase(); const A = CONFIG.SUBAGENT_ALIASES;
  if (A[t]) return A[t]; for (const k of Object.keys(A)) if (t.includes(k)) return A[k]; return null;
}

function detectError() { return false; }   // CONFIRM(M.2c) opsional
function getBubble() { return null; }

// [TORANG] #2b — RUANGAN BERDASAR AKTIVITAS (spec Hadi):
//   lahir/belum jelas kerja -> ruang TAMU ; kerja web/cs/analisis -> WEB/CS/DATA ; selesai/nunggu -> STANDBY.
//   (Logo = area logo Torang, BUKAN ruang agent — agent tak pernah ke sana.)
const ROLE_TO_ROOM = { web_designer: 'web', customer_service: 'cs', business_analyst: 'data' };
const ROOM_STATE   = { web: 'writing', cs: 'researching', data: 'executing' };
function workRoom(role) { return (role && ROLE_TO_ROOM[role]) || null; } // null = jenis kerja tak terklasifikasi
function currentState() {
  if (detectError()) return 'error';
  return (workRoom(currentSub()) ? ROOM_STATE[workRoom(currentSub())] : 'idle');
}

/* ===== TOPOLOGI "PC GURU" (Star-Office) =====================================
 * MAIN agent -> kucing tengah (/set_state). Tiap SUB-AGENT -> satu guest. */
function nowMs() { return Date.now(); }
function hashStr(s) { let h = 0; for (let i = 0; i < s.length; i++) { h = (h * 31 + s.charCodeAt(i)) | 0; } return h; }
function stableClientId(seed) {                 // UUID stabil dari id sub -> avatar & posisi tetap selama sub hidup
  const x = crypto.createHash('sha1').update('torang-sub:' + seed).digest('hex');
  return `${x.slice(0,8)}-${x.slice(8,12)}-${x.slice(12,16)}-${x.slice(16,20)}-${x.slice(20,32)}`;
}
function cap(s){ return s ? s.charAt(0).toUpperCase()+s.slice(1) : s; }
function subLabel(role, tn, key) {              // nama guest: pakai peran bila terpetakan, jika tidak id pendek
  if (role) return cap(role.replace(/_/g,' '));
  if (tn) return String(tn).slice(0, 24);
  return 'Sub-' + String(key).slice(0, 6);
}

/* [TORANG] v2.8 — deteksi berbasis DATA OpenClaw asli (dari diagnosa oc-diag.txt):
 *  • Kerja sub-agent muncul sbg task runtime "cli" dgn ownerKey "...:subagent:..."
 *    PENTING: `tasks list --runtime subagent` SELALU kosong -> pakai `tasks list` biasa.
 *  • Status resmi: queued | running | succeeded | failed | timed_out | cancelled | lost.
 *  • Main agent "sibuk" = sesi main status "running" & masih baru (`sessions --active`). */
const TASK_TERMINAL = new Set(['succeeded', 'failed', 'timed_out', 'cancelled', 'lost', 'error', 'completed']);
function shortTask(txt) {
  const m = String(txt).match(/\[Subagent Task\]\s*([\s\S]*?)(?:\n\n|Begin\.|$)/i);
  return ((m ? m[1] : String(txt)).replace(/\s+/g, ' ').trim().slice(0, 40)) || 'tugas';
}
function isSubTask(t) { return /:subagent:/.test(String(t.ownerKey || t.childSessionKey || t.requesterSessionKey || '')); }
function guestName(room, id) { const M = { web: 'Web', cs: 'CS', data: 'Data' }; return (room && M[room]) ? M[room] + '·' + String(id).slice(0, 4) : 'Sub-' + String(id).slice(0, 6); }

let cachedTasks = [];   // [{id, room, tn, status, endedAt}]
async function refreshTasks() {
  if (CONFIG.SIMULATE_SUBAGENT || !CONFIG.POLL_SUB || subInFlight) return;
  subInFlight = true;
  try {
    const data = parseCliJson(await ocCliAsync(['tasks', 'list', '--json']));
    const arr = Array.isArray(data) ? data : (data.tasks || data.items || []);
    cachedTasks = arr.filter(isSubTask).map((t) => {
      const id = String(t.taskId || t.id || t.runId || Math.abs(hashStr(JSON.stringify(t))));
      const txt = String(t.task || t.taskName || t.title || '');
      return { id, room: workRoom(mapTaskName(txt)), tn: shortTask(txt),
        status: String(t.status || t.state || '').toLowerCase(),
        endedAt: Number(t.endedAt || t.lastEventAt || t.updatedAt || 0) };
    });
    dbg('tasks', { total: arr.length, sub: cachedTasks.length });
  } catch (e) { dbg('tasks list gagal', { err: e.message }); }
  finally { subInFlight = false; }
}

let cachedMainBusy = false, busyAgents = new Set(), mainInFlight = false;
// [TORANG] v3.1 — deteksi SIAPA yang sedang bekerja (main + tiap worker) dari mtime file
// sesi masing-masing (`sessions --all-agents`). Tangkap pemanggilan agent LANGSUNG,
// bukan cuma sub-agent task. -> worker & main benar-benar bergerak saat dipakai.
function agentBusy(id) { return busyAgents.has(String(id).toLowerCase()); }
function toMs(v) { // epoch-ms | epoch-detik | ISO-string -> ms
  if (v == null) return 0;
  if (typeof v === 'number') return v > 1e12 ? v : v * 1000;
  const t = Date.parse(String(v)); return isNaN(t) ? 0 : t;
}
async function refreshBusy() {
  if (CONFIG.SIMULATE_SUBAGENT || !CONFIG.POLL_SUB || mainInFlight) return;
  mainInFlight = true;
  try {
    const data = parseCliJson(await ocCliAsync(['sessions', 'list', '--all-agents', '--json']));
    const arr = Array.isArray(data) ? data : (data.sessions || []);
    const now = Date.now(); const set = new Set(); const seen = [];
    for (const s of arr) {
      const aid = (s.agentId || String(s.key || '').split(':')[1] || '').toLowerCase();
      if (!aid) continue;
      // Ambil tanda "baru aktif" TERSEGAR dari semua sinyal — JANGAN biarkan mtime file basi
      // memveto updatedAt/lastInteractionAt yang lebih segar (ini bikin main kerja tapi dikira nganggur).
      const stamps = [];
      try { if (s.sessionFile && fs.existsSync(s.sessionFile)) stamps.push(fs.statSync(s.sessionFile).mtimeMs); } catch (_) {}
      for (const k of ['updatedAt', 'lastInteractionAt', 'lastEventAt', 'modifiedAt', 'ts']) if (s[k] != null) stamps.push(toMs(s[k]));
      const freshest = stamps.length ? Math.max(...stamps) : 0;
      const ago = freshest ? now - freshest : Infinity;
      const st = String(s.status || s.state || '').toLowerCase();
      const running = /run|active|work|generat|stream|busy|think/.test(st);
      const isBusy = running || (isFinite(ago) && ago >= 0 && ago < CONFIG.MAIN_BUSY_MS);
      if (isBusy) set.add(aid);
      if (CONFIG.DEBUG) seen.push({ a: aid, st: st || '-', umur: isFinite(ago) ? Math.round(ago / 1000) + 's' : '∞', sibuk: isBusy ? 1 : 0 });
    }
    busyAgents = set;
    // [TORANG] v3.7: JANGAN hardcode 'main' — id main sebenarnya dari agents list (isDefault),
    // bisa beda dari 'main'. Kalau salah id -> main kerja-sendiri tak terdeteksi sibuk.
    const _m = mainAgent();
    const _mid = (_m && _m.id) ? String(_m.id).toLowerCase() : 'main';
    cachedMainBusy = set.has(_mid) || set.has('main');
    dbg('busy', { mainId: _mid, mainBusy: cachedMainBusy, aktif: [...set], sesi: seen });
  } catch (e) { dbg('sessions gagal', { err: e.message }); }
  finally { mainInFlight = false; }
}

/* [TORANG] v3.8 — ROUTING BERDASAR AKTIVITAS (Cara A). Baca `openclaw audit` (metadata-only):
 *   tahu tiap agent LAGI PAKAI TOOL apa (bukan isinya) -> petakan ke ruang.
 *   cari (internet) -> WEB ; olah/baca -> DATA ; hasilkan/kirim -> CS ; lain -> null (jangan pindah). */
const TOOL_ROOM = Object.assign({
  // WEB — cari dari internet
  web_search: 'web', web_fetch: 'web', browser: 'web', navigate: 'web', fetch_url: 'web', http_request: 'web',
  // DATA — baca / cari / olah info
  memory_search: 'data', sessions_list: 'data', sessions_history: 'data',
  read: 'data', file_read: 'data', read_file: 'data', grep: 'data', glob: 'data', list_dir: 'data',
  // CS — hasilkan / kirim (produksi & komunikasi)
  apply_patch: 'cs', write: 'cs', edit: 'cs', write_file: 'cs', sessions_send: 'cs', message_send: 'cs',
}, FILECFG.toolRoom || {});
function toolRoom(t) { return TOOL_ROOM[String(t || '').toLowerCase()] || null; }

let toolActivity = new Map(); // agentId(lower) -> { room, ts, tool }
let actInFlight = false;
const _unmappedTools = new Set();
async function refreshToolActivity() {
  if (CONFIG.SIMULATE_SUBAGENT || !CONFIG.POLL_ACTIVITY || actInFlight) return;
  actInFlight = true;
  try {
    const raw = parseCliJson(await ocCliAsync(['audit', '--kind', 'tool_action', '--limit', '80', '--json']));
    const events = Array.isArray(raw) ? raw : (raw && raw.events) || [];
    const now = Date.now();
    // proses dari TERLAMA -> TERBARU supaya event terbaru per-agent yang menang
    events.slice().sort((a, b) => (Number(a.occurredAt) || 0) - (Number(b.occurredAt) || 0)).forEach((e) => {
      const aid = String(e.agentId || '').toLowerCase(); if (!aid) return;
      const r = toolRoom(e.toolName);
      if (!r) { if (CONFIG.DEBUG && e.toolName) _unmappedTools.add(e.toolName); return; }
      toolActivity.set(aid, { room: r, ts: Number(e.occurredAt) || now, tool: e.toolName });
    });
    if (CONFIG.DEBUG) dbg('activity', {
      agents: [...toolActivity.entries()].map(([a, v]) => ({ a, room: v.room, tool: v.tool, umur: Math.round((now - v.ts) / 1000) + 's' })),
      belum_dipetakan: [..._unmappedTools],
    });
  } catch (e) { dbg('audit gagal (routing aktivitas dilewati)', { err: e.message }); }
  finally { actInFlight = false; }
}
function activityRoom(id) {
  const v = toolActivity.get(String(id).toLowerCase());
  if (!v) return null;
  return (Date.now() - v.ts <= CONFIG.ACTIVITY_LINGER_MS) ? v.room : null;
}

/* [TORANG] v2.9 — WORKER AGENT = penghuni tetap (bukan per-task).
 *  Tiap agent bernama (non-main) selalu tampil: nganggur -> STANDBY, kerja -> ruangnya.
 *  Ruang per identitas: customer_service->CS, business_analyst->DATA, desainer_etalase->WEB.
 *  "Kerja" dideteksi bila ada sub-agent task RUNNING yang jenis kerjanya cocok ruang itu. */
const AGENT_ROOM = Object.assign(
  { customer_service: 'cs', business_analyst: 'data', desainer_etalase: 'web', web_designer: 'web' },
  FILECFG.agentRoom || {});
// ruang dari id agent; kalau tak terdaftar, coba tebak dari kata kunci id/nama (web/cs/analisis).
// Agent di luar web/cs/data -> null (tinggal di Ruang Tamu/Standby, karena ruang kerja cuma 3).
function agentRoom(id, name) {
  const k = String(id).toLowerCase();
  return AGENT_ROOM[k] || workRoom(mapTaskName(k)) || (name ? workRoom(mapTaskName(String(name))) : null);
}
const DEFAULT_WORKERS = [
  { id: 'desainer_etalase', name: 'Desainer Etalase', room: 'web' },
  { id: 'customer_service', name: 'Customer Service', room: 'cs' },
  { id: 'business_analyst', name: 'Business Analyst', room: 'data' },
];

let cachedAgents = [], agentsInFlight = false;   // [{id,name,room,isMain}] SEMUA agent
async function refreshAgents() {
  if (CONFIG.SIMULATE_SUBAGENT || !CONFIG.POLL_SUB || agentsInFlight) return;
  agentsInFlight = true;
  try {
    const arr = parseCliJson(await ocCliAsync(['agents', 'list', '--json']));
    const mapped = (Array.isArray(arr) ? arr : []).filter((a) => a && a.id)
      .map((a) => ({ id: a.id, name: a.identityName || a.name || a.id, room: agentRoom(a.id, a.identityName || a.name), isMain: !!a.isDefault || a.id === 'main' }));
    if (mapped.length) cachedAgents = mapped;  // jangan kosongkan roster kalau hasil transien kosong
    dbg('agents', { total: cachedAgents.length, workers: cachedAgents.filter((a) => !a.isMain).length });
  } catch (e) { dbg('agents list gagal', { err: e.message }); }
  finally { agentsInFlight = false; }
}
function workers() { const w = cachedAgents.filter((a) => !a.isMain); return w.length ? w : (CONFIG.SIMULATE_SUBAGENT ? DEFAULT_WORKERS : []); }
function mainAgent() { return cachedAgents.find((a) => a.isMain); }
function runningRooms() {   // ruang yang sedang "kerja" (dari task running, atau SIMULATE)
  if (CONFIG.SIMULATE_SUBAGENT)
    return new Set(String(CONFIG.SIMULATE_SUBAGENT).split(',').map((r) => workRoom(mapTaskName(r.trim()))).filter(Boolean));
  return new Set(cachedTasks.filter((t) => t.status === 'running' || t.status === 'queued').map((t) => t.room).filter(Boolean));
}
// v3.3: ADA task jalan (biar ruangnya belum keklasifikasi) -> tim dianggap kerja, main ikut gerak.
function anyTaskRunning() {
  if (CONFIG.SIMULATE_SUBAGENT) return runningRooms().size > 0;
  return cachedTasks.some((t) => t.status === 'running' || t.status === 'queued');
}

const guests = new Map();  // id -> { clientId, joined, lastSeen, hasWorked }
// [TORANG] KUCING TENGAH — HANYA host/guru yang mendorong /set_state (satu kucing).
async function tickCat() {
  const rr = runningRooms();
  const busy = cachedMainBusy || rr.size > 0;
  const detail = rr.size ? `tim mengerjakan: ${[...rr].join(', ')}`
    : (cachedMainBusy ? `${currentName()} sedang bekerja` : `menunggu · main: ${currentName()}`);
  await post('/set_state', { state: detectError() ? 'error' : (busy ? 'executing' : 'idle'), detail });
}
// [TORANG] WORKER agent -> guest. Dipakai guru DAN murid (tiap PC push tim-nya sendiri).
//   client_id unik per-PC (pakai CLIENT_ID) -> tim tiap murid TAK merge walau nama peran sama.
//   nama diberi awalan LABEL (nama murid/host) supaya guru bisa bedakan milik siapa.
//   includeMain=true (mode murid): main agent PC itu ikut tampil sebagai guest (bukan kucing).
function label(n) { return CONFIG.LABEL ? `${CONFIG.LABEL} · ${n}` : n; }
async function pushGuest(desiredIds, now, key, name, room, state, detail) {
  desiredIds.add(key);
  let g = guests.get(key); if (!g) { g = { clientId: stableClientId(CLIENT_ID + ':' + key), joined: false, hasWorked: false }; guests.set(key, g); }
  g.lastSeen = now;
  const body = { client_id: g.clientId, joinKey: CONFIG.JOIN_KEY, name, state, detail, room };
  if (!g.joined) { const st = await post('/join-agent', body); g.joined = (st !== 429); } // 429 = penuh (naikkan maxConcurrent)
  else { const st = await post('/agent-push', body); if (st === 404) g.joined = false; } // office lupa agent ini -> join ulang tick berikutnya
  return g;
}
async function tickWorkers(includeMain) {
  const now = nowMs();
  const rr = runningRooms();
  const taskRunning = anyTaskRunning();
  const desiredIds = new Set();
  let teamRoom = [...rr][0] || null;        // ruang tim yang sedang aktif (buat main mengawasi)
  let teamBusy = rr.size > 0 || taskRunning; // tim kerja bila ada task jalan / ruang aktif

  for (const w of workers()) {
    // "kerja SEKARANG" = sesi agent berubah / ada task cocok ruangnya / lagi pakai tool (audit).
    const actRoomW = activityRoom(w.id);               // [TORANG] v3.8 ruang dari aktivitas tool (Cara A)
    const roomActive = actRoomW || w.room;             // aktivitas dulu, baru peran
    const busyNow = agentBusy(w.id) || (w.room && rr.has(w.room)) || !!actRoomW;
    const key = 'agent:' + w.id;
    const g0 = guests.get(key);
    if (busyNow) { teamBusy = true; if (roomActive) teamRoom = teamRoom || roomActive; }
    // JEDA-KERJA: sekali kerja, anggap masih "di ruangnya" selama WORK_LINGER_MS (kerja OpenClaw berdenyut).
    const lastBusy = (g0 && g0.lastBusyAt) || 0;
    const lingerBusy = busyNow || (now - lastBusy < CONFIG.WORK_LINGER_MS);
    const inRoom = lingerBusy && !!roomActive;   // pindah ke ruang kerja hanya kalau punya ruang
    const hadWorked = (g0 && g0.hasWorked) || busyNow;
    // belum pernah kerja -> RUANG TAMU ; pernah & nganggur -> STANDBY ; kerja/menyelesaikan -> ruangnya.
    const room = inRoom ? roomActive : (hadWorked ? 'standby' : 'tamu');
    const detail = busyNow ? (roomActive ? `kerja: ${roomActive}` : 'bekerja')
      : (lingerBusy ? 'menyelesaikan…' : (hadWorked ? 'menunggu tugas' : 'baru masuk'));
    const g = await pushGuest(desiredIds, now, key, label(w.name), room,
      lingerBusy ? (ROOM_STATE[roomActive] || 'executing') : 'idle', detail);
    if (busyNow) { g.hasWorked = true; g.lastBusyAt = now; }
  }

  if (includeMain) {
    const m = mainAgent() || { id: 'main', name: currentName() };
    const key = 'agent:main';
    const g0 = guests.get(key);
    // [TORANG] main = orkestrator: SIBUK bila sesinya sendiri aktif ATAU tim-nya sedang kerja.
    // Saat sibuk ia IKUT ke ruang kerja aktif (mengawasi tim); tanpa ruang spesifik -> Ruang Tamu (mejanya).
    // [TORANG] v3.8: main punya ruang SENDIRI dari aktivitas tool (Cara A) -> keluar Ruang Tamu.
    const actRoom = activityRoom(m.id);
    const busyNow = cachedMainBusy || teamBusy || !!actRoom;
    const lastBusy = (g0 && g0.lastBusyAt) || 0;
    const lingerBusy = busyNow || (now - lastBusy < CONFIG.WORK_LINGER_MS);
    // v3.5: main yang PERNAH kerja -> STANDBY saat selesai; Ruang Tamu hanya utk yg belum pernah kerja.
    const hadWorked = (g0 && g0.hasWorked) || busyNow;
    // prioritas ruang: aktivitas main sendiri (cari/olah) -> ikut ruang tim (mengawasi).
    const mroom = actRoom || teamRoom;
    // [TORANG] v3.9 — main SIBUK TAK PERNAH balik Ruang Tamu:
    //   ada aktivitas cari/olah -> ruang itu (web/data) ; sibuk tapi tak ada aktivitas
    //   cari/olah (mis. `bash`: menyusun file / MENGIRIM laporan ke user) -> fase
    //   "sampaikan/hasilkan" -> RUANG CS. Ruang Tamu hanya utk yg BELUM pernah kerja &
    //   nganggur; sudah pernah kerja & nganggur -> Standby.
    const room = lingerBusy ? (mroom || 'cs') : (hadWorked ? 'standby' : 'tamu');
    const detail = busyNow ? (actRoom ? `kerja: ${actRoom}` : (teamRoom ? `mengawasi: ${teamRoom}` : 'menyusun & menyampaikan hasil'))
      : (lingerBusy ? 'menyelesaikan…' : (hadWorked ? 'menunggu tugas' : 'menunggu perintah'));
    const g = await pushGuest(desiredIds, now, key, label(m.name), room,
      lingerBusy ? (ROOM_STATE[room] || 'executing') : 'idle', detail);
    if (busyNow) { g.hasWorked = true; g.lastBusyAt = now; }
  }

  for (const [id, g] of guests) {
    if (desiredIds.has(id)) continue;
    if (now - (g.lastSeen || 0) > CONFIG.GUEST_LINGER_MS) { await post('/leave-agent', { client_id: g.clientId, joinKey: CONFIG.JOIN_KEY }); guests.delete(id); }
  }
}
async function tickTeacher() { await tickCat(); await tickWorkers(false); }

/* 5) PENGIRIM --------------------------------------------------------------- */
async function post(pathname, body) {
  try {
    const ctrl = new AbortController(); const t = setTimeout(() => ctrl.abort(), 4000);
    try { const r = await fetch(base() + pathname, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: ctrl.signal }); return r.status; }
    finally { clearTimeout(t); }
  } catch (e) { dbg('post gagal (diabaikan)', { pathname, err: e.message }); return 0; }
}
// body sesuai TARGET: 'star-office' pakai field name/joinKey/state; 'torang' pakai kontrak kita (mock)
function studentRoom() { return workRoom(currentSub()) || 'tamu'; } // murid: kerja->ruang; belum->tamu
function joinBody() {
  if (CONFIG.TARGET === 'star-office')
    return { name: currentName(), joinKey: CONFIG.JOIN_KEY, client_id: CLIENT_ID, state: currentState(), detail: currentSub() || '', room: studentRoom() };
  return { join_key: CONFIG.JOIN_KEY, client_id: CLIENT_ID, agent_name: currentName() };
}
function pushBody() {
  if (CONFIG.TARGET === 'star-office')
    return { client_id: CLIENT_ID, joinKey: CONFIG.JOIN_KEY, name: currentName(), state: currentState(), detail: currentSub() || '', room: studentRoom() };
  return { join_key: CONFIG.JOIN_KEY, client_id: CLIENT_ID, agent_name: currentName(),
    ts: Math.floor(Date.now() / 1000), sub_agent: currentSub(), error: detectError(), bubble: getBubble() };
}
function leaveBody() {
  if (CONFIG.TARGET === 'star-office') return { client_id: CLIENT_ID, joinKey: CONFIG.JOIN_KEY };
  return { join_key: CONFIG.JOIN_KEY, client_id: CLIENT_ID };
}

/* 6) LOOP UTAMA ------------------------------------------------------------- */
const TEACHER = CONFIG.TARGET === 'star-office' && CONFIG.SO_ROLE === 'teacher';
const STUDENT = CONFIG.TARGET === 'star-office' && CONFIG.SO_ROLE === 'student';

async function main() {
  if (!acquireSingleton()) return;
  if (base().includes('<<') || CONFIG.JOIN_KEY.includes('<<'))
    console.error('[torang-monitor] OFFICE_URL/JOIN_KEY belum diisi (cek config.json / env).');

  // mulai baca OpenClaw di latar (tak memblok)
  refreshAgentName();
  if (TEACHER || STUDENT) { refreshAgents(); refreshTasks(); refreshBusy(); refreshToolActivity(); } else refreshSubAgent();

  let hb, rs, rn, bye;

  if (TEACHER) {
    // ==== PC GURU: main -> kucing tengah, sub-agent -> guest ====
    console.log(`[torang-monitor] aktif -> ${base()} [target=star-office/GURU] · main="${currentName()}" · kucing-tengah=main, guest=sub-agent · heartbeat ${CONFIG.HEARTBEAT_MS / 1000}s`);
    await tickTeacher();
    // tick secepat refresh biar sub-agent yang cuma hidup ~6-8 dtk tetap kelihatan
    hb = setInterval(() => tickTeacher(), CONFIG.REFRESH_MS);
    rs = setInterval(() => { refreshTasks(); refreshBusy(); refreshToolActivity(); }, CONFIG.REFRESH_MS);
    rn = setInterval(() => { refreshAgentName(); refreshAgents(); }, 30000);
    bye = async () => {
      clearInterval(hb); clearInterval(rs); clearInterval(rn);
      try { fs.existsSync(PID_FILE) && fs.unlinkSync(PID_FILE); } catch (_) {}
      // [TORANG] JANGAN keluarkan semua guest saat exit (restart/loop bikin semua hilang lalu join lagi).
      // Biarkan agent tetap di office; office menandai offline sendiri bila monitor benar-benar mati.
      try { await post('/set_state', { state: 'idle', detail: 'menunggu' }); } finally { process.exit(0); }
    };
  } else if (STUDENT) {
    // ==== PC MURID: baca 4 agent (main + 3 worker) dari OpenClaw PC ini, push SEMUA sbg guest ====
    console.log(`[torang-monitor] aktif -> ${base()} [target=star-office/MURID] · label="${CONFIG.LABEL}" · 4 agent(main+worker)->guest · refresh ${CONFIG.REFRESH_MS / 1000}s`);
    await tickWorkers(true);
    hb = setInterval(() => tickWorkers(true), CONFIG.REFRESH_MS);
    rs = setInterval(() => { refreshTasks(); refreshBusy(); refreshToolActivity(); }, CONFIG.REFRESH_MS);
    rn = setInterval(() => { refreshAgentName(); refreshAgents(); }, 30000);
    bye = async () => {
      clearInterval(hb); clearInterval(rs); clearInterval(rn);
      try { fs.existsSync(PID_FILE) && fs.unlinkSync(PID_FILE); } catch (_) {}
      // [TORANG] JANGAN keluarkan semua guest saat exit (restart/loop bikin semua hilang lalu join lagi).
      // Biarkan agent tetap di office; office menandai offline sendiri bila monitor benar-benar mati.
      process.exit(0);
    };
  } else {
    // ==== target mock 'torang' (kontrak lama, satu agent) ====
    console.log(`[torang-monitor] aktif -> ${base()} [target=${CONFIG.TARGET}] · client_id=${CLIENT_ID} · agent="${currentName()}" · heartbeat ${CONFIG.HEARTBEAT_MS / 1000}s`);
    await post('/join-agent', joinBody());
    await post('/agent-push', pushBody());
    hb = setInterval(() => post('/agent-push', pushBody()), CONFIG.HEARTBEAT_MS);
    rs = setInterval(() => { refreshSubAgent(); }, CONFIG.REFRESH_MS);
    rn = setInterval(() => { refreshAgentName(); }, 60000);
    bye = async () => {
      clearInterval(hb); clearInterval(rs); clearInterval(rn);
      try { fs.existsSync(PID_FILE) && fs.unlinkSync(PID_FILE); } catch (_) {}
      try { await post('/leave-agent', leaveBody()); } finally { process.exit(0); }
    };
  }

  process.on('SIGINT', bye); process.on('SIGTERM', bye);
  process.on('uncaughtException', (e) => dbg('uncaughtException', { err: e.message }));
  process.on('unhandledRejection', (e) => dbg('unhandledRejection', { err: String(e) }));
}

if (require.main === module) main();
module.exports = { currentName, currentSub, refreshAgentName, refreshTasks, refreshBusy, mapTaskName };
