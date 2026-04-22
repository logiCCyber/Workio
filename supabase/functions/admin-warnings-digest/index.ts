import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Worker = {
  id: string;
  auth_user_id: string;
  owner_admin_id: string;
  email?: string;
  name?: string;
};

type ShiftEvent = {
  worker_id: string;
  event_type: string;
  created_at: string;
};

type WarningItem = {
  key?: string;
  level: "critical" | "warning";
  icon: string;
  title: string;
  message: string;
  signature?: string;
};

serve(async (req) => {
  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const RESEND_API_KEY =
      Deno.env.get("RESEND_API_KEY") || Deno.env.get("SUCCESS_REG") || "";
  const EMAIL_FROM =
      Deno.env.get("EMAIL_FROM") ||
      Deno.env.get("FROM_EMAIL") ||
      "Workio <noreply@workio.ca>";
  const CRON_SECRET = Deno.env.get("CRON_SECRET") || "";

  const corsHeaders: Record<string, string> = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type, x-cron-secret",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Content-Type": "application/json",
  };

  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: corsHeaders,
    });
  }

  // Optional protection for cron/manual calls
  if (CRON_SECRET) {
    const got = req.headers.get("x-cron-secret") ?? "";
    if (got !== CRON_SECRET) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: corsHeaders,
      });
    }
  }

  if (!RESEND_API_KEY) {
    return new Response(JSON.stringify({ error: "RESEND_API_KEY missing" }), {
      status: 500,
      headers: corsHeaders,
    });
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

  const now = new Date();
  const nowIso = now.toISOString();

  // Thresholds
  const UNPAID_CRITICAL_DAYS = 14; // > 2 weeks
  const LONG_SHIFT_WARNING_MINUTES = 8 * 60 + 30; // 8h 30m
  const LONG_SHIFT_CRITICAL_MINUTES = 9 * 60 + 30; // 9h 30m

  // Anti-spam resend windows
  const RESEND_UNPAID_14D_MINUTES = 48 * 60; // раз в 2 дня
  const RESEND_LONG_SHIFT_MINUTES = 120;       // раз в 2 часа пока смена длится
  const RESEND_LONG_SHIFT_CRITICAL_MINUTES = 60; // critical можно слать чаще
  const RESEND_MULTI_STARTS_MINUTES = 24 * 60; // раз в сутки

  const unpaidCriticalBefore = new Date(
      now.getTime() - UNPAID_CRITICAL_DAYS * 24 * 3600 * 1000,
  ).toISOString();

  const longShiftBefore = new Date(
      now.getTime() - LONG_SHIFT_WARNING_MINUTES * 60 * 1000,
  ).toISOString();

  // "Today" in UTC (good enough to start)
  const dayStartUtc = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 0, 0, 0, 0),
  ).toISOString();

  function isStartEvent(t: string) {
    const x0 = (t || "").toLowerCase().trim();
    const x = x0.replace(/[\s-]+/g, "_"); // ✅ "shift started" -> "shift_started"

    return (
        x === "start" ||
        x === "started" ||
        x === "shift_start" ||
        x === "shift_started" ||
        x === "clock_in" ||
        x === "check_in" ||
        x === "on" ||
        x === "shift_on" ||
        x === "start_shift" ||
        x === "shiftstart"
    );
  }

  function money(v: number) {
    return `$${v.toFixed(2)}`;
  }

  function makeWarningKey(adminId: string, type: string, entityId: string) {
    return `${adminId}::${type}::${entityId}`;
  }

  function minutesSince(iso?: string | null) {
    if (!iso) return Infinity;
    const t = new Date(iso).getTime();
    if (!Number.isFinite(t)) return Infinity;
    return Math.floor((Date.now() - t) / 60000);
  }

  function fmtDate(iso: string) {
    try {
      const d = new Date(iso);
      return d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
    } catch {
      return iso;
    }
  }

  function fmtTime(iso: string) {
    try {
      const d = new Date(iso);
      return d.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" });
    } catch {
      return iso;
    }
  }

  function renderEmailHtml(params: {
    adminEmail: string;
    generatedAtIso: string;
    critical: WarningItem[];
    warnings: WarningItem[];
  }) {
    const { adminEmail, generatedAtIso, critical, warnings } = params;

    const logoUrl =
        "https://mnycxmpofeajhjecsvhk.supabase.co/storage/v1/object/public/images/mahmadiyarov.png";

    const year = new Date().getFullYear();

    const fmtDateTime = (iso: string) => {
      try {
        const d = new Date(iso);
        return d.toLocaleString("en-US", {
          month: "short",
          day: "2-digit",
          year: "numeric",
          hour: "2-digit",
          minute: "2-digit",
        });
      } catch {
        return iso;
      }
    };

    const generated = fmtDateTime(generatedAtIso);

    const countPill = (label: string, value: number, color: string, bg: string, border: string) => `
    <table role="presentation" align="center" cellpadding="0" cellspacing="0" border="0" style="margin:0 auto;">
      <tr>
        <td align="center"
            style="padding:8px 14px;border-radius:999px;
                   background:${bg};border:1px solid ${border};
                   color:${color};font-size:12px;font-weight:900;letter-spacing:0.5px;">
          ${label}: ${value}
        </td>
      </tr>
    </table>
  `;

    const itemRow = (it: WarningItem, accent: string, softBg: string, softBorder: string) => `
    <tr>
      <td style="padding:0 0 12px 0;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
          style="background:rgba(255,255,255,0.04);
                 border:1px solid rgba(255,255,255,0.08);
                 border-radius:18px;border-collapse:separate;border-spacing:0;">
          <tr>
            <td width="56" valign="top" style="padding:14px 0 14px 14px;">
              <table role="presentation" width="40" cellpadding="0" cellspacing="0" border="0"
                style="background:${softBg};border:1px solid ${softBorder};border-radius:14px;">
                <tr>
                  <td align="center" valign="middle"
                      style="width:40px;height:40px;font-size:18px;line-height:40px;">
                    ${it.icon}
                  </td>
                </tr>
              </table>
            </td>
            <td valign="top" style="padding:14px 14px 14px 10px;">
              <div style="color:#F3F5F8;font-size:15px;line-height:20px;font-weight:900;">
                ${it.title}
              </div>
              <div style="height:6px;"></div>
              <div style="color:rgba(183,188,203,0.88);font-size:13px;line-height:20px;font-weight:700;word-break:break-word;">
                ${it.message}
              </div>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  `;

    const section = (
        title: string,
        items: WarningItem[],
        accent: string,
        softBg: string,
        softBorder: string,
    ) => {
      if (!items.length) return "";

      return `
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:20px;">
        <tr>
          <td>
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td align="left"
                    style="color:#F3F5F8;font-size:14px;line-height:18px;font-weight:900;letter-spacing:0.3px;">
                  ${title}
                </td>
                <td align="right">
                  <span style="display:inline-block;padding:6px 10px;border-radius:999px;
                               background:${softBg};border:1px solid ${softBorder};
                               color:${accent};font-size:11px;font-weight:900;letter-spacing:0.5px;">
                    ${items.length}
                  </span>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <tr>
          <td height="10" style="font-size:0;line-height:0;">&nbsp;</td>
        </tr>

        <tr>
          <td>
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
              ${items.map((it) => itemRow(it, accent, softBg, softBorder)).join("")}
            </table>
          </td>
        </tr>
      </table>
    `;
    };

    const emptyState =
        critical.length === 0 && warnings.length === 0
            ? `
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
        style="margin-top:20px;background:rgba(108,255,141,0.07);
               border:1px solid rgba(108,255,141,0.18);
               border-radius:18px;border-collapse:separate;border-spacing:0;">
        <tr>
          <td style="padding:14px 16px;">
            <div style="color:#F3F5F8;font-size:14px;line-height:18px;font-weight:900;">
              ✅ All good
            </div>
            <div style="height:6px;"></div>
            <div style="color:rgba(183,188,203,0.82);font-size:12.5px;line-height:19px;font-weight:700;">
              No warning conditions are active right now.
            </div>
          </td>
        </tr>
      </table>
    `
            : "";

    return `<!doctype html>
<html style="margin:0;padding:0;background:#0B0D12;">
  <body style="margin:0;padding:0;background:#0B0D12;font-family:Arial,Helvetica,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
           style="margin:0;padding:0;background:#0B0D12;mso-table-lspace:0pt;mso-table-rspace:0pt;">
      <tr>
        <td align="center" style="padding:24px 12px;background:#0B0D12;">
          <table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0"
                 style="max-width:560px;width:100%;background:#1E1C22;border-radius:22px;
                        border:1px solid rgba(255,255,255,0.10);
                        box-shadow:0 18px 50px rgba(0,0,0,0.55);
                        border-collapse:separate;border-spacing:0;">
            <tr>
              <td style="padding:18px 18px 18px 18px;">

                <!-- TOP BAR -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td valign="middle">
                      <img src="${logoUrl}" height="46" alt="Workio"
                           style="display:block;object-fit:contain;" />
                    </td>
                    <td align="right" valign="middle"
                        style="color:#A8B0C2;font-size:12px;font-weight:800;white-space:nowrap;">
                      Security email
                    </td>
                  </tr>
                </table>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr><td height="14" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td style="height:1px;background:rgba(255,255,255,0.07);font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td height="18" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                </table>

                <!-- TITLE -->
                <div style="color:#FFFFFF;font-size:30px;font-weight:900;letter-spacing:-0.25px;line-height:36px;text-align:center;">
                  Admin alerts digest
                </div>

                <div style="height:8px;"></div>

                <div style="color:rgba(183,188,203,0.86);font-size:14px;line-height:20px;text-align:center;font-weight:700;">
                  We found potential issues in shifts and payouts that may need your attention.
                </div>

                <div style="height:16px;"></div>

                <!-- GREEN CENTER ACCENT -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td style="height:2px;background:transparent;"></td>
                    <td width="220" style="height:2px;background:rgba(108,255,141,0.55);font-size:0;line-height:0;">&nbsp;</td>
                    <td style="height:2px;background:transparent;"></td>
                  </tr>
                </table>

                <div style="height:18px;"></div>

                <!-- SUMMARY CARD -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="background:rgba(255,255,255,0.04);
                              border:1px solid rgba(255,255,255,0.08);
                              border-radius:18px;border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td style="padding:16px 16px 14px 16px;">

                      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td align="center">
                            ${countPill("CRITICAL", critical.length, "#FB7185", "rgba(251,113,133,0.08)", "rgba(251,113,133,0.18)")}
                          </td>
                          <td width="10">&nbsp;</td>
                          <td align="center">
                            ${countPill("WARNINGS", warnings.length, "#F59E0B", "rgba(245,158,11,0.08)", "rgba(245,158,11,0.18)")}
                          </td>
                        </tr>
                      </table>

                      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                        <tr><td height="14" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                      </table>

                      <div style="color:#EDEFF6;font-size:13px;line-height:18px;font-weight:800;text-align:center;">
                        Generated: ${fmtDateTime(generatedAtIso)}
                      </div>

                      <div style="height:8px;"></div>

                      <div style="color:rgba(183,188,203,0.78);font-size:12px;line-height:17px;font-weight:700;text-align:center;">
                        Recipient:
                        <a href="mailto:${adminEmail}" style="color:#8FC7FF;text-decoration:underline;">
                          ${adminEmail}
                        </a>
                      </div>

                    </td>
                  </tr>
                </table>

                ${section("Critical issues", critical, "#FB7185", "rgba(251,113,133,0.08)", "rgba(251,113,133,0.18)")}
                ${section("Warnings", warnings, "#F59E0B", "rgba(245,158,11,0.08)", "rgba(245,158,11,0.18)")}
                ${emptyState}

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:18px;">
                  <tr>
                    <td style="background:rgba(255,255,255,0.04);
                               border:1px solid rgba(255,255,255,0.08);
                               border-radius:16px;padding:12px 14px;">
                      <div style="color:#EDEFF6;font-size:12.5px;line-height:17px;font-weight:900;">
                        Thresholds
                      </div>
                      <div style="height:5px;"></div>
                      <div style="color:rgba(183,188,203,0.78);font-size:12px;line-height:18px;font-weight:700;">
                        Unpaid 14+ days • live shift 8h 30m+ warning • 9h 30m+ critical • multiple starts/day
                      </div>
                    </td>
                  </tr>
                </table>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr><td height="16" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td style="height:1px;background:rgba(255,255,255,0.07);font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td height="14" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                </table>

                <!-- FOOTER -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td align="center"
                        style="color:rgba(237,239,246,0.82);font-size:12px;line-height:16px;font-weight:900;letter-spacing:0.2px;">
                      Workio • ${year}
                    </td>
                  </tr>
                  <tr>
                    <td height="8" style="font-size:0;line-height:0;">&nbsp;</td>
                  </tr>
                  <tr>
                    <td align="center"
                        style="color:rgba(183,188,203,0.48);font-size:11px;line-height:17px;font-weight:700;">
                      Automated admin digest. Do not reply.
                    </td>
                  </tr>
                </table>

              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`;
  }


  try {
    // 1) Active workers with owner_admin_id
    const { data: workersRaw, error: wErr } = await supabase
        .from("workers")
        .select("id, auth_user_id, owner_admin_id, email, name, is_active")
        .eq("is_active", true);

    if (wErr) {
      return new Response(JSON.stringify({ error: wErr.message }), {
        status: 500,
        headers: corsHeaders,
      });
    }

    const workers = (workersRaw ?? []) as Worker[];
    if (!workers.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0, message: "No workers" }), {
        status: 200,
        headers: corsHeaders,
      });
    }

    // 2) Group workers by admin
    const byAdmin = new Map<string, Worker[]>();
    for (const w of workers) {
      const adminId = (w.owner_admin_id || "").trim();
      const authId = (w.auth_user_id || "").trim();
      if (!adminId || !authId) continue;
      if (!byAdmin.has(adminId)) byAdmin.set(adminId, []);
      byAdmin.get(adminId)!.push(w);
    }

    let sent = 0;

    for (const [adminId, adminWorkers] of byAdmin.entries()) {
      // Admin email
      const { data: adminUser, error: auErr } = await supabase.auth.admin.getUserById(adminId);
      const adminEmail = adminUser?.user?.email || "";
      if (auErr || !adminEmail) continue;

      const authIds = adminWorkers.map((w) => w.auth_user_id).filter(Boolean);
      const workerIds = adminWorkers.map((w) => w.id).filter(Boolean);

      if (authIds.length === 0) continue;

      // Index maps
      const byWorkerId = new Map<string, Worker>();
      const byAuthId = new Map<string, Worker>();
      for (const w of adminWorkers) {
        if (w.id) byWorkerId.set(w.id, w);
        if (w.auth_user_id) byAuthId.set(w.auth_user_id, w);
      }

      const critical: WarningItem[] = [];
      const warnings: WarningItem[] = [];

      type BuiltWarning = WarningItem & {
        warning_type:
            | "unpaid_14d"
            | "long_live_shift"
            | "long_live_shift_critical"
            | "multi_starts_today";
        entity_id: string;      // стабильный id (auth_user_id / worklog_id / worker id + date)
        fingerprint: string;    // строка или json-string, чтобы понять изменилось ли
      };

      const built: BuiltWarning[] = [];

      // ==========================
      // A) CRITICAL: unpaid older than 14 days
      // ==========================
      const { data: unpaidOldRaw, error: uoErr } = await supabase
          .from("work_logs")
          .select("id,user_id,start_time,end_time,total_payment,paid_at")
          .in("user_id", authIds)
          .not("end_time", "is", null)
          .is("paid_at", null)
          .lt("start_time", unpaidCriticalBefore)
          .order("start_time", { ascending: true });

      if (!uoErr && unpaidOldRaw?.length) {
        const list = unpaidOldRaw as any[];
        const sumByUser = new Map<string, number>();
        const oldestByUser = new Map<string, string>();
        const countByUser = new Map<string, number>();

        for (const r of list) {
          const uid = String(r.user_id || "");
          const pay = Number(r.total_payment || 0);
          sumByUser.set(uid, (sumByUser.get(uid) || 0) + pay);
          countByUser.set(uid, (countByUser.get(uid) || 0) + 1);

          const st = String(r.start_time || "");
          if (!oldestByUser.has(uid) || st < oldestByUser.get(uid)!) oldestByUser.set(uid, st);
        }

        for (const [uid, sum] of sumByUser.entries()) {
          const w = byAuthId.get(uid);
          const who = w ? `${w.name || "worker"} (${w.email || "—"})` : uid;
          const oldest = oldestByUser.get(uid) || "";
          const cnt = countByUser.get(uid) || 0;

          const msg = `${who}: ${money(sum)} across ${cnt} shift(s) • oldest shift: ${fmtDate(oldest)}`;

          critical.push({
            level: "critical",
            icon: "🧾",
            title: "Unpaid older than 14 days",
            message: msg,
          });

          built.push({
            level: "critical",
            icon: "🧾",
            title: "Unpaid older than 14 days",
            message: msg,
            warning_type: "unpaid_14d",
            entity_id: uid,                 // auth_user_id
            fingerprint: `${sum.toFixed(2)}|${cnt}|${oldest}`, // если сумма/кол-во/дата меняется — это “новое”
          });
        }
      }

      // ==========================
// B) LONG LIVE SHIFT:
// 8h30m+ = warning
// 9h30m+ = critical
// ==========================
      const { data: longLiveRaw, error: llErr } = await supabase
          .from("work_logs")
          .select("id,user_id,start_time,end_time,total_payment")
          .in("user_id", authIds)
          .is("end_time", null)
          .lt("start_time", longShiftBefore)
          .order("start_time", { ascending: true });

      if (!llErr && longLiveRaw?.length) {
        const list = longLiveRaw as any[];

        for (const r of list) {
          const uid = String(r.user_id || "");
          const w = byAuthId.get(uid);
          const who = w ? `${w.name || "worker"} (${w.email || "—"})` : uid;

          const st = String(r.start_time || "");
          const mins = Math.max(
              0,
              Math.round((now.getTime() - new Date(st).getTime()) / 60000),
          );

          const msg =
              `${who}: started ${fmtDate(st)} ${fmtTime(st)} • running ` +
              `${Math.floor(mins / 60)}h ${mins % 60}m`;

          if (mins >= LONG_SHIFT_CRITICAL_MINUTES) {
            critical.push({
              level: "critical",
              icon: "🚨",
              title: "Shift running critically long",
              message: msg,
            });

            built.push({
              level: "critical",
              icon: "🚨",
              title: "Shift running critically long",
              message: msg,
              warning_type: "long_live_shift_critical",
              entity_id: String(r.id || uid),
              fingerprint: `${uid}|${st}|critical`,
            });
          } else {
            warnings.push({
              level: "warning",
              icon: "⏱️",
              title: "Shift running too long",
              message: msg,
            });

            built.push({
              level: "warning",
              icon: "⏱️",
              title: "Shift running too long",
              message: msg,
              warning_type: "long_live_shift",
              entity_id: String(r.id || uid),
              fingerprint: `${uid}|${st}|warning`,
            });
          }
        }
      }

      // ==========================
      // C) WARNING: multiple starts today (>=2)
      // shift_events.worker_id may be workers.id OR auth_user_id
      // ==========================
      const bothIds = Array.from(new Set([...workerIds, ...authIds])).filter(Boolean);

      if (bothIds.length) {
        const { data: evRaw, error: evErr } = await supabase
            .from("shift_events")
            .select("worker_id,event_type,created_at")
            .in("worker_id", bothIds)
            .gte("created_at", dayStartUtc);

        console.log("multi_starts_today events:", evRaw?.length || 0);
        console.log("sample event_type:", evRaw?.[0]?.event_type);

        if (!evErr && evRaw?.length) {
          const events = evRaw as ShiftEvent[];
          const startsByRaw = new Map<string, number>();

          for (const e of events) {
            if (!isStartEvent(e.event_type)) continue;
            const k = String(e.worker_id || "").trim();
            if (!k) continue;
            startsByRaw.set(k, (startsByRaw.get(k) || 0) + 1);
          }

          for (const [rawId, cnt] of startsByRaw.entries()) {
            if (cnt < 2) continue;

            const w = byWorkerId.get(rawId) || byAuthId.get(rawId);
            const who = w ? `${w.name || "worker"} (${w.email || "—"})` : rawId;

            const msg = `${who}: starts today = ${cnt} • please review shift logs`;

            warnings.push({
              level: "warning",
              icon: "🔁",
              title: "Multiple starts today",
              message: msg,
            });

            built.push({
              level: "warning",
              icon: "🔁",
              title: "Multiple starts today",
              message: msg,
              warning_type: "multi_starts_today",
              entity_id: `${(w?.auth_user_id || w?.id || rawId)}|${dayStartUtc.substring(0,10)}`, // worker + YYYY-MM-DD
              fingerprint: `${cnt}`, // если cnt растёт — можно считать “обновление”
            });
          }
        }
      }

      // ===== Dedup / throttle via admin_warning_state =====
      const nowDb = new Date().toISOString();

      const { data: stateRows, error: stErr } = await supabase
          .from("admin_warning_state")
          .select("warning_key, warning_type, fingerprint, last_sent_at, muted_until, muted_forever, ack_expires_at, resolved_at")
          .eq("admin_id", adminId);

      const stateByKey = new Map<string, any>();
      if (!stErr && stateRows) {
        for (const r of stateRows as any[]) stateByKey.set(String(r.warning_key), r);
      }

      function resendWindowMinutes(t: BuiltWarning["warning_type"]) {
        if (t === "unpaid_14d") return RESEND_UNPAID_14D_MINUTES;
        if (t === "long_live_shift") return RESEND_LONG_SHIFT_MINUTES;
        if (t === "long_live_shift_critical") return RESEND_LONG_SHIFT_CRITICAL_MINUTES;
        return RESEND_MULTI_STARTS_MINUTES;
      }

      const activeKeys = new Set<string>();
      for (const w of built) {
        activeKeys.add(makeWarningKey(adminId, w.warning_type, w.entity_id));
      }

      for (const [key, st] of stateByKey.entries()) {
        if (!activeKeys.has(key) && !st?.resolved_at) {
          await supabase.from("admin_warning_state").update({
            resolved_at: nowDb,
            last_seen_at: nowDb,
          }).eq("admin_id", adminId).eq("warning_key", key);
        }
      }

      const sendable: BuiltWarning[] = [];

      for (const w of built) {
        const key = makeWarningKey(adminId, w.warning_type, w.entity_id);
        const st = stateByKey.get(key);

        const mutedForever = !!st?.muted_forever;
        const mutedUntil = st?.muted_until ? new Date(st.muted_until).getTime() : 0;
        const ackUntil = st?.ack_expires_at ? new Date(st.ack_expires_at).getTime() : 0;

        // ✅ 1) Mute/Ack применяем ко ВСЕМ, кроме unpaid_14d
        if (w.warning_type !== "unpaid_14d") {
          if (mutedForever) continue;
          if (mutedUntil && Date.now() < mutedUntil) continue;
          if (ackUntil && Date.now() < ackUntil) continue;
        }

        // ✅ 2) Считаем общие значения ОДИН раз
        const lastSentMin = minutesSince(st?.last_sent_at);
        const win = resendWindowMinutes(w.warning_type);
        const fingerprintChanged = !st || String(st.fingerprint) !== String(w.fingerprint);

        // ✅ 3) unpaid_14d: строго по таймеру (у тебя win = 48*60)
        if (w.warning_type === "unpaid_14d") {
          if (!st || lastSentMin >= win) {
            sendable.push(w);
          }
          continue;
        }

        // ✅ 4) остальные: как было (если fingerprint изменился — можно сразу)
        if (fingerprintChanged || lastSentMin >= win) {
          sendable.push(w);
        }
      }

// если нечего отправлять — всё равно обновим last_seen, но письмо не шлём

      // Nothing to send
      if (sendable.length === 0) {
        // обновим last_seen_at и выйдем
        // (чтобы понимать что проблема всё ещё есть, но мы не спамим)
        for (const w of built) {
          const key = makeWarningKey(adminId, w.warning_type, w.entity_id);
          await supabase.from("admin_warning_state").upsert({
            admin_id: adminId,
            warning_key: key,
            warning_type: w.warning_type,
            fingerprint: w.fingerprint,
            last_seen_at: nowDb,
            resolved_at: null,
          }, { onConflict: "admin_id,warning_key" });
        }
        continue;
      }

      // Send email
      const criticalToSend = sendable.filter(x => x.level === "critical");
      const warningsToSend  = sendable.filter(x => x.level === "warning");

// Send email
      const html = renderEmailHtml({
        adminEmail,
        generatedAtIso: nowIso,
        critical: criticalToSend,
        warnings: warningsToSend,
      });

      const subject =
          criticalToSend.length > 0
              ? `🚨 CRITICAL • Workio admin alerts • ${criticalToSend.length} critical / ${warningsToSend.length} warnings`
              : `⚠️ Workio admin alerts • ${warningsToSend.length} warnings`;

      console.log("sendable:", sendable.length, "critical:", criticalToSend.length, "warnings:", warningsToSend.length);


      const sendRes = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${RESEND_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: EMAIL_FROM,
          to: adminEmail,
          subject,
          html,
        }),
      });

      if (sendRes.ok) {
        sent++;

        for (const w of sendable) {
          const key = makeWarningKey(adminId, w.warning_type, w.entity_id);
          await supabase.from("admin_warning_state").upsert({
            admin_id: adminId,
            warning_key: key,
            warning_type: w.warning_type,
            fingerprint: w.fingerprint,
            last_seen_at: nowDb,
            last_sent_at: nowDb,
            resolved_at: null,
          }, { onConflict: "admin_id,warning_key" });
        }
      }
    }

    return new Response(JSON.stringify({ ok: true, sent }), {
      status: 200,
      headers: corsHeaders,
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});