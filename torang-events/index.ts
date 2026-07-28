/**
 * Torang Events — v0.2 (FIX: non-blocking, TIDAK menyentuh hasil tool)
 * ============================================================
 * Kenapa v0.1 bikin laporan sub-agent KOSONG:
 *   handler `after_tool_call` v0.1 mem-`await` POST ke office DI DALAM jalur
 *   eksekusi tool. `fetch`-nya juga tanpa timeout. Jadi kalau office lambat /
 *   mati / IP-nya tak reachable, tool `collaborationspawn_agent` &
 *   `collaborationwait_agent` (yang membawa TASK ke sub-agent & HASIL balik ke
 *   main) ikut ketahan → sub-agent timeout → main lapor kosong.
 *
 * Perubahan v0.2:
 *   1. Handler TIDAK PERNAH await network. Semua POST office = fire-and-forget
 *      (dispatch lalu handler langsung selesai). Office lambat/mati TIDAK lagi
 *      menahan tool call sub-agent.
 *   2. `fetch` pakai AbortController timeout 1.5s → koneksi menggantung auto-batal.
 *   3. Cocokkan nama tool PERSIS (bukan regex /spawn/ /wait/ yang bisa kena tool lain).
 *   4. Seluruh handler dibungkus try/catch → tidak pernah melempar error ke runtime.
 *   5. Handler observer murni: tidak me-return nilai apa pun. (Lihat CATATAN di bawah.)
 *
 * CATATAN: `api.on(...)` hampir pasti OBSERVER (nilai return diabaikan). Tapi
 * biar aman kalau ternyata TRANSFORM (handler wajib balikin hasil tool), handler
 * ini menutup dengan PASSTHROUGH DEFENSIF: mengembalikan hasil tool asli apa
 * adanya (dari context.result / event.result / event.output). Untuk observer,
 * nilai itu diabaikan (aman). Untuk transform, hasil sub-agent TIDAK ketimpa.
 * Kalau setelah enable v0.2 sub-agent MASIH kosong, kirim aku:
 *     openclaw plugins inspect torang-events --runtime --json
 * (berarti bentuk return transform-nya beda) — aku sesuaikan dalam hitungan menit.
 * ============================================================ */
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import * as fs from "node:fs";
import * as os from "node:os";
import * as crypto from "node:crypto";

const LOG = os.homedir() + "/torang-events.log";
function log(...a: any[]) { try { fs.appendFileSync(LOG, new Date().toISOString() + " " + a.map((x) => typeof x === "string" ? x : JSON.stringify(x)).join(" ") + "\n"); } catch (_) {} }

// Nama tool spawn/wait di OpenClaw 2026.7.x. Bisa ditimpa lewat env kalau versimu beda.
const SPAWN_TOOLS = (process.env.TORANG_SPAWN_TOOLS || "collaborationspawn_agent,spawn_agent,sessions_spawn").split(",").map((s) => s.trim()).filter(Boolean);
const WAIT_TOOLS  = (process.env.TORANG_WAIT_TOOLS  || "collaborationwait_agent,wait_agent").split(",").map((s) => s.trim()).filter(Boolean);

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
function prefix(): string { try { const u = os.userInfo().username; if (u && u !== "root") return u; } catch (_) {} return os.hostname(); }

export default definePluginEntry({
  id: "torang-events",
  name: "Torang Events",
  description: "hatch instan subagent -> office (v0.2, non-blocking)",
  register(api: any) {
    const c = cfg(); const PREFIX = prefix();
    const born = new Map<string, { clientId: string; name: string; order: number }>();
    let seq = 0;

    // Fire-and-forget: TIDAK PERNAH di-await oleh handler. Timeout keras 1.5s.
    function send(path: string, body: any) {
      let ctl: AbortController | null = null; let t: any = null;
      try { ctl = new AbortController(); t = setTimeout(() => { try { ctl!.abort(); } catch (_) {} }, 1500); } catch (_) {}
      Promise.resolve()
        .then(() => fetch(c.url + path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body), signal: ctl ? ctl.signal : undefined }))
        .then((r: any) => log("POST", path, r && r.status))
        .catch((e: any) => log("POST ERR", path, String((e && e.message) || e)))
        .finally(() => { if (t) clearTimeout(t); });
    }
    function leave(key: string, why: string) {
      const g = born.get(key); if (!g) return; born.delete(key);
      send("/leave-agent", { client_id: g.clientId, joinKey: c.key }); log("LEAVE", g.name, why);
    }
    function leaveOldest(why: string) {
      let ok: string | null = null, o = Infinity;
      for (const [k, v] of born) if (v.order < o) { o = v.order; ok = k; }
      if (ok) leave(ok, why);
    }

    log("REGISTER v0.2; office=", c.url, "spawnTools=", SPAWN_TOOLS.join("|"));

    // Observer murni & non-blocking. Handler ini WAJIB: (a) tidak throw,
    // (b) tidak await network, (c) tidak me-return nilai yang bisa mengubah hasil tool.
    api.on("after_tool_call", (event: any, context: any) => {
      try {
        const tool = String((event && event.toolName) || "");
        if (SPAWN_TOOLS.includes(tool)) {
          const p = (event && event.params) || {};
          const key = String((context && context.toolCallId) || (event && event.toolCallId) || ("sp" + (++seq)));
          if (born.has(key)) return;
          const raw = String(p.task_name || p.name || p.label || "").replace(/^.*\//, "").slice(0, 24);
          const name = `${PREFIX} · ${raw || ("subagent-" + (seq + 1))} (temp)`;
          const clientId = cid(key);
          born.set(key, { clientId, name, order: ++seq });
          send("/join-agent", { client_id: clientId, joinKey: c.key, name, state: "idle", detail: "baru lahir", room: "tamu" });
          log("HATCH", name);
          setTimeout(() => { try { if (born.has(key)) send("/agent-push", { client_id: clientId, joinKey: c.key, name, state: "executing", detail: "bekerja", room: "data" }); } catch (_) {} }, 3000);
          setTimeout(() => { try { leave(key, "ttl"); } catch (_) {} }, 240000);
        } else if (WAIT_TOOLS.includes(tool)) {
          leaveOldest("selesai");
        }
      } catch (e: any) { log("HANDLER ERR", String((e && e.message) || e)); }
      // PASSTHROUGH DEFENSIF: kalau after_tool_call = TRANSFORM, kembalikan hasil
      // tool ASLI apa adanya; kalau OBSERVER, nilai ini diabaikan (aman).
      try {
        if (context && typeof context === "object" && "result" in context) return (context as any).result;
        if (event && typeof event === "object" && "result" in event) return (event as any).result;
        if (event && typeof event === "object" && "output" in event) return (event as any).output;
      } catch (_) {}
      return undefined;
    });

    api.on("subagent_ended", (_e: any) => { try { leaveOldest("ended"); } catch (_) {} });
  },
});
