// supabase/functions/notify-worker-access-change/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ============ helpers ============
function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function mustEnv(name: string) {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}

type AccessMode = "active" | "readonly" | "suspended";

const MODE_META: Record<
    AccessMode,
    {
      color: string;
      softBg: string;
      softBorder: string;
      badge: string;
      title: string;
      lead: string;
      text: string;
      noteTitle: string;
      noteText: string;
    }
> = {
  active: {
    color: "#6CFF8D",
    softBg: "rgba(108,255,141,0.07)",
    softBorder: "rgba(108,255,141,0.16)",
    badge: "ACTIVE",
    title: "Access restored",
    lead: "Good news — your access is fully active again.",
    text: "You can now sign in and use Workio normally without restrictions.",
    noteTitle: "Everything is back to normal",
    noteText: "Your account is active and ready to use.",
  },
  readonly: {
    color: "#F59E0B",
    softBg: "rgba(245,158,11,0.08)",
    softBorder: "rgba(245,158,11,0.18)",
    badge: "VIEW ONLY",
    title: "View-only access",
    lead: "Your access level has been updated.",
    text: "You can still open Workio and view information, but editing and changes are now disabled.",
    noteTitle: "Limited access",
    noteText: "You still have visibility, but actions are restricted in this mode.",
  },
  suspended: {
    color: "#FB7185",
    softBg: "rgba(251,113,133,0.08)",
    softBorder: "rgba(251,113,133,0.18)",
    badge: "SUSPENDED",
    title: "Access update",
    lead: "Your access is currently suspended.",
    text: "You won’t be able to use Workio until your administrator restores your access.",
    noteTitle: "Action may be required",
    noteText: "If you believe this change is incorrect, please contact your administrator as soon as possible.",
  },
};

function subjectByMode(mode: AccessMode) {
  switch (mode) {
    case "active":
      return "Workio • Access restored";
    case "readonly":
      return "Workio • View-only access";
    case "suspended":
      return "Workio • Your access status has changed";
  }
}

/**
 * Простая email-safe карточка (таблицы).
 * logoUrl можно оставить пустым, если пока нет.
 */
function buildAccessEmailHtml(params: {
  workerName: string;
  workerEmail: string;
  mode: AccessMode;
  companyName?: string;
  logoUrl?: string;
}) {
  const { workerName, workerEmail, mode } = params;
  const companyName = params.companyName ?? "Workio";
  const logoUrl = params.logoUrl ?? "";
  const meta = MODE_META[mode];
  const year = new Date().getFullYear();

  const logoBlock = logoUrl
      ? `<img 
         src="${logoUrl}" 
         height="46"
         style="display:block;object-fit:contain;"
         alt="${escapeHtml(companyName)}" 
       />`
      : `<div style="font-weight:900;font-size:18px;color:#ffffff;">
         ${escapeHtml(companyName)}
       </div>`;

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
                      ${logoBlock}
                    </td>
                    <td align="right" valign="middle"
                        style="color:#A8B0C2;font-size:12px;font-weight:800;white-space:nowrap;">
                      Account update
                    </td>
                  </tr>
                </table>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr><td height="14" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td style="height:1px;background:rgba(255,255,255,0.07);font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td height="16" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                </table>

                <!-- BADGE -->
                <table role="presentation" align="center" cellpadding="0" cellspacing="0" border="0" style="margin:0 auto;">
                  <tr>
                    <td align="center"
                        style="padding:7px 14px;border-radius:999px;
                               background:${meta.softBg};
                               border:1px solid ${meta.softBorder};
                               color:${meta.color};
                               font-size:12px;font-weight:900;letter-spacing:0.7px;">
                      ${meta.badge}
                    </td>
                  </tr>
                </table>

                <div style="height:16px;"></div>

                <!-- TITLE -->
                <div style="color:#FFFFFF;font-size:30px;font-weight:900;letter-spacing:-0.25px;line-height:34px;text-align:center;">
                  ${escapeHtml(meta.title)}
                </div>

                <div style="height:8px;"></div>

                <div style="color:rgba(183,188,203,0.86);font-size:14px;line-height:20px;text-align:center;font-weight:700;">
                  ${escapeHtml(meta.lead)}
                </div>

                <div style="height:14px;"></div>

                <!-- CENTER ACCENT -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td style="height:2px;background:transparent;"></td>
                    <td width="220" style="height:2px;background:${meta.color};font-size:0;line-height:0;">&nbsp;</td>
                    <td style="height:2px;background:transparent;"></td>
                  </tr>
                </table>

                <div style="height:18px;"></div>

                <!-- GREETING -->
                <div style="color:#FFFFFF;font-size:18px;font-weight:900;line-height:24px;">
                  Hello ${escapeHtml(workerName || "Worker")},
                </div>

                <div style="height:10px;"></div>

                <div style="color:rgba(183,188,203,0.84);font-size:14px;line-height:22px;font-weight:700;">
                  ${escapeHtml(meta.text)}
                </div>

                <div style="height:18px;"></div>

                <!-- MAIN STATUS CARD -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="background:rgba(255,255,255,0.04);
                              border:1px solid rgba(255,255,255,0.08);
                              border-radius:18px;
                              border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td style="padding:0;">
                      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td style="padding:14px 16px 10px 16px;">
                            <div style="color:rgba(183,188,203,0.72);font-size:12px;line-height:16px;font-weight:700;">
                              Account
                            </div>
                            <div style="height:6px;"></div>
                            <div style="color:#EDEFF6;font-size:14px;line-height:20px;font-weight:800;word-break:break-word;">
                              ${escapeHtml(workerEmail)}
                            </div>
                          </td>
                        </tr>

                        <tr>
                          <td style="padding:0 16px 0 16px;">
                            <div style="height:1px;background:rgba(255,255,255,0.06);"></div>
                          </td>
                        </tr>

                        <tr>
                          <td style="padding:12px 16px 14px 16px;">
                            <div style="color:rgba(183,188,203,0.72);font-size:12px;line-height:16px;font-weight:700;">
                              Current status
                            </div>
                            <div style="height:8px;"></div>
                            <span style="display:inline-block;padding:7px 12px;border-radius:999px;
                                         background:${meta.softBg};
                                         border:1px solid ${meta.softBorder};
                                         color:${meta.color};
                                         font-size:12px;font-weight:900;letter-spacing:0.6px;">
                              ${meta.badge}
                            </span>
                          </td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                </table>

                <div style="height:14px;"></div>

                <!-- NOTE CARD -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="background:${meta.softBg};
                              border:1px solid ${meta.softBorder};
                              border-radius:18px;
                              border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td style="padding:14px 16px 14px 16px;">
                      <div style="color:#EDEFF6;font-size:13px;line-height:18px;font-weight:900;">
                        ${escapeHtml(meta.noteTitle)}
                      </div>
                      <div style="height:6px;"></div>
                      <div style="color:rgba(183,188,203,0.82);font-size:12.5px;line-height:19px;font-weight:700;">
                        ${escapeHtml(meta.noteText)}
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
                      ${escapeHtml(companyName)} • ${year}
                    </td>
                  </tr>
                  <tr>
                    <td height="8" style="font-size:0;line-height:0;">&nbsp;</td>
                  </tr>
                  <tr>
                    <td align="center"
                        style="color:rgba(183,188,203,0.48);font-size:11px;line-height:17px;font-weight:700;">
                      If you believe this is a mistake, please contact your administrator.<br/>
                      This is an automated message. Please do not reply.
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

function escapeHtml(s: string) {
  return (s ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

// ============ main ============
serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    const RESEND_API_KEY = mustEnv("RESEND_API_KEY_ACCESS");
    const FROM_EMAIL = mustEnv("FROM_EMAIL"); // onboarding@resend.dev или noreply@domain.com

    // supabase client (для чтения worker)
    const supabaseUrl = mustEnv("SUPABASE_URL");
    const supabaseServiceKey = mustEnv("SUPABASE_SERVICE_ROLE_KEY");

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const body = await req.json();
    const worker_id = body?.worker_id as string | undefined;
    const new_mode = body?.new_mode as AccessMode | undefined;

    if (!worker_id || !new_mode) {
      return json({ error: "worker_id and new_mode required" }, 400);
    }
    if (!["active", "readonly", "suspended"].includes(new_mode)) {
      return json({ error: "Invalid new_mode" }, 400);
    }

    // 1) читаем воркера из БД
    const { data: worker, error: wErr } = await supabase
      .from("workers")
      .select("id, name, email, access_mode")
      .eq("id", worker_id)
      .maybeSingle();

    if (wErr) return json({ error: `DB error: ${wErr.message}` }, 500);
    if (!worker) return json({ error: "Worker not found" }, 404);
    // const email = (worker.email ?? "").toString();
    const email = (worker.email ?? "").toString().trim();
    if (!email) return json({ error: "Worker email is empty" }, 400);

    // 2) HTML
    const html = buildAccessEmailHtml({
      workerName: (worker.name ?? "Worker").toString(),
      workerEmail: email,
      mode: new_mode,
      companyName: "Workio",
      logoUrl: "https://mnycxmpofeajhjecsvhk.supabase.co/storage/v1/object/public/images/mahmadiyarov.png",
    });
   
    const subject = subjectByMode(new_mode);

    // 3) отправка через Resend (обычный fetch)
    const resendRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: [email],
        subject,
        html,
      }),
    });

    const resendJson = await resendRes.json();
    if (!resendRes.ok) {
      return json(
        { error: "Resend error", details: resendJson },
        500,
      );
    }

    // 4) можно залогировать в таблицу (не обязательно)
    // await supabase.from("worker_notifications").insert({...})

    return json({ success: true, resend: resendJson });
  } catch (e) {
    return json({ error: String(e?.message ?? e) }, 500);
  }
});
