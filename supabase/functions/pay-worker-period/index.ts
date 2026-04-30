import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function mustEnv(name: string) {
    const v = Deno.env.get(name);
    if (!v) throw new Error(`Missing env: ${name}`);
    return v;
}

function escapeHtml(s: string) {
    return (s ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
}

function paymentMethodLabel(v: string) {
    switch ((v ?? "").toLowerCase().trim()) {
        case "cash":
            return "Cash";
        case "card":
            return "Card";
        case "transfer":
            return "Transfer";
        case "check":
            return "Check";
        case "other":
            return "Other";
        default:
            return "Cash";
    }
}

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
    // ✅ CORS preflight
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    try {
        // 0) only POST
        if (req.method !== "POST") {
            return new Response("Method not allowed", { status: 405, headers: corsHeaders });
        }

        // 1) create client with service role
        const supabase = createClient(
            Deno.env.get("SUPABASE_URL")!,
            Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
        );

        // 2) auth header
        const authHeader = req.headers.get("Authorization");
        if (!authHeader) {
            return new Response(JSON.stringify({ error: "Missing Authorization" }), {
                status: 401,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        const token = authHeader.replace("Bearer ", "");

        // 3) verify user (admin)
        const { data: userData, error: userErr } = await supabase.auth.getUser(token);
        if (userErr || !userData?.user) {
            return new Response(JSON.stringify({ error: "Unauthorized", details: userErr?.message }), {
                status: 401,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        const adminEmail = userData.user.email;
        if (!adminEmail) {
            return new Response(JSON.stringify({ error: "Admin email not found" }), {
                status: 401,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        // 4) check admin_settings
        const { data: admin, error: adminErr } = await supabase
            .from("admin_settings")
            .select("id")
            .eq("admin_email", adminEmail)
            .maybeSingle();

        if (adminErr) {
            return new Response(JSON.stringify({ error: "Admin check error", details: adminErr.message }), {
                status: 500,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        if (!admin) {
            return new Response(JSON.stringify({ error: "Forbidden: not admin" }), {
                status: 403,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        // 5) body
        const body = await req.json();

        const {
            user_id,
            from,
            to,
            payment_method = "cash",
            payment_note = null,
        } = body;

        if (!user_id || !from || !to) {
            return new Response(JSON.stringify({ error: "user_id, from, to required" }), {
                status: 400,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        const normalizedMethod = String(payment_method ?? "cash")
            .toLowerCase()
            .trim();

        const allowedMethods = ["cash", "card", "transfer", "check", "other"];

        if (!allowedMethods.includes(normalizedMethod)) {
            return new Response(JSON.stringify({ error: "Invalid payment_method" }), {
                status: 400,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        const cleanPaymentNote =
            typeof payment_note === "string" && payment_note.trim() !== ""
                ? payment_note.trim()
                : null;

        // 🔎 get worker info
        const { data: worker, error: workerErr } = await supabase
            .from("workers")
            .select("email, name")
            .eq("auth_user_id", user_id)
            .single();

        if (workerErr || !worker?.email) {
            return new Response(JSON.stringify({ error: "Worker email not found" }), {
                status: 500,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        // 6) fetch unpaid shifts
        const { data: shifts, error: fetchErr } = await supabase
            .from("work_logs")
            .select("id, total_payment, total_hours, start_time, end_time")
            .eq("user_id", user_id)
            .not("end_time", "is", null)
            .is("paid_at", null)
            .gte("start_time", from)
            .lte("start_time", to);

        if (fetchErr) {
            return new Response(JSON.stringify({ error: "Fetch shifts error", details: fetchErr.message }), {
                status: 500,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        if (!shifts || shifts.length === 0) {
            return new Response(JSON.stringify({ paid_shifts: 0, total_amount: 0 }), {
                status: 200,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        // 7) totals
        const totalAmount = shifts.reduce((sum, s) => sum + Number(s.total_payment ?? 0), 0);
        const totalHours = shifts.reduce((sum, s) => sum + Number(s.total_hours ?? 0), 0);

        // 8) insert payments
        const { data: payment, error: paymentErr } = await supabase
            .from("payments")
            .insert({
                worker_auth_id: user_id,
                admin_email: adminEmail,
                period_from: from,
                period_to: to,
                total_hours: totalHours,
                total_amount: totalAmount,
                payment_method: normalizedMethod,
                payment_note: cleanPaymentNote,
            })
            .select()
            .single();

        if (paymentErr || !payment) {
            return new Response(JSON.stringify({ error: "Payment insert failed", details: paymentErr?.message }), {
                status: 500,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        // 9) insert payment_items
        const items = shifts.map((s) => ({
            payment_id: payment.id,
            work_log_id: s.id,
            amount: s.total_payment ?? 0,
        }));

        const { error: itemsErr } = await supabase.from("payment_items").insert(items);

        if (itemsErr) {
            return new Response(JSON.stringify({ error: "Payment items insert failed", details: itemsErr.message }), {
                status: 500,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        // 10) update work_logs paid_at
        const ids = shifts.map((s) => s.id);

        const { error: updateErr } = await supabase
            .from("work_logs")
            .update({ paid_at: new Date().toISOString() })
            .in("id", ids);

        if (updateErr) {
            return new Response(JSON.stringify({ error: "Update work_logs failed", details: updateErr.message }), {
                status: 500,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }

        const formatDate = (d: string) =>
            new Date(d).toLocaleDateString("en-US", {
                month: "short",
                day: "numeric",
                year: "numeric",
            });

        const periodText = `${formatDate(from)} → ${formatDate(to)}`;

        const paymentMethodText = paymentMethodLabel(normalizedMethod);
        const paymentNoteText = cleanPaymentNote ? escapeHtml(cleanPaymentNote) : "";

        const html = `<!doctype html>
<html style="margin:0;padding:0;background:#0B0D12;">
  <body style="margin:0;padding:0;background:#0B0D12;font-family:Arial,Helvetica,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
           style="margin:0;padding:0;background:#0B0D12;mso-table-lspace:0pt;mso-table-rspace:0pt;">
      <tr>
        <td align="center" style="padding:24px 12px;background:#0B0D12;">

          <table role="presentation" width="620" cellpadding="0" cellspacing="0" border="0"
                 style="max-width:620px;width:100%;
                        background:#1E1C22;
                        border:1px solid rgba(255,255,255,0.08);
                        border-radius:28px;
                        box-shadow:0 18px 44px rgba(0,0,0,0.55);
                        border-collapse:separate;border-spacing:0;">

            <tr>
              <td style="padding:18px 18px 18px 18px;">

                <!-- HEADER -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td align="left" valign="middle">
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
                            ✅ PAID
                          </td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                </table>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr><td height="14" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td style="height:1px;background:rgba(255,255,255,0.06);font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td height="18" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                </table>

                <!-- TITLE -->
                <div style="text-align:center;">
                  <div style="color:#EDEFF6;
                              font-size:14px;
                              line-height:18px;
                              font-weight:900;
                              letter-spacing:2px;
                              opacity:0.92;">
                    PAYMENT UPDATE
                  </div>

                  <div style="height:12px;"></div>

                  <div style="color:#2CFF8F;
                              font-size:54px;
                              line-height:58px;
                              font-weight:900;
                              letter-spacing:-0.7px;
                              text-shadow:0 0 24px rgba(44,255,143,0.28);">
                    $${totalAmount.toFixed(2)}
                  </div>

                  <div style="height:10px;"></div>

                  <div style="color:rgba(183,188,203,0.88);
                              font-size:14px;
                              line-height:21px;
                              font-weight:700;">
                    Your salary for the period below has been marked as paid.
                  </div>
                </div>

                <div style="height:16px;"></div>

                <!-- CENTER ACCENT -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td style="height:2px;background:transparent;"></td>
                    <td width="220"
                        style="height:2px;background:linear-gradient(90deg,rgba(52,211,153,0),rgba(52,211,153,0.72),rgba(56,189,248,0.45),rgba(52,211,153,0));font-size:0;line-height:0;">
                      &nbsp;
                    </td>
                    <td style="height:2px;background:transparent;"></td>
                  </tr>
                </table>

                <div style="height:18px;"></div>

                <!-- SUMMARY NOTE -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="background:rgba(255,255,255,0.04);
                              border:1px solid rgba(255,255,255,0.08);
                              border-radius:20px;
                              border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td style="padding:14px 16px 14px 16px;">
                      <div style="color:#F3F5F8;font-size:15px;line-height:20px;font-weight:900;">
                        Payment confirmed
                      </div>

                      <div style="height:6px;"></div>

                      <div style="color:rgba(183,188,203,0.84);font-size:13px;line-height:20px;font-weight:700;">
                        This payment has been recorded in your history and marked as completed in Workio.
                      </div>
                    </td>
                  </tr>
                </table>

                <div style="height:16px;"></div>

                <!-- DETAILS CARD -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="background:#101522;
                              border:1px solid rgba(255,255,255,0.08);
                              border-radius:22px;
                              border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td style="padding:10px 14px 10px 14px;">

                      <!-- NAME -->
                      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td width="42" valign="middle" style="padding:10px 0;">
                            <table role="presentation" width="32" cellpadding="0" cellspacing="0" border="0"
                                   style="background:rgba(255,255,255,0.05);
                                          border:1px solid rgba(255,255,255,0.08);
                                          border-radius:10px;">
                              <tr><td align="center" valign="middle" style="height:32px;font-size:14px;">👤</td></tr>
                            </table>
                          </td>
                          <td width="118" valign="middle"
                              style="padding:10px 0;color:rgba(183,188,203,0.88);font-size:12px;font-weight:800;letter-spacing:0.5px;">
                            Name
                          </td>
                          <td valign="middle"
                              style="padding:10px 0;color:#FFFFFF;font-size:15px;font-weight:900;word-break:break-word;">
                            ${escapeHtml(worker.name ?? "")}
                          </td>
                        </tr>
                      </table>

                      <div style="height:1px;background:rgba(255,255,255,0.06);"></div>

                      <!-- EMAIL -->
                      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td width="42" valign="middle" style="padding:10px 0;">
                            <table role="presentation" width="32" cellpadding="0" cellspacing="0" border="0"
                                   style="background:rgba(56,189,248,0.08);
                                          border:1px solid rgba(56,189,248,0.14);
                                          border-radius:10px;">
                              <tr><td align="center" valign="middle" style="height:32px;font-size:14px;">✉️</td></tr>
                            </table>
                          </td>
                          <td width="118" valign="middle"
                              style="padding:10px 0;color:rgba(183,188,203,0.88);font-size:12px;font-weight:800;letter-spacing:0.5px;">
                            Email
                          </td>
                          <td valign="middle" style="padding:10px 0;word-break:break-word;">
                            <span style="color:#38BDF8;font-size:14px;font-weight:900;">
                              ${escapeHtml(worker.email ?? "")}
                            </span>
                          </td>
                        </tr>
                      </table>

                      <div style="height:1px;background:rgba(255,255,255,0.06);"></div>

                      <!-- PERIOD -->
                      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td width="42" valign="middle" style="padding:10px 0;">
                            <table role="presentation" width="32" cellpadding="0" cellspacing="0" border="0"
                                   style="background:rgba(255,255,255,0.05);
                                          border:1px solid rgba(255,255,255,0.08);
                                          border-radius:10px;">
                              <tr><td align="center" valign="middle" style="height:32px;font-size:14px;">📅</td></tr>
                            </table>
                          </td>
                          <td width="118" valign="middle"
                              style="padding:10px 0;color:rgba(183,188,203,0.88);font-size:12px;font-weight:800;letter-spacing:0.5px;">
                            Period
                          </td>
                          <td valign="middle"
                              style="padding:10px 0;color:#FFFFFF;font-size:14px;font-weight:900;word-break:break-word;">
                            ${escapeHtml(periodText)}
                          </td>
                        </tr>
                      </table>

                      <div style="height:1px;background:rgba(255,255,255,0.06);"></div>
                      
                      <!-- PAYMENT METHOD -->
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
  <tr>
    <td width="42" valign="middle" style="padding:10px 0;">
      <table role="presentation" width="32" cellpadding="0" cellspacing="0" border="0"
             style="background:rgba(52,211,153,0.08);
                    border:1px solid rgba(52,211,153,0.14);
                    border-radius:10px;">
        <tr><td align="center" valign="middle" style="height:32px;font-size:14px;">💳</td></tr>
      </table>
    </td>
    <td width="118" valign="middle"
        style="padding:10px 0;color:rgba(183,188,203,0.88);font-size:12px;font-weight:800;letter-spacing:0.5px;">
      Method
    </td>
    <td valign="middle"
        style="padding:10px 0;color:#FFFFFF;font-size:14px;font-weight:900;word-break:break-word;">
      ${escapeHtml(paymentMethodText)}
    </td>
  </tr>
</table>

<div style="height:1px;background:rgba(255,255,255,0.06);"></div>

                      <!-- TOTAL HOURS -->
                      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td width="42" valign="middle" style="padding:10px 0;">
                            <table role="presentation" width="32" cellpadding="0" cellspacing="0" border="0"
                                   style="background:rgba(255,255,255,0.05);
                                          border:1px solid rgba(255,255,255,0.08);
                                          border-radius:10px;">
                              <tr><td align="center" valign="middle" style="height:32px;font-size:14px;">⏱️</td></tr>
                            </table>
                          </td>
                          <td width="118" valign="middle"
                              style="padding:10px 0;color:rgba(183,188,203,0.88);font-size:12px;font-weight:800;letter-spacing:0.5px;">
                            Total hours
                          </td>
                          <td valign="middle"
                              style="padding:10px 0;color:#FFFFFF;font-size:14px;font-weight:900;">
                            ${totalHours.toFixed(2)} h
                          </td>
                        </tr>
                      </table>

                      <div style="height:1px;background:rgba(255,255,255,0.06);"></div>

                      <!-- PAID SHIFTS -->
                      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td width="42" valign="middle" style="padding:10px 0;">
                            <table role="presentation" width="32" cellpadding="0" cellspacing="0" border="0"
                                   style="background:rgba(52,211,153,0.08);
                                          border:1px solid rgba(52,211,153,0.14);
                                          border-radius:10px;">
                              <tr><td align="center" valign="middle" style="height:32px;font-size:14px;">✅</td></tr>
                            </table>
                          </td>
                          <td width="118" valign="middle"
                              style="padding:10px 0;color:rgba(183,188,203,0.88);font-size:12px;font-weight:800;letter-spacing:0.5px;">
                            Paid shifts
                          </td>
                          <td valign="middle"
                              style="padding:10px 0;color:#FFFFFF;font-size:14px;font-weight:900;">
                            ${shifts.length}
                          </td>
                        </tr>
                      </table>

                    </td>
                  </tr>
                </table>

                <div style="height:14px;"></div>

                <!-- STATUS / AMOUNT CARD -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="background:rgba(255,255,255,0.04);
                              border:1px solid rgba(255,255,255,0.08);
                              border-radius:18px;
                              border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td style="padding:12px 14px;">
                      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td align="left" valign="middle"
                              style="color:rgba(183,188,203,0.92);font-size:12px;line-height:18px;font-weight:700;">
                            Status:
                            <span style="color:#34D399;font-weight:900;">PAID</span>
                          </td>

                          <td align="center" valign="middle"
                              style="color:rgba(255,255,255,0.18);font-size:12px;line-height:18px;">
                            •
                          </td>

                          <td align="right" valign="middle"
                              style="color:rgba(183,188,203,0.92);font-size:12px;line-height:18px;font-weight:700;">
                            Amount:
                            <span style="color:#2CFF8F;font-weight:900;">$${totalAmount.toFixed(2)}</span>
                          </td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                </table>

                <div style="height:16px;"></div>

                <!-- NOTE -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="background:rgba(56,189,248,0.06);
                              border:1px solid rgba(56,189,248,0.16);
                              border-radius:18px;
                              border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td style="padding:14px 16px 14px 16px;">
                      <div style="color:#F3F5F8;font-size:13px;line-height:18px;font-weight:900;">
  Payment note
</div>
<div style="height:6px;"></div>
<div style="color:rgba(183,188,203,0.84);font-size:12.5px;line-height:19px;font-weight:700;">
  ${paymentNoteText || "If you have any questions about this payment, please contact your administrator."}
</div>
                    </td>
                  </tr>
                </table>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr><td height="16" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td style="height:1px;background:rgba(255,255,255,0.06);font-size:0;line-height:0;">&nbsp;</td></tr>
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
                      This message was sent automatically. Please do not reply.
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
        const FROM_EMAIL = mustEnv("FROM_EMAIL"); // onboarding@resend.dev или noreply@domain.com
        const RESEND_API_KEY = mustEnv("RESEND_API_KEY_ACCESS");

        console.log("FROM:", FROM_EMAIL);
        console.log("TO:", worker.email);

        // 📧 send payment email via Resend (как было)
        const resendResponse = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${RESEND_API_KEY}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                from: FROM_EMAIL,
                to: [worker.email],
                subject: "Salary paid 💸",
                html,
            }),
        });

        const resendText = await resendResponse.text();

        console.log("RESEND STATUS:", resendResponse.status);
        console.log("RESEND BODY:", resendText);

        let emailSent = true;

        if (!resendResponse.ok) {
            console.error("EMAIL FAILED:", resendText);
            emailSent = false;
        }

        return new Response(
            JSON.stringify({
                ok: true,
                email_sent: emailSent,
                paid_shifts: ids.length,
                total_amount: totalAmount,
            }),
            { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );

    } catch (e) {
        console.error("pay-worker-period error:", e);
        return new Response(JSON.stringify({ error: String(e) }), {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
    }
});