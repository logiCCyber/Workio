import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

    const corsHeaders = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Content-Type": "application/json",
    };

    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    if (req.method !== "POST") {
        return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: corsHeaders });
    }

    const authHeader = req.headers.get("Authorization") ?? "";

// ✅ Клиент "как пользователь" — чтобы узнать, кто вызвал функцию
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
        global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: corsHeaders });
    }

    const adminId = userData.user.id; // ✅ это владелец


// ✅ Сервисный клиент — для admin.createUser + записи в БД
    const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

    try {
        const body = await req.json();
        const { email, name, hourly_rate, avatar_base64 } = body;

        // 1) VALIDATION
        if (!email || !name || hourly_rate == null) {
            return new Response(JSON.stringify({ error: "Missing required fields" }), { status: 400, headers: corsHeaders });
        }

        const normalizedEmail = String(email).trim().toLowerCase();
        const safeName = String(name).trim();
        const rate = Number(hourly_rate);

        if (!normalizedEmail.includes("@")) {
            return new Response(JSON.stringify({ error: "Invalid email" }), { status: 400, headers: corsHeaders });
        }
        if (!safeName) {
            return new Response(JSON.stringify({ error: "Invalid name" }), { status: 400, headers: corsHeaders });
        }
        if (!Number.isFinite(rate) || rate <= 0) {
            return new Response(JSON.stringify({ error: "Invalid hourly_rate" }), { status: 400, headers: corsHeaders });
        }

        // 2) WORKER EXISTS?
        const { data: existingWorker, error: existsError } = await supabase
            .from("workers")
            .select("id")
            .eq("email", normalizedEmail)
            .maybeSingle();

        if (existsError) {
            return new Response(JSON.stringify({ error: existsError.message }), { status: 500, headers: corsHeaders });
        }
        if (existingWorker) {
            // чтобы у тебя в приложении было красиво
            return new Response(JSON.stringify({ error: "WORKER_EXISTS" }), { status: 409, headers: corsHeaders });
        }

        // 3) CREATE (or reuse) AUTH USER
        let userId: string | null = null;

        const { data: created, error: createError } = await supabase.auth.admin.createUser({
            email: normalizedEmail,
            email_confirm: true,
        });

        if (createError) {
            const msg = (createError.message ?? "").toLowerCase();

            // auth already exists -> продолжаем дальше (НЕ падаем)
            if (msg.includes("already been registered")) {
                // ❗ тут нам нужно получить userId существующего auth-юзера
                // Вариант 1 (быстро и надёжно): ищем в таблице workers (если там auth_user_id уже есть)
                const { data: w2, error: w2err } = await supabase
                    .from("workers")
                    .select("auth_user_id")
                    .eq("email", normalizedEmail)
                    .maybeSingle();

                if (w2err) return new Response(JSON.stringify({ error: w2err.message }), { status: 500, headers: corsHeaders });

                if (w2?.auth_user_id) {
                    userId = w2.auth_user_id;
                } else {
                    // Вариант 2: если workers нет, а auth есть — тогда admin lookup
                    // supabase-js v2: listUsers + find by email
                    const { data: list, error: listErr } = await supabase.auth.admin.listUsers({ page: 1, perPage: 1000 });
                    if (listErr) return new Response(JSON.stringify({ error: listErr.message }), { status: 500, headers: corsHeaders });

                    const u = (list?.users ?? []).find((x) => (x.email ?? "").toLowerCase() === normalizedEmail);
                    if (!u?.id) {
                        return new Response(JSON.stringify({ error: "Auth user exists but cannot fetch id" }), { status: 500, headers: corsHeaders });
                    }
                    userId = u.id;
                }
            } else {
                return new Response(JSON.stringify({ error: createError.message }), { status: 400, headers: corsHeaders });
            }
        } else {
            userId = created?.user?.id ?? null;
        }

        if (!userId) {
            return new Response(JSON.stringify({ error: "Cannot resolve auth user id" }), { status: 500, headers: corsHeaders });
        }

        // 3.5) GENERATE REAL RESET LINK (for your Resend email)
        const { data: linkData, error: linkErr } = await supabase.auth.admin.generateLink({
            type: "recovery",
            email: normalizedEmail,
            options: { redirectTo: "workio://reset-password" },
        });

        if (linkErr) {
            return new Response(JSON.stringify({ error: linkErr.message }), { status: 500, headers: corsHeaders });
        }

        const resetLink = linkData?.properties?.action_link;
        if (!resetLink) {
            return new Response(JSON.stringify({ error: "Reset link was not generated" }), { status: 500, headers: corsHeaders });
        }

        // 4) AVATAR UPLOAD (optional)
        let avatarUrl: string | null = null;

        if (avatar_base64) {
            const base64 = String(avatar_base64);
            const pure = base64.includes(",") ? base64.split(",")[1] : base64;
            const bytes = Uint8Array.from(atob(pure), (c) => c.charCodeAt(0));
            const fileName = `${crypto.randomUUID()}.jpg`;

            const { error: uploadError } = await supabase.storage
                .from("avatars")
                .upload(fileName, bytes, { contentType: "image/jpeg", upsert: false });

            if (uploadError) {
                return new Response(JSON.stringify({ error: "Avatar upload failed" }), { status: 500, headers: corsHeaders });
            }

            avatarUrl = supabase.storage.from("avatars").getPublicUrl(fileName).data.publicUrl;
        }

        // 5) UPSERT worker
        const { error: upsertError } = await supabase
            .from("workers")
            .upsert(
                {
                    auth_user_id: userId,
                    email: normalizedEmail,
                    name: safeName,
                    hourly_rate: rate,
                    avatar_url: avatarUrl ?? null,
                    role: "worker",
                    is_active: true,
                    on_shift: false,
                    access_mode: "active",

                    // ✅ старое поле можешь оставить
                    owner_admin_id: adminId,

                    // ✅ ВОТ ЭТО ГЛАВНОЕ
                    created_by_auth_id: adminId,
                },
                { onConflict: "email" }
            );

        if (upsertError) {
            return new Response(JSON.stringify({ error: upsertError.message }), { status: 500, headers: corsHeaders });
        }

        // 6) SEND WELCOME EMAIL (Resend)
        const RESEND_API_KEY = Deno.env.get("SUCCESS_REG") || Deno.env.get("RESEND_API_KEY");
        const EMAIL_FROM =
            Deno.env.get("EMAIL_FROM") ||
            Deno.env.get("FROM_EMAIL") ||
            "Workio <noreply@workio.ca>";

        if (!RESEND_API_KEY) {
            return new Response(JSON.stringify({ error: "Resend API key is missing (SUCCESS_REG)" }), { status: 500, headers: corsHeaders });

        }
        if (!EMAIL_FROM) {
            return new Response(JSON.stringify({ error: "EMAIL_FROM is missing" }), { status: 500, headers: corsHeaders });
        }

        const year = new Date().getFullYear();
        const logoUrl =
            "https://mnycxmpofeajhjecsvhk.supabase.co/storage/v1/object/public/images/mahmadiyarov.png";

        const html = `<!doctype html>
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
                        style="color:#A8B0C2;font-size:12px;font-weight:800;">
                      Invitation email
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
                  Workio
                </div>

                <div style="height:8px;"></div>

                <div style="color:rgba(183,188,203,0.85);font-size:14px;line-height:20px;text-align:center;font-weight:700;">
                  Welcome to the team
                </div>

                <div style="height:14px;"></div>

                <!-- GREEN CENTER DIVIDER -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td style="height:2px;background:transparent;"></td>
                    <td width="220" style="height:2px;background:rgba(108,255,141,0.55);font-size:0;line-height:0;">&nbsp;</td>
                    <td style="height:2px;background:transparent;"></td>
                  </tr>
                </table>

                <div style="height:18px;"></div>

                <!-- GREETING -->
                <div style="color:#FFFFFF;font-size:18px;font-weight:900;line-height:24px;">
                  Hi ${safeName}, 👋
                </div>

                <div style="height:10px;"></div>

                <div style="color:rgba(183,188,203,0.85);font-size:14px;line-height:22px;font-weight:700;">
                  You’ve been invited to work with <span style="color:#EDEFF6;font-weight:900;">Workio</span>.
                </div>

                <div style="height:8px;"></div>

                <div style="color:rgba(183,188,203,0.72);font-size:13px;line-height:20px;font-weight:700;">
                  Please set your password to activate your access and sign in to the app.
                </div>

                <div style="height:18px;"></div>

                <!-- RATE CARD -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="background:rgba(255,255,255,0.04);
                              border:1px solid rgba(255,255,255,0.08);
                              border-radius:18px;
                              border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td align="center" style="padding:16px 16px 18px 16px;">
                      <div style="color:rgba(183,188,203,0.72);font-size:12px;line-height:16px;font-weight:700;">
                        Hourly rate
                      </div>
                      <div style="height:8px;"></div>
                      <div style="color:#6CFF8D;font-size:34px;line-height:38px;font-weight:900;letter-spacing:-0.4px;">
                        $${rate.toFixed(2)}
                      </div>
                    </td>
                  </tr>
                </table>

                <div style="height:18px;"></div>

                <!-- CTA BUTTON -->
                <table role="presentation" align="center" cellpadding="0" cellspacing="0" border="0" style="margin:0 auto;">
                  <tr>
                    <td align="center" bgcolor="#49D66D"
                        style="border-radius:16px;background:linear-gradient(135deg,#5CFF8A,#2E7D32);">
                      <a href="${resetLink}"
                         style="display:inline-block;min-width:220px;padding:15px 28px;
                                font-size:16px;line-height:20px;font-weight:900;
                                color:#07110A;text-decoration:none;border-radius:16px;">
                        Set password
                      </a>
                    </td>
                  </tr>
                </table>

                <div style="height:16px;"></div>

                <!-- HELP TEXT -->
                <div style="color:rgba(183,188,203,0.72);font-size:12px;line-height:18px;text-align:center;font-weight:700;">
                  This secure link lets you create your password and finish account setup.
                </div>

                <div style="height:14px;"></div>

                <!-- FALLBACK LINK BOX -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="background:rgba(255,255,255,0.04);
                              border:1px solid rgba(255,255,255,0.08);
                              border-radius:16px;
                              border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td style="padding:12px 14px 12px 14px;">
                      <div style="color:rgba(183,188,203,0.78);font-size:12px;line-height:17px;font-weight:700;">
                        If the button doesn’t work, copy and open this link:
                      </div>
                      <div style="height:8px;"></div>
                      <div style="font-size:12px;line-height:18px;word-break:break-all;">
                        <a href="${resetLink}" style="color:#6CFF8D;text-decoration:underline;">
                          ${resetLink}
                        </a>
                      </div>
                    </td>
                  </tr>
                </table>

                <div style="height:16px;"></div>

                <!-- MINI NOTE -->
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="background:rgba(108,255,141,0.06);
                              border:1px solid rgba(108,255,141,0.14);
                              border-radius:16px;
                              border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td style="padding:12px 14px 12px 14px;">
                      <div style="color:#EDEFF6;font-size:12.5px;line-height:18px;font-weight:800;">
                        Important
                      </div>
                      <div style="height:4px;"></div>
                      <div style="color:rgba(183,188,203,0.78);font-size:12px;line-height:18px;font-weight:700;">
                        For security, please change your password only through the button or link in this email.
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
                      This is an automated message. Please do not reply.<br/>
                      If you didn’t expect this invitation, you can safely ignore this email.<br/>
                      If you believe this is a mistake, please contact your administrator.
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


        const sendRes = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${RESEND_API_KEY}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                from: EMAIL_FROM,
                to: normalizedEmail,
                subject: "Welcome to Workio ✅",
                html,
            }),
        });

        if (!sendRes.ok) {
            const txt = await sendRes.text();
            return new Response(JSON.stringify({ error: "Email send failed",  details: txt }), { status: 500, headers: corsHeaders });
        }

        return new Response(JSON.stringify({ success: true, code: "SUCCESS_REG" }), { status: 200, headers: corsHeaders });
    } catch (e) {
        return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
    }
});
