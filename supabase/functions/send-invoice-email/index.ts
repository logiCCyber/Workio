import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

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

function textToHtml(value: string) {
    return escapeHtml(value).replaceAll("\n", "<br />");
}

function infoRow(label: string, value: string) {
    return `
    <tr>
      <td style="padding:12px 14px;border-top:1px solid rgba(255,255,255,0.07);color:rgba(183,188,203,0.72);font-size:12px;font-weight:700;line-height:16px;width:38%;">
        ${escapeHtml(label)}
      </td>
      <td style="padding:12px 14px;border-top:1px solid rgba(255,255,255,0.07);color:#FFFFFF;font-size:14px;font-weight:800;line-height:20px;">
        ${value}
      </td>
    </tr>
  `;
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

        const to = String(body?.to ?? "").trim();
        const subject = String(body?.subject ?? "").trim();
        const messageText = String(body?.text ?? "").trim();

        const invoiceId = String(body?.invoice_id ?? "").trim();
        const clientName = String(body?.client_name ?? "").trim();
        const companyName = String(body?.company_name ?? "").trim() || "Workio";
        const companyEmail = String(body?.company_email ?? "").trim();
        const companyPhone = String(body?.company_phone ?? "").trim();
        const companyAddress = String(body?.company_address ?? "").trim();
        const companyLogoUrl = String(body?.company_logo_url ?? "").trim();

        const attachmentPath = String(body?.attachment?.path ?? "").trim();
        const attachmentFilename =
            String(body?.attachment?.filename ?? "").trim() || "invoice.pdf";

        if (!to || !subject) {
            throw new Error("Missing required fields: to, subject");
        }

        const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
        const FROM_EMAIL =
            Deno.env.get("FROM_EMAIL") || "Workio <noreply@workio.ca>";

        if (!RESEND_API_KEY) {
            throw new Error("RESEND_API_KEY is missing");
        }

        const year = new Date().getFullYear();

        const safeClientName = clientName || "Client";
        const introText = messageText ||
            "Please review the attached invoice. Thank you for your business.";

        const detailRows = [
            clientName
                ? infoRow("Bill To", escapeHtml(clientName))
                : "",
            invoiceId
                ? infoRow("Invoice ID", escapeHtml(invoiceId))
                : "",
            infoRow(
                "Document",
                attachmentPath
                    ? `Attached PDF: <strong>${escapeHtml(attachmentFilename)}</strong>`
                    : "No PDF attachment",
            ),
        ].join("");

        const companyContact = [
            companyEmail,
            companyPhone,
            companyAddress,
        ]
            .filter((v) => String(v ?? "").trim().isNotEmpty)
            .map((v) => escapeHtml(v))
            .join(" • ");

        const logoHtml = companyLogoUrl
            ? `
        <img src="${escapeHtml(companyLogoUrl)}" alt="${escapeHtml(companyName)}"
             height="44" style="display:block;object-fit:contain;border:0;" />
      `
            : `
        <div style="color:#FFFFFF;font-size:22px;font-weight:900;line-height:26px;">
          ${escapeHtml(companyName)}
        </div>
      `;

        const html = `<!doctype html>
<html style="margin:0;padding:0;background:#0B0D12;">
  <body style="margin:0;padding:0;background:#0B0D12;font-family:Arial,Helvetica,sans-serif;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
           style="margin:0;padding:0;background:#0B0D12;">
      <tr>
        <td align="center" style="padding:24px 12px;background:#0B0D12;">
          <table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0"
                 style="max-width:560px;width:100%;background:#1E1C22;border-radius:22px;border:1px solid rgba(255,255,255,0.10);box-shadow:0 18px 50px rgba(0,0,0,0.55);border-collapse:separate;border-spacing:0;">
            <tr>
              <td style="padding:18px;">

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td valign="middle">
                      ${logoHtml}
                    </td>
                    <td align="right" valign="middle">
                      <span style="display:inline-block;padding:7px 12px;border-radius:999px;background:rgba(32,211,119,0.10);border:1px solid #20D377;color:#4BE094;font-size:11px;font-weight:900;letter-spacing:0.4px;white-space:nowrap;">
                        INVOICE
                      </span>
                    </td>
                  </tr>
                </table>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr><td height="14" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td style="height:1px;background:rgba(255,255,255,0.07);font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td height="18" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                </table>

                <div style="color:#FFFFFF;font-size:13px;line-height:18px;font-weight:800;text-align:center;letter-spacing:1.2px;">
                  INVOICE ATTACHED
                </div>

                <div style="height:10px;"></div>

                <div style="color:#FFFFFF;font-size:34px;line-height:38px;font-weight:900;text-align:center;letter-spacing:-0.4px;">
                  Hello ${escapeHtml(safeClientName)}
                </div>

                <div style="height:8px;"></div>

                <div style="color:rgba(183,188,203,0.85);font-size:14px;line-height:22px;text-align:center;font-weight:700;">
                  Your invoice is ready. Please find the PDF attached below.
                </div>

                <div style="height:16px;"></div>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td style="height:2px;background:transparent;"></td>
                    <td width="220" style="height:2px;background:#20D377;font-size:0;line-height:0;">&nbsp;</td>
                    <td style="height:2px;background:transparent;"></td>
                  </tr>
                </table>

                <div style="height:18px;"></div>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="width:100%;background:rgba(255,255,255,0.04);border:1px solid rgba(255,255,255,0.08);border-radius:18px;border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td style="padding:18px;">
                      <div style="color:#EDEFF6;font-size:17px;line-height:22px;font-weight:900;">
                        Message
                      </div>
                      <div style="height:8px;"></div>
                      <div style="color:rgba(183,188,203,0.86);font-size:14px;line-height:22px;font-weight:700;">
                        ${textToHtml(introText)}
                      </div>
                    </td>
                  </tr>
                </table>

                <div style="height:14px;"></div>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="width:100%;background:rgba(8,25,17,0.72);border:1px solid rgba(32,211,119,0.22);border-radius:18px;border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td style="padding:16px 16px 10px 16px;color:#FFFFFF;font-size:17px;line-height:22px;font-weight:900;">
                      Invoice Summary
                    </td>
                  </tr>
                  ${detailRows}
                </table>

                <div style="height:14px;"></div>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                       style="width:100%;background:rgba(255,255,255,0.04);border:1px solid rgba(255,255,255,0.08);border-radius:18px;border-collapse:separate;border-spacing:0;">
                  <tr>
                    <td style="padding:14px 16px;">
                      <div style="color:#EDEFF6;font-size:13px;line-height:18px;font-weight:800;">
                        Contact
                      </div>
                      <div style="height:6px;"></div>
                      <div style="color:rgba(183,188,203,0.78);font-size:13px;line-height:20px;font-weight:700;">
                        ${escapeHtml(companyName)}${companyContact ? ` • ${companyContact}` : ""}
                      </div>
                    </td>
                  </tr>
                </table>

                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr><td height="16" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td style="height:1px;background:rgba(255,255,255,0.07);font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td height="14" style="font-size:0;line-height:0;">&nbsp;</td></tr>
                </table>

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
</html>`;

        const resendBody: Record<string, unknown> = {
            from: FROM_EMAIL,
            to,
            subject,
            html,
            text: messageText || "Please review the attached invoice.",
        };

        if (attachmentPath) {
            resendBody.attachments = [
                {
                    filename: attachmentFilename,
                    path: attachmentPath,
                },
            ];
        }

        const res = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${RESEND_API_KEY}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify(resendBody),
        });

        const data = await res.json().catch(() => ({}));

        if (!res.ok) {
            throw new Error(
                typeof data?.message === "string" ? data.message : JSON.stringify(data),
            );
        }

        return json(data, 200);
    } catch (e) {
        return json(
            { error: e instanceof Error ? e.message : String(e) },
            400,
        );
    }
});