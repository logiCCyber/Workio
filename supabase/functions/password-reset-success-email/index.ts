// supabase/functions/notify-password-updated/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Resend } from "npm:resend";

function mustEnv(name: string) {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
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

/** Адаптивная карточка в твоём стиле */
function buildPasswordUpdatedHtml(params: {
  name: string;
  email: string;
  logoUrl: string;
  appName?: string;
}) {
  const appName = params.appName ?? "WorkTime";
  const name = escapeHtml(params.name || "there");
  const email = escapeHtml(params.email || "");
  const logoUrl = params.logoUrl;

  return `
  <div style="margin:0;padding:0;background:#0B0D12;">
    <table width="100%" cellpadding="0" cellspacing="0" style="background:#0B0D12;padding:28px 0;">
      <tr>
        <td align="center" style="padding:0 14px;">
          <table width="520" cellpadding="0" cellspacing="0" style="
            width:520px; max-width:520px;
            background:#11131A;
            border-radius:22px;
            border:1px solid rgba(255,255,255,0.08);
            box-shadow:0 18px 44px rgba(0,0,0,0.55);
            font-family:Arial,Helvetica,sans-serif;
            overflow:hidden;
          ">
            <!-- top glow line -->
            <tr>
              <td style="height:6px;background:linear-gradient(90deg,#34D399,#38BDF8);"></td>
            </tr>

            <tr>
              <td style="padding:20px 20px 8px 20px;">
                <table width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td align="left" valign="middle">
                      <img src="${logoUrl}" height="44" style="display:block;max-width:180px;" alt="${escapeHtml(appName)}"/>
                    </td>
                    <td align="right" valign="middle">
                      <span style="
                        display:inline-block;
                        padding:7px 12px;
                        border-radius:999px;
                        background:rgba(52,211,153,0.12);
                        border:1px solid rgba(52,211,153,0.22);
                        color:#34D399;
                        font-size:12px;
                        font-weight:900;
                        letter-spacing:0.6px;
                        white-space:nowrap;
                      ">SECURITY</span>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>

            <tr>
              <td style="padding:14px 20px 0 20px;">
                <div style="
                  color:#EDEFF6;
                  font-size:18px;
                  font-weight:900;
                  letter-spacing:0.4px;
                ">Password updated</div>

                <div style="margin-top:10px;color:rgba(183,188,203,0.92);font-size:14px;line-height:1.6;">
                  Hello <b style="color:#FFFFFF;">${name}</b>,<br/>
                  Your password was successfully updated for this account:
                  <span style="color:#38BDF8;font-weight:800;">${email}</span>
                </div>
              </td>
            </tr>

            <tr>
              <td style="padding:14px 20px 0 20px;">
                <table width="100%" cellpadding="0" cellspacing="0" style="
                  background:rgba(52,211,153,0.08);
                  border:1px solid rgba(52,211,153,0.16);
                  border-radius:18px;
                ">
                  <tr>
                    <td style="padding:14px 14px;">
                      <table width="100%" cellpadding="0" cellspacing="0">
                        <tr>
                          <td valign="middle" style="width:28px;">
                            <span style="display:inline-block;font-size:18px;">✅</span>
                          </td>
                          <td valign="middle" style="color:#EDEFF6;font-size:14px;font-weight:900;">
                            Your account is secure
                          </td>
                        </tr>
                      </table>
                      <div style="margin-top:6px;color:rgba(183,188,203,0.92);font-size:13px;line-height:1.5;">
                        If this wasn’t you, contact your administrator immediately.
                      </div>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>

            <tr>
              <td style="padding:18px 20px 0 20px;">
                <div style="height:1px;background:rgba(255,255,255,0.06);"></div>
              </td>
            </tr>

            <tr>
              <td style="padding:14px 20px 18px 20px;color:rgba(139,144,160,0.95);font-size:12px;line-height:1.5;">
                © ${new Date().getFullYear()} ${escapeHtml(appName)} • Automated message
              </td>
            </tr>
          </table>

          <!-- small responsive hint -->
          <div style="max-width:520px;color:rgba(139,144,160,0.70);font-size:11px;font-family:Arial,Helvetica,sans-serif;padding-top:10px;text-align:center;">
            Tip: best viewed in dark mode
          </div>
        </td>
      </tr>
    </table>
  </div>
  `;
}

serve(async (req) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    const RESEND_API_KEY = mustEnv("RESEND_API_KEY_ACCESS");
    const FROM_EMAIL = mustEnv("FROM_EMAIL"); // например: "WorkTime <security@worktime.app>"
    const SUPABASE_URL = mustEnv("SUPABASE_URL");
    const SERVICE_ROLE = mustEnv("SUPABASE_SERVICE_ROLE_KEY");

    const resend = new Resend(RESEND_API_KEY);
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);

    // ✅ мы НЕ принимаем email из body
    // ожидаем либо user_id (auth uuid), либо admin_email (если хочешь)
    const body = await req.json().catch(() => ({}));
    const user_id = (body?.user_id ?? "").toString().trim();

    if (!user_id) {
      return json({ error: "user_id required" }, 400);
    }

    // 1) получаем email из auth
    const { data: userData, error: uErr } = await supabase.auth.admin.getUserById(user_id);
    if (uErr || !userData?.user) return json({ error: "User not found" }, 404);

    const email = (userData.user.email ?? "").toString().trim();
    const name =
        (userData.user.user_metadata?.name ??
            userData.user.user_metadata?.full_name ??
            "there").toString();

    if (!email) return json({ error: "User email is empty" }, 400);

    // 2) html
    const html = buildPasswordUpdatedHtml({
      name,
      email,
      appName: "WorkTime",
      logoUrl: "https://mnycxmpofeajhjecsvhk.supabase.co/storage/v1/object/public/images/mahmadiyarov.png",
    });

    // 3) send
    const result = await resend.emails.send({
      from: FROM_EMAIL,
      to: [email],
      subject: "Your password has been updated",
      html,
    });

    return json({ success: true, result });
  } catch (e) {
    return json({ error: String((e as any)?.message ?? e) }, 500);
  }
});
