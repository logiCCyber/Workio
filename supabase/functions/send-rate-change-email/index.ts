import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { Resend } from "npm:resend";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function mustEnv(name: string) {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function escapeHtml(s: string) {
  return (s ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
}

serve(async (req) => {
  try {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    const RESEND_API_KEY = mustEnv("RESEND_API_KEY_ACCESS");
    const FROM_EMAIL = mustEnv("FROM_EMAIL"); // example: Workio <noreply@workio.ca>

    const body = await req.json().catch(() => ({}));

    const workerEmail = (body?.worker_email ?? "").toString().trim();
    const workerName = (body?.worker_name ?? "there").toString();
    const oldRate = Number(body?.old_rate ?? 0);
    const newRate = Number(body?.new_rate ?? 0);

    if (!workerEmail) return json({ error: "worker_email is required" }, 400);

    const resend = new Resend(RESEND_API_KEY);

    const html = `<!doctype html>
<html style="margin:0;padding:0;background:#0B0D12;">
  <body style="margin:0;padding:0;background:#0B0D12;font-family:Arial,Helvetica,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
           style="margin:0;padding:0;background:#0B0D12;mso-table-lspace:0pt;mso-table-rspace:0pt;">
      <tr>
        <td align="center" style="padding:26px 12px;background:#0B0D12;">

          <table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0"
                 style="max-width:560px;width:100%;
                        background:#1E1C22;
                        border:1px solid rgba(255,255,255,0.10);
                        border-radius:24px;
                        box-shadow:0 18px 50px rgba(0,0,0,0.55);
                        border-collapse:separate;border-spacing:0;">

            <tr>
              <td style="padding:18px 18px 18px 18px;">

                <!-- HEADER -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td valign="middle">
                      <img
                        src="https://mnycxmpofeajhjecsvhk.supabase.co/storage/v1/object/public/images/mahmadiyarov.png"
                        alt="Workio"
                        height="46"
                        style="display:block;object-fit:contain;"
                      />
                    </td>

                    <td align="right" valign="middle">
                      <table role="presentation" cellpadding="0" cellspacing="0" border="0"
                             style="border-collapse:separate;border-spacing:0;">
                        <tr>
                          <td style="padding:7px 12px;
                                     border-radius:999px;
                                     background:rgba(52,211,153,0.10);
                                     border:1px solid rgba(52,211,153,0.22);
                                     color:#34D399;
                                     font-size:12px;
                                     font-weight:900;
                                     letter-spacing:0.6px;
                                     white-space:nowrap;">
                            ✅ UPDATED
                          </td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                </table>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr><td height="14" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td style="height:1px;background:rgba(255,255,255,0.07);font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td height="18" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                </table>

                <!-- TITLE -->
                <div style="text-align:center;">
                  <div style="color:#F9FAFB;
                              font-size:28px;
                              line-height:34px;
                              font-weight:900;
                              letter-spacing:-0.25px;">
                    Hourly rate updated
                  </div>

                  <div style="height:8px;"></div>

                  <div style="color:rgba(226,232,240,0.88);
                              font-size:14px;
                              line-height:21px;
                              font-weight:700;">
                    Your hourly rate has been updated in Workio.
                  </div>
                </div>

                <div style="height:16px;"></div>

                <!-- center accent -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td style="height:2px;background:transparent;"></td>
                    <td width="220"
                        style="height:2px;background:linear-gradient(90deg,rgba(52,211,153,0.75),rgba(56,189,248,0.75));font-size:0;line-height:0;">
                      &nbsp;
                    </td>
                    <td style="height:2px;background:transparent;"></td>
                  </tr>
                </table>

                <div style="height:18px;"></div>

                <!-- worker info -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="background:rgba(255,255,255,0.04);
                              border:1px solid rgba(255,255,255,0.08);
                              border-radius:18px;
                              border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td style="padding:14px 16px 14px 16px;">
                      <div style="color:#F3F5F8;font-size:16px;line-height:22px;font-weight:900;">
                        Hello ${escapeHtml(workerName || "there")}
                      </div>

                      <div style="height:6px;"></div>

                      <div style="color:rgba(183,188,203,0.84);font-size:13px;line-height:20px;font-weight:700;">
                        Account:
                        <span style="color:#8FC7FF;font-weight:800;">${escapeHtml(workerEmail || "")}</span>
                      </div>

                      <div style="height:8px;"></div>

                      <div style="color:rgba(183,188,203,0.82);font-size:13px;line-height:20px;font-weight:700;">
                        This update applies to <span style="color:#EDEFF6;font-weight:900;">future shifts only</span>.
                        Past shifts are not affected.
                      </div>
                    </td>
                  </tr>
                </table>

                <div style="height:16px;"></div>

                <!-- main comparison card -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="background:#0B1020;
                              border:1px solid rgba(255,255,255,0.08);
                              border-radius:20px;
                              border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td style="padding:18px 16px 18px 16px;">

                      <div style="text-align:center;color:#EDEFF6;font-size:13px;line-height:18px;font-weight:900;letter-spacing:0.9px;">
                        RATE CHANGE SUMMARY
                      </div>

                      <div style="height:14px;"></div>

                      <div style="text-align:center;color:#22C55E;font-size:13px;line-height:18px;font-weight:900;letter-spacing:0.5px;">
                        ● RATE CHANGED
                      </div>

                      <div style="height:16px;"></div>

                      <div style="text-align:center;color:rgba(183,188,203,0.88);font-size:13px;line-height:20px;font-weight:700;">
                        This change affects <span style="color:#FFFFFF;font-weight:900;">future shifts only</span>. Past shifts are not affected.
                      </div>

                      <div style="height:18px;"></div>

                      <!-- comparison -->
                      <table role="presentation" align="center" cellpadding="0" cellspacing="0" border="0" style="margin:0 auto;">
                        <tr>
                          <!-- OLD -->
                          <td valign="middle"
                              style="width:180px;
                                     background:linear-gradient(180deg,#3A0D16 0%, #2A0911 100%);
                                     border:1px solid rgba(239,68,68,0.55);
                                     border-right:none;
                                     border-radius:18px 0 0 18px;
                                     padding:16px 14px;
                                     text-align:center;">
                            <div style="font-size:12px;line-height:16px;color:#FECACA;font-weight:900;letter-spacing:0.8px;">
                              OLD RATE
                            </div>
                            <div style="height:8px;"></div>
                            <div style="font-size:26px;line-height:30px;font-weight:900;color:#FF5A67;">
                              $${oldRate.toFixed(2)}
                            </div>
                          </td>

                          <!-- CENTER TRIANGLE -->
                          <td valign="middle"
                              style="width:46px;
                                     background:linear-gradient(90deg,rgba(239,68,68,0.14),rgba(34,197,94,0.14));
                                     border-top:1px solid rgba(255,255,255,0.10);
                                     border-bottom:1px solid rgba(255,255,255,0.10);
                                     text-align:center;">
                            <div style="font-size:22px;line-height:22px;color:#E5E7EB;font-weight:900;">
                              ▶
                            </div>
                          </td>

                          <!-- NEW -->
                          <td valign="middle"
                              style="width:180px;
                                     background:linear-gradient(180deg,#06291B 0%, #041F14 100%);
                                     border:1px solid rgba(34,197,94,0.55);
                                     border-left:none;
                                     border-radius:0 18px 18px 0;
                                     padding:16px 14px;
                                     text-align:center;">
                            <div style="font-size:12px;line-height:16px;color:#BBF7D0;font-weight:900;letter-spacing:0.8px;">
                              NEW RATE
                            </div>
                            <div style="height:8px;"></div>
                            <div style="font-size:26px;line-height:30px;font-weight:900;color:#2EEB7F;">
                              $${newRate.toFixed(2)}
                            </div>
                          </td>
                        </tr>
                      </table>

                      <div style="height:16px;"></div>

                      <!-- delta badge -->
                      <table role="presentation" align="center" cellpadding="0" cellspacing="0" border="0" style="margin:0 auto;">
                        <tr>
                          <td style="padding:9px 16px;
                                     border-radius:999px;
                                     background:${newRate > oldRate ? "rgba(34,197,94,0.12)" : newRate < oldRate ? "rgba(239,68,68,0.12)" : "rgba(148,163,184,0.12)"};
                                     border:1px solid ${newRate > oldRate ? "rgba(34,197,94,0.28)" : newRate < oldRate ? "rgba(239,68,68,0.28)" : "rgba(148,163,184,0.24)"};
                                     color:${newRate > oldRate ? "#34D399" : newRate < oldRate ? "#FB7185" : "#CBD5E1"};
                                     font-size:12px;
                                     line-height:16px;
                                     font-weight:900;
                                     letter-spacing:0.5px;">
                            ${newRate > oldRate
        ? `INCREASE: +$${(newRate - oldRate).toFixed(2)} / HOUR`
        : newRate < oldRate
            ? `DECREASE: -$${(oldRate - newRate).toFixed(2)} / HOUR`
            : `NO CHANGE IN RATE`}
                          </td>
                        </tr>
                      </table>

                      <div style="height:14px;"></div>

                      <div style="text-align:center;color:rgba(183,188,203,0.82);font-size:12px;line-height:18px;font-weight:700;">
                        Effective starting from the next shift.
                      </div>
                    </td>
                  </tr>
                </table>

                <div style="height:16px;"></div>

                <!-- note card -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="background:rgba(56,189,248,0.06);
                              border:1px solid rgba(56,189,248,0.16);
                              border-radius:18px;
                              border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td style="padding:14px 16px 14px 16px;">
                      <div style="color:#F3F5F8;font-size:13px;line-height:18px;font-weight:900;">
                        Important
                      </div>
                      <div style="height:6px;"></div>
                      <div style="color:rgba(183,188,203,0.84);font-size:12.5px;line-height:19px;font-weight:700;">
                        If you have any questions about this update, please contact your administrator.
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
                      Workio • ${new Date().getFullYear()}
                    </td>
                  </tr>
                  <tr>
                    <td height="8" style="font-size:0;line-height:0;">&nbsp;</td>
                  </tr>
                  <tr>
                    <td align="center"
                        style="color:rgba(183,188,203,0.48);font-size:11px;line-height:17px;font-weight:700;">
                      Automated message. Please do not reply.
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
</html>
`;

    const result = await resend.emails.send({
      from: FROM_EMAIL,
      to: [workerEmail],
      subject: "Your hourly rate was updated",
      html,
    });

    return json({ success: true, result });
  } catch (e) {
    return json({ error: String((e as any)?.message ?? e) }, 500);
  }
});