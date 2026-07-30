/**
 * Torang Events — v0.9 (HATCH INSTAN subagent -> office)
 * ============================================================
 * Kenapa v0.1/v0.2 diam total (REGISTER ada, HATCH nol):
 *   Keduanya menebak kelahiran subagent dari NAMA TOOL lewat `after_tool_call`
 *   (`collaborationspawn_agent`, `collaborationwait_agent`). Nama itu tidak
 *   pernah ada di OpenClaw 2026.7.x. Tool aslinya `sessions_spawn`
 *   (runtime="subagent"), dan yang lebih penting: runtime ini SUDAH punya hook
 *   khusus untuk ini. Menebak dari nama tool tidak pernah perlu.
 *
 * Hook resmi yang dipakai (terverifikasi di plugin-sdk 2026.7.1-2):
 *   subagent_spawned -> { childSessionKey, agentId, label, mode, runId }
 *   subagent_ended   -> { targetSessionKey, outcome, reason, runId }
 *   session_end      -> { sessionKey, reason }
 *
 * Tiga jebakan yang ditemukan saat verifikasi di PC ini:
 *
 * 1. `register()` DIPANGGIL BERULANG dalam proses gateway yang sama. Setiap
 *    panggilan bikin closure baru, jadi state di `Map` memori hilang di antara
 *    `subagent_spawned` dan sinyal selesai — karakter lahir lalu tak pernah
 *    keluar sampai TTL. Karena itu state disimpan di FILE, bukan di memori.
 *
 * 2. Endpoint `/leave-agent` office hanya menerima `agentId` atau `name`;
 *    `client_id` diabaikan (beda dari /join-agent dan /agent-push yang sudah
 *    mendukungnya). Jadi leave mengirim ketiganya sekaligus.
 *
 * 3. TIDAK ADA handler `after_tool_call` di plugin ini, dan itu disengaja.
 *    Dibuktikan 29 Jul 2026: hook itu HANYA terpicu untuk tool milik main agent,
 *    tidak pernah untuk subagent. Subagent `business-analyst` menjalankan `bash`
 *    dua kali menurut `openclaw audit`, tapi hook tidak memancarkan satu pun
 *    event untuknya; `runId` yang masuk selalu milik main (`98db47f8…`), tak
 *    pernah milik subagent (`2e1c1746…`), jadi korelasi `runId` mustahil cocok.
 *    Karena itu peta tool->ruang dan field `runId` di state sudah dibuang —
 *    keduanya kode mati. Ruang subagent kini diturunkan dari IDENTITAS agent
 *    (lihat `resolveRoom`), dan perpindahan berbasis aktivitas tetap tugas
 *    monitor-client lewat `openclaw audit`.
 *    (Catatan nama tool: di lapisan hook, tool shell bernama `exec`; di
 *    `openclaw audit` tool yang sama muncul sebagai `bash`.)
 *
 * `agent_end` sengaja TIDAK dipakai walau menggoda: runtime memblokirnya kecuali
 * allowConversationAccess=true, dan plugin ini tidak boleh membaca percakapan.
 *
 * Batas etika (wajib): hanya METADATA (id sesi, id agent, label tugas). Tidak
 * pernah membaca isi percakapan, isi file, atau layar.
 *
 * Telemetri gagal != agent gagal: semua POST ke office fire-and-forget, timeout
 * keras 4 dtk, seluruh handler dibungkus try/catch dan tidak pernah await.
 * ============================================================ */
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import * as fs from "node:fs";
import * as os from "node:os";
import * as crypto from "node:crypto";

const LOG = os.homedir() + "/torang-events.log";
const STATE = os.homedir() + "/.torang-events-state.json";
function log(...a: any[]) { try { fs.appendFileSync(LOG, new Date().toISOString() + " " + a.map((x) => typeof x === "string" ? x : JSON.stringify(x)).join(" ") + "\n"); } catch (_) {} }

const DEBUG = process.env.TORANG_DEBUG === "1";
// Lama singgah di Ruang Tamu sebelum pindah ke ruang kerja. Dinaikkan dari 3000
// (v0.7, tetap) ke 6000: di TV 65 inci tiga detik terlalu singkat buat penonton
// menemukan karakter baru sebelum dia keburu pindah.
const MOVE_DELAY_MS = Math.max(0, Number(process.env.TORANG_HATCH_HOLD_MS ?? 6000) || 0);
const TTL_MS = 240000;         // jaring pengaman kalau sinyal selesai tak pernah datang
const POST_TIMEOUT_MS = 4000;  // 1500 ms dulu terlalu ketat: koneksi terputus padahal request sampai
// Lama singgah pamit di Ruang Tamu sebelum benar-benar keluar. 0 = langsung
// keluar (perilaku v0.6).
const LINGER_MS = Math.max(0, Number(process.env.TORANG_SUB_LINGER_MS ?? 8000) || 0);

// --- Tangga penentuan ruang, tiga tingkat ---------------------------------
// (a) identitas agent. Sama dengan AGENT_ROOM di monitor-client v3.9.
const AGENT_ROOM: Record<string, string> = {
  customer_service: "cs", cs: "cs",
  business_analyst: "data",
  desainer_etalase: "web", web_designer: "web",
};
// (b) tebak jenis kerja dari label tugas. Sama dengan SUBAGENT_ALIASES v3.9.
const SUBAGENT_ALIASES: Record<string, string> = {
  web_designer: "web_designer", web: "web_designer", website: "web_designer", frontend: "web_designer", ui: "web_designer", etalase: "web_designer",
  customer_service: "customer_service", cs: "customer_service", customer: "customer_service", support: "customer_service", layanan: "customer_service",
  business_analyst: "business_analyst", analyst: "business_analyst", analis: "business_analyst", analisis: "business_analyst", data: "business_analyst",
};
const ROLE_TO_ROOM: Record<string, string> = { web_designer: "web", customer_service: "cs", business_analyst: "data" };
const ROOM_STATE: Record<string, string> = { web: "writing", cs: "researching", data: "executing" };

// Persis mapTaskName() monitor v3.9: cocok penuh dulu, baru cocok sebagian.
function mapTaskName(tn: string): string | null {
  if (!tn) return null;
  const t = String(tn).toLowerCase();
  if (SUBAGENT_ALIASES[t]) return SUBAGENT_ALIASES[t];
  for (const k of Object.keys(SUBAGENT_ALIASES)) if (t.includes(k)) return SUBAGENT_ALIASES[k];
  return null;
}

// Id agent beda-beda antar mesin (`designer` vs `desainer_etalase`,
// `business-analyst` vs `business_analyst`). Normalkan dulu — huruf kecil, buang
// - dan _ — cocokkan persis, baru lewat kata kunci. Aturannya sama persis dengan
// agentRoom() di monitor-client v4.0 supaya keduanya tak beda pendapat.
function normId(s: string): string { return String(s || "").toLowerCase().replace(/[-_]/g, ""); }
const AGENT_ROOM_NORM: Record<string, string> = {};
for (const k of Object.keys(AGENT_ROOM)) AGENT_ROOM_NORM[normId(k)] = AGENT_ROOM[k];
function agentRoomByKeyword(agentId: string): string | null {
  const k = normId(agentId);
  if (!k) return null;
  if (k === "cs") return "cs";                        // token pendek: PERSIS saja,
  if (/design|web|etalase/.test(k)) return "web";     // jangan sampai kena "docs"/"specs"
  if (/customer|support|layanan/.test(k)) return "cs";
  if (/analy|analis|data/.test(k)) return "data";
  return null;
}

function resolveRoom(agentId: string, label: string): string {
  // (a) identitas agent, tahan variasi penamaan.
  const byId = AGENT_ROOM_NORM[normId(agentId)] || agentRoomByKeyword(agentId);
  if (byId) return byId;
  // (b) tebak dari label tugas.
  const role = mapTaskName(label);
  if (role && ROLE_TO_ROOM[role]) return ROLE_TO_ROOM[role];
  // (c) tak jelas -> DATA, bukan standby. Subagent dari main agent ber-agentId
  // "main" dan selalu jatuh ke sini; dia sedang bekerja, jadi tidak boleh
  // pernah tampil nganggur di Standby.
  return "data";
}

type Born = { clientId: string; name: string; room: string; bornAt: number; endedAt?: number };

