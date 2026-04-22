import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
    return new Response(JSON.stringify(data), {
        status,
        headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
        },
    });
}

function escapeHtml(value: unknown) {
    return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
}

serve(async (req) => {
    if (req.method === "OPTIONS") {
        return new Response(null, {
            status: 200,
            headers: corsHeaders,
        });
    }

    if (req.method !== "POST") {
        return json({ error: "Method not allowed" }, 405);
    }

    try {
        const body = await req.json().catch(() => ({}));

        const event_type = String(body?.event_type ?? "").trim();
        const worker_email = String(body?.worker_email ?? "").trim().toLowerCase();
        const started_at = body?.started_at ? String(body.started_at) : undefined;
        const ended_at = body?.ended_at ? String(body.ended_at) : undefined;
        const hours = body?.hours;
        const earned = body?.earned;
        const address_text = body?.address_text;

        if (!event_type || !worker_email) {
            throw new Error("Missing required fields");
        }

        if (!["start", "end"].includes(event_type)) {
            throw new Error("Invalid event_type");
        }

        const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
        const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get(
            "SUPABASE_SERVICE_ROLE_KEY",
        );
        const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
        const FROM_EMAIL =
            Deno.env.get("FROM_EMAIL") || "Workio <noreply@workio.ca>";

        if (!SUPABASE_URL) throw new Error("SUPABASE_URL is missing");
        if (!SUPABASE_SERVICE_ROLE_KEY) {
            throw new Error("SUPABASE_SERVICE_ROLE_KEY is missing");
        }
        if (!RESEND_API_KEY) throw new Error("RESEND_API_KEY is missing");

        const supabase = createClient(
            SUPABASE_URL,
            SUPABASE_SERVICE_ROLE_KEY,
        );

        // 1) find worker
        const { data: worker, error: workerError } = await supabase
            .from("workers")
            .select("id, email, name, owner_admin_id")
            .eq("email", worker_email)
            .maybeSingle();

        if (workerError) {
            throw new Error(`Worker lookup failed: ${workerError.message}`);
        }

        if (!worker) {
            throw new Error("Worker not found");
        }

        if (!worker.owner_admin_id) {
            throw new Error("Worker owner_admin_id not found");
        }

        // 2) find admin auth user -> email
        const { data: adminAuth, error: adminAuthError } =
            await supabase.auth.admin.getUserById(worker.owner_admin_id);

        if (adminAuthError) {
            throw new Error(`Admin auth lookup failed: ${adminAuthError.message}`);
        }

        const adminEmail = adminAuth?.user?.email?.trim();
        if (!adminEmail) {
            throw new Error("Admin email not found");
        }

        // 3) format values
        const TZ = "America/Toronto";
        const fmt = (v?: string) =>
            v
                ? new Date(v).toLocaleString("en-US", {
                    timeZone: TZ,
                    year: "numeric",
                    month: "short",
                    day: "2-digit",
                    hour: "2-digit",
                    minute: "2-digit",
                })
                : "—";

        const isStart = event_type === "start";
        const subject = isStart ? "🟢 Shift started" : "🔴 Shift completed";

        const accent = isStart ? "#6CFF8D" : "#FF6B6B";
        const accentSoft = isStart
            ? "rgba(108,255,141,0.06)"
            : "rgba(255,107,107,0.08)";
        const badgeText = isStart ? "SHIFT STARTED" : "SHIFT COMPLETED";
        const titleText = isStart
            ? "Worker shift started"
            : "Worker shift completed";
        const subtitleText = isStart
            ? "A worker has started a shift in Workio."
            : "A worker has completed a shift in Workio.";

        const logoUrl =
            "https://mnycxmpofeajhjecsvhk.supabase.co/storage/v1/object/public/images/mahmadiyarov.png";

        const workerName = String(worker.name ?? "").trim();
        const workerDisplayName =
            workerName || worker_email.split("@")[0] || worker_email;

        const safeWorkerName = escapeHtml(workerDisplayName);
        const safeWorkerEmail = escapeHtml(worker_email);
        const safeAddress = escapeHtml(address_text ?? "—");
        const year = new Date().getFullYear();

        const hoursText =
            hours != null && hours !== ""
                ? `${Number(hours).toFixed(2)} h`
                : "—";

        const earnedText =
            earned != null && earned !== ""
                ? `$${Number(earned).toFixed(2)}`
                : "—";

        // invitation email palette
        const outerCardStyle = `
      max-width:560px;
      width:100%;
      background:#1E1C22;
      border-radius:22px;
      border:1px solid rgba(255,255,255,0.10);
      box-shadow:0 18px 50px rgba(0,0,0,0.55);
      border-collapse:separate;
      border-spacing:0;
    `;

        const sectionCardStyle = `
      background:rgba(255,255,255,0.04);
      border:1px solid rgba(255,255,255,0.08);
      border-radius:18px;
      border-collapse:separate;
      border-spacing:0;
    `;

        const labelStyle = `
      color:rgba(183,188,203,0.72);
      font-size:12px;
      line-height:16px;
      font-weight:700;
    `;

        const valueStyle = `
      color:#FFFFFF;
      font-size:14px;
      line-height:20px;
      font-weight:900;
    `;

        const html = `<!doctype html>
<html style="margin:0;padding:0;background:#0B0D12;">
  <body style="margin:0;padding:0;background:#0B0D12;font-family:Arial,Helvetica,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
           style="margin:0;padding:0;background:#0B0D12;mso-table-lspace:0pt;mso-table-rspace:0pt;">
      <tr>
        <td align="center" style="padding:24px 12px;background:#0B0D12;">
          <table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0"
                 style="${outerCardStyle}">
            <tr>
              <td style="padding:18px 18px 18px 18px;">

                <!-- TOP BAR -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td valign="middle">
                      <img src="${logoUrl}" height="46" alt="Workio"
                           style="display:block;object-fit:contain;" />
                    </td>
                    <td align="right" valign="middle">
                      <span style="
                        display:inline-block;
                        padding:7px 12px;
                        border-radius:999px;
                        background:${accentSoft};
                        border:1px solid ${accent};
                        color:${accent};
                        font-size:11px;
                        font-weight:900;
                        letter-spacing:0.4px;
                        white-space:nowrap;
                      ">
                        ${badgeText}
                      </span>
                    </td>
                  </tr>
                </table>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr><td height="14" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td style="height:1px;background:rgba(255,255,255,0.07);font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td height="18" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                </table>

                <!-- TITLE -->
                <div style="color:#FFFFFF;font-size:26px;font-weight:900;letter-spacing:-0.2px;line-height:32px;text-align:center;">
                  ${titleText}
                </div>

                <div style="height:8px;"></div>

                <div style="color:rgba(183,188,203,0.85);font-size:14px;line-height:20px;text-align:center;font-weight:700;">
                  ${subtitleText}
                </div>

                <div style="height:14px;"></div>

                <!-- CENTER DIVIDER -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td style="height:2px;background:transparent;"></td>
                    <td width="220" style="height:2px;background:${accent};font-size:0;line-height:0;">&nbsp;</td>
                    <td style="height:2px;background:transparent;"></td>
                  </tr>
                </table>

                <div style="height:18px;"></div>

                <!-- HERO CARD -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="${sectionCardStyle}">
                  <tr>
                    <td align="center" style="padding:18px 18px 18px 18px;">
                      <div style="color:rgba(183,188,203,0.72);font-size:12px;line-height:16px;font-weight:700;">
                        Worker
                      </div>

                      <div style="height:8px;"></div>

                      <div style="color:#FFFFFF;font-size:24px;line-height:30px;font-weight:900;">
                        ${safeWorkerName}
                      </div>

                      <div style="height:6px;"></div>

                      <div style="font-size:13px;line-height:20px;font-weight:700;word-break:break-word;">
                        <a href="mailto:${worker_email}" style="color:#6CFF8D;text-decoration:underline;">
                          ${safeWorkerEmail}
                        </a>
                      </div>

                      <div style="height:14px;"></div>

                      <div style="color:${accent};font-size:34px;line-height:38px;font-weight:900;letter-spacing:-0.4px;">
                        ${isStart ? "Shift On" : "Shift Off"}
                      </div>
                    </td>
                  </tr>
                </table>

                <div style="height:16px;"></div>

                <!-- INFO GRID 1 -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td width="50%" style="padding-right:6px;vertical-align:top;">
                      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                             style="${sectionCardStyle}">
                        <tr>
                          <td style="padding:14px 14px 14px 14px;">
                            <div style="${labelStyle}">
                              Started
                            </div>
                            <div style="height:6px;"></div>
                            <div style="${valueStyle}">
                              ${fmt(started_at)}
                            </div>
                          </td>
                        </tr>
                      </table>
                    </td>
                    <td width="50%" style="padding-left:6px;vertical-align:top;">
                      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                             style="${sectionCardStyle}">
                        <tr>
                          <td style="padding:14px 14px 14px 14px;">
                            <div style="${labelStyle}">
                              ${isStart ? "Status" : "Ended"}
                            </div>
                            <div style="height:6px;"></div>
                            <div style="${valueStyle}">
                              ${isStart ? "In progress" : fmt(ended_at)}
                            </div>
                          </td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                </table>

                <div style="height:12px;"></div>

                <!-- INFO GRID 2 -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td width="50%" style="padding-right:6px;vertical-align:top;">
                      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                             style="${sectionCardStyle}">
                        <tr>
                          <td style="padding:14px 14px 14px 14px;">
                            <div style="${labelStyle}">
                              Worked
                            </div>
                            <div style="height:6px;"></div>
                            <div style="color:#6CFF8D;font-size:18px;line-height:22px;font-weight:900;">
                              ${hoursText}
                            </div>
                          </td>
                        </tr>
                      </table>
                    </td>
                    <td width="50%" style="padding-left:6px;vertical-align:top;">
                      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                             style="${sectionCardStyle}">
                        <tr>
                          <td style="padding:14px 14px 14px 14px;">
                            <div style="${labelStyle}">
                              Earned
                            </div>
                            <div style="height:6px;"></div>
                            <div style="color:#6CFF8D;font-size:18px;line-height:22px;font-weight:900;">
                              ${earnedText}
                            </div>
                          </td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                </table>

                <div style="height:12px;"></div>

                <!-- ADDRESS -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="${sectionCardStyle}">
                  <tr>
                    <td style="padding:14px 14px 14px 14px;">
                      <div style="${labelStyle}">
                        Address
                      </div>
                      <div style="height:6px;"></div>
                      <div style="color:#FFFFFF;font-size:14px;line-height:20px;font-weight:800;word-break:break-word;">
                        ${safeAddress}
                      </div>
                    </td>
                  </tr>
                </table>

                <div style="height:16px;"></div>

                <!-- ADMIN NOTE -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="${sectionCardStyle}">
                  <tr>
                    <td style="padding:12px 14px 12px 14px;">
                      <div style="color:#EDEFF6;font-size:12.5px;line-height:18px;font-weight:800;">
                        Admin note
                      </div>
                      <div style="height:4px;"></div>
                      <div style="color:rgba(183,188,203,0.78);font-size:12px;line-height:18px;font-weight:700;">
                        ${
            isStart
                ? "The worker is currently on shift. You can review progress from the admin panel."
                : "The shift has been completed. Hours and earned amount are shown above for quick review."
        }
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
                      This is an automated shift notification for the admin panel.
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

        const res = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${RESEND_API_KEY}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                from: FROM_EMAIL,
                to: adminEmail,
                subject,
                html,
            }),
        });

        if (!res.ok) {
            throw new Error(await res.text());
        }

        return json({ success: true });
    } catch (e) {
        return json(
            { error: e instanceof Error ? e.message : String(e) },
            400,
        );
    }
});