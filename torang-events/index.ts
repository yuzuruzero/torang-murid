/**
 * Torang Events — typed plugin OpenClaw (Cara B: HATCH INSTAN)
 * ============================================================
 * Tujuan: subagent yang BARU LAHIR langsung muncul di office (Ruang Tamu)
 * TANPA menunggu polling. Menutup gap X1 "hatch moment" dari spec telemetri.
 *
 *   subagent_spawned  -> POST /join-agent  (karakter (temp) muncul di Ruang Tamu)
 *   after_tool_call   -> POST /agent-push  (pindah ruang sesuai tool: web/data/cs)
 *   subagent_ended    -> POST /leave-agent (karakter keluar)
 *
 * Main agent & worker permanen TETAP diurus monitor-client.js (polling) — plugin ini
 * fokus ke subagent transient (yang tak punya karakter tetap). client_id plugin memakai
 * namespace sendiri ("torang-plugin:") sehingga TIDAK bentrok dgn monitor.
 *
 * Metadata-only: TIDAK membaca params/result/isi tool. Tak butuh allowConversationAccess.
 * Config office URL + join key dibaca dari env atau file config monitor (lihat readConfig).
 * ============================================================ */
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as crypto from "node:crypto";

/* --- config: OFFICE_URL + JOIN_KEY (env -> file config monitor -> default) --- */
function readConfig(): { officeUrl: string; joinKey: string } {
  let officeUrl = process.env.TORANG_OFFICE_URL || "";
  let joinKey = process.env.TORANG_JOIN_KEY || "";
  const home = os.homedir();
  const files = [
    path.join(home, ".torang", "config.env"),        // murid
    path.join(home, ".torang-guru", "config.env"),   // guru
    path.join(home, ".torang-events.env"),           // override khusus plugin
  ];
  for (const f of files) {
    if (officeUrl && joinKey) break;
    try {
      if (!fs.existsSync(f)) continue;
      for (const line of fs.readFileSync(f, "utf8").split(/\r?\n/)) {
        const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
        if (!m) continue;
        if (m[1] === "TORANG_OFFICE_URL" && !officeUrl) officeUrl = m[2];
        if (m[1] === "TORANG_JOIN_KEY" && !joinKey) joinKey = m[2];
      }
    } catch (_) { /* abaikan */ }
  }
  if (!officeUrl) officeUrl = "http://127.0.0.1:19000"; // default: office lokal (guru)
  if (!joinKey) joinKey = "ocj_test";
  return { officeUrl: officeUrl.replace(/\/+$/, ""), joinKey };
}

/* --- peta tool -> ruang (samakan dengan monitor-client.js) --- */
const TOOL_ROOM: Record<string, string> = {
  web_search: "web", web_fetch: "web", browser: "web", navigate: "web", fetch_url: "web", http_request: "web",
  memory_search: "data", sessions_list: "data", sessions_history: "data", read: "data", file_read: "data",
  read_file: "data", grep: "data", glob: "data", list_dir: "data",
  apply_patch: "cs", write: "cs", edit: "cs", write_file: "cs", sessions_send: "cs", message_send: "cs", bash: "cs",
};
function toolRoom(t?: string): string | null {
  return t ? (TOOL_ROOM[String(t).toLowerCase()] || null) : null;
}

/* --- client_id stabil (UUID) dari session key subagent --- */
function clientIdFor(sessionKey: string): string {
  const h = crypto.createHash("sha1").update("torang-plugin:" + sessionKey).digest("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}

/* --- awalan nama (username Ubuntu, fallback hostname) — samakan dgn monitor --- */
function labelPrefix(): string {
  try { const u = os.userInfo().username; if (u && u !== "root") return u; } catch (_) {}
  return os.hostname();
}

export default definePluginEntry({
  id: "torang-events",
  name: "Torang Events",
  description: "Dorong subagent baru lahir & aktivitas tool ke Torang office (hatch instan)",

  register(api: any) {
    const cfg = readConfig();
    const PREFIX = labelPrefix();
    // ingat sessionKey subagent -> karakternya (biar tool_call & ended tahu siapa)
    const known = new Map<string, { clientId: string; name: string }>();

    async function post(pathname: string, body: any): Promise<void> {
      try {
        const ctrl = new AbortController();
        const t = setTimeout(() => ctrl.abort(), 3000);
        try {
          await fetch(cfg.officeUrl + pathname, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body),
            signal: ctrl.signal,
          });
        } finally { clearTimeout(t); }
      } catch (_) { /* fire-and-forget: telemetry gagal != agent gagal */ }
    }

    console.log("[torang-events] aktif -> office", cfg.officeUrl);

    // 1) SUBAGENT LAHIR -> langsung muncul di Ruang Tamu (X1 hatch)
    api.on("subagent_spawned", async (event: any) => {
      const sk = String(event?.childSessionKey || event?.runId || "");
      if (!sk) return;
      const clientId = clientIdFor(sk);
      const base = String(event?.label || event?.agentId || "Subagent").slice(0, 24);
      const name = `${PREFIX} · ${base} (temp)`;
      known.set(sk, { clientId, name });
      console.log("[torang-events] hatch:", name);
      await post("/join-agent", {
        client_id: clientId, joinKey: cfg.joinKey, name,
        state: "idle", detail: "baru lahir", room: "tamu",
      });
    });

    // 2) SUBAGENT PAKAI TOOL -> pindah ruang instan (cari->web, olah->data, hasilkan->cs)
    api.on("after_tool_call", async (event: any, context: any) => {
      const sk = String(context?.sessionKey || "");
      const room = toolRoom(event?.toolName);
      if (!sk || !room) return;
      const g = known.get(sk);
      if (!g) return; // hanya subagent yang kita kenal (yang lahir via spawn)
      await post("/agent-push", {
        client_id: g.clientId, joinKey: cfg.joinKey, name: g.name,
        state: "executing", detail: `pakai ${event?.toolName}`, room,
      });
    });

    // 3) SUBAGENT SELESAI -> keluar dari office
    api.on("subagent_ended", async (event: any) => {
      const sk = String(event?.targetSessionKey || "");
      if (!sk) return;
      const g = known.get(sk);
      if (!g) return;
      known.delete(sk);
      console.log("[torang-events] keluar:", g.name);
      await post("/leave-agent", { client_id: g.clientId, joinKey: cfg.joinKey });
    });
  },
});