// v0.9 — timer HATCH_HOLD yang belum meletus, per childSessionKey. Dibatalkan
// begitu subagent pamit/keluar. `move()` memang sudah menolak entri ber-endedAt
// (sejak v0.7), tapi membatalkan timernya lebih murah daripada membiarkannya
// meletus lalu ditolak — dan menutup celah kalau kunci yang sama dipakai ulang.
const holdTimers = new Map<string, any>();
function cancelHold(key: string) {
  const t = holdTimers.get(key);
  if (t) { try { clearTimeout(t); } catch (_) {} holdTimers.delete(key); }
}

function readState(): Record<string, Born> {
  try { const o = JSON.parse(fs.readFileSync(STATE, "utf8")); return (o && typeof o === "object") ? o : {}; } catch (_) { return {}; }
}
function writeState(s: Record<string, Born>) {
  try { const tmp = STATE + ".tmp"; fs.writeFileSync(tmp, JSON.stringify(s)); fs.renameSync(tmp, STATE); } catch (_) {}
}

function cfg(): { url: string; key: string } {
  let url = process.env.TORANG_OFFICE_URL || "", key = process.env.TORANG_JOIN_KEY || "";
  for (const f of [os.homedir() + "/.torang/config.env", os.homedir() + "/.torang-guru/config.env", os.homedir() + "/.torang-events.env"]) {
    if (url && key) break;
    try {
      for (const line of fs.readFileSync(f, "utf8").split(/\r?\n/)) {
        const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/); if (!m) continue;
        if (m[1] === "TORANG_OFFICE_URL" && !url) url = m[2];
        if (m[1] === "TORANG_JOIN_KEY" && !key) key = m[2];
      }
    } catch (_) {}
  }
  return { url: (url || "http://127.0.0.1:19000").replace(/\/+$/, ""), key: key || "ocj_test" };
}
function cid(s: string): string { const h = crypto.createHash("sha1").update("torang-plugin:" + s).digest("hex"); return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`; }

// Replika persis _torang_hash() di backend office (FNV-1a, `h` sengaja tidak
// direset tiap iterasi) supaya agentId yang kita kirim sama dengan yang dipakai
// office saat join.
function officeAgentId(clientId: string): string {
  const alpha = "abcdefghijklmnopqrstuvwxyz0123456789";
  let h = 2166136261, out = "";
  for (let i = 0; i < 12; i++) {
    for (const ch of clientId + "#" + i) h = Math.imul(h ^ ch.charCodeAt(0), 16777619) >>> 0;
    out += alpha[h % alpha.length];
  }
  return "agent_" + out;
}
function prefix(): string { try { const u = os.userInfo().username; if (u && u !== "root") return u; } catch (_) {} return os.hostname(); }

export default definePluginEntry({
  id: "torang-events",
  name: "Torang Events",
  description: "hatch instan subagent -> office (v0.9, timer pindah dibatalkan saat pamit)",
  register(api: any) {
    const c = cfg(); const PREFIX = prefix();

    // Fire-and-forget: TIDAK PERNAH di-await. Handler tetap kembali seketika,
    // timeout hanya membatasi koneksi yang menggantung di latar.
    function send(path: string, body: any) {
      let ctl: AbortController | null = null; let t: any = null;
      try { ctl = new AbortController(); t = setTimeout(() => { try { ctl!.abort(); } catch (_) {} }, POST_TIMEOUT_MS); } catch (_) {}
      Promise.resolve()
        .then(() => fetch(c.url + path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body), signal: ctl ? ctl.signal : undefined }))
        .then((r: any) => { if (DEBUG) log("POST", path, r && r.status); })
        .catch((e: any) => log("POST ERR", path, String((e && e.message) || e)))
        .finally(() => { if (t) clearTimeout(t); });
    }

    function move(key: string, room: string, detail: string) {
      const s = readState(); const g = s[key];
      // Sudah pamit -> jangan tarik balik ke ruang kerja. Timer HATCH_HOLD bisa
      // meletus jauh lebih lambat dari setelannya kalau mesin sibuk (terukur 13,4
      // dtk untuk setelan 6 dtk, uji 29 Jul 13:08), sedangkan subagent cuma hidup
      // 6-8 dtk — jadi urutannya bisa terbalik.
      if (!g || g.endedAt || g.room === room) return;
      g.room = room; writeState(s);
      send("/agent-push", { client_id: g.clientId, joinKey: c.key, name: g.name, state: ROOM_STATE[room] || "executing", detail, room });
      log("MOVE", g.name, "->", room, detail);
    }

    function leave(key: string, why: string) {
      cancelHold(key);
      const s = readState(); const g = s[key];
      if (!g) return;
      delete s[key]; writeState(s);
      send("/leave-agent", { client_id: g.clientId, agentId: officeAgentId(g.clientId), name: g.name, joinKey: c.key });
      log("LEAVE", g.name, why);
    }

    // Selesai: kembali ke Ruang Tamu untuk pamit, baru keluar. Ruang Tamu adalah
    // tempat datang dan pergi, jadi busurnya utuh: masuk -> kerja -> kembali ke
    // pintu -> pulang. Teks "selesai, pamit" tampil sebagai gelembung di atas
    // karakter (pengganti animasi melambaikan tangan yang belum ada).
    function farewell(key: string, why: string) {
      cancelHold(key);                          // v0.9: batalkan timer pindah yang belum meletus
      const s = readState(); const g = s[key];
      if (!g || g.endedAt) return;              // tak ada / sudah pamit
      if (LINGER_MS <= 0) { leave(key, why); return; }
      g.endedAt = Date.now(); g.room = "tamu"; writeState(s);
      send("/agent-push", { client_id: g.clientId, joinKey: c.key, name: g.name, state: "idle", detail: "selesai, pamit", room: "tamu" });
      log("BYE", g.name, why);
      setTimeout(() => { try { leave(key, why); } catch (_) {} }, LINGER_MS);
    }

    // Sapu karakter yatim. Dua kedaluwarsa: (1) sudah pamit tapi timer keluarnya
    // hilang bersama prosesnya, (2) tak pernah dapat sinyal selesai sama sekali.
    // Dipanggil di SEMUA hook, bukan cuma saat spawn — kalau tidak, satu subagent
    // yang menggantung bisa menunggu selamanya sampai ada subagent berikutnya.
    function sweep() {
      const s = readState(); const now = Date.now();
      for (const key of Object.keys(s)) {
        const g = s[key];
        if (g.endedAt) { if (now - g.endedAt > LINGER_MS) leave(key, "linger"); }
        else if (now - (g.bornAt || 0) > TTL_MS) leave(key, "ttl");
      }
    }

    log("REGISTER v0.9 pid=" + process.pid + "; office=", c.url, "hold=", MOVE_DELAY_MS, "linger=", LINGER_MS);

    // LAHIR — hook resmi, bukan tebakan nama tool.
    api.on("subagent_spawned", (event: any) => {
      try {
        sweep();
        const key = String((event && event.childSessionKey) || "");
        if (!key) return;
        const s = readState();
        if (s[key]) return;
        const agentId = String((event && event.agentId) || "");
        const label = String((event && event.label) || "");
        const raw = (label || agentId).replace(/^.*\//, "").slice(0, 24);
        const name = `${PREFIX} · ${raw || "subagent"} (temp)`;
        const clientId = cid(key);
        s[key] = { clientId, name, room: "tamu", bornAt: Date.now() };
        writeState(s);
        send("/join-agent", { client_id: clientId, joinKey: c.key, name, state: "idle", detail: "baru lahir", room: "tamu" });
        log("HATCH", name, key);
        const room = resolveRoom(agentId, label);
        holdTimers.set(key, setTimeout(() => {
          holdTimers.delete(key);
          try { move(key, room, "ruang " + (agentId || "subagent")); } catch (_) {}
        }, MOVE_DELAY_MS));
      } catch (e: any) { log("SPAWN ERR", String((e && e.message) || e)); }
    });

    // SELESAI (1) — dicocokkan persis lewat childSessionKey.
    api.on("subagent_ended", (event: any) => {
      try {
        sweep();
        const key = String((event && event.targetSessionKey) || "");
        if (key) farewell(key, String((event && event.outcome) || "selesai"));
      } catch (e: any) { log("END ERR", String((e && e.message) || e)); }
    });

    // SELESAI (2) — sesi anak ditutup. Metadata saja (sessionKey + reason).
    // Perlu karena `subagent_ended` tidak diemisikan untuk spawn mode "session".
    api.on("session_end", (event: any) => {
      try {
        sweep();
        const key = String((event && event.sessionKey) || "");
        if (key) farewell(key, "sesi-" + String((event && event.reason) || "tutup"));
      } catch (e: any) { log("END ERR", String((e && e.message) || e)); }
    });
  },
});
