import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

type PriceRuleForVision = {
    service_type: string;
    display_name?: string | null;
    aliases?: string[];
    ai_keywords?: string[];
};

serve(async (req) => {
    try {
        if (req.method !== "POST") {
            return jsonResponse({ error: "Method not allowed" }, 405);
        }

        const openAiKey = Deno.env.get("OPENAI_API_KEY");
        if (!openAiKey) {
            return jsonResponse({ error: "Missing OPENAI_API_KEY" }, 500);
        }

        const body = await req.json();

        const imageBase64 = String(body.imageBase64 ?? "").trim();
        const mimeType = String(body.mimeType ?? "image/jpeg").trim();
        const priceRules = Array.isArray(body.priceRules)
            ? body.priceRules as PriceRuleForVision[]
            : [];

        if (!imageBase64) {
            return jsonResponse({ error: "Missing imageBase64" }, 400);
        }

        if (priceRules.length === 0) {
            return jsonResponse({
                matched: false,
                confidence: 0,
                detected_issue: "",
                service_type: "",
                service_label: "",
                suggested_prompt: "",
                warning: "No active Price Rules found. Add Price Rules before using Photo Quick Quote.",
            });
        }

        const rulesText = priceRules.map((rule) => {
            return {
                service_type: rule.service_type,
                display_name: rule.display_name ?? rule.service_type,
                aliases: rule.aliases ?? [],
                ai_keywords: rule.ai_keywords ?? [],
            };
        });

        const prompt = `
You are Workio Photo Quick Quote Vision.

Your job:
1. Look at the image.
2. Decide if it clearly looks like a repair/service job.
3. Match it ONLY to one of the provided Price Rules.
4. If it does not clearly match, return matched=false.
5. Do NOT invent services.
6. Do NOT create prices.
7. Do NOT create an estimate.
8. Return ONLY valid JSON.

Available Price Rules:
${JSON.stringify(rulesText, null, 2)}

Return JSON shape:
{
  "matched": true/false,
  "confidence": 0.0-1.0,
  "service_type": "one of provided service_type or empty",
  "service_label": "display name or empty",
  "detected_issue": "short description of what is visible",
  "suggested_prompt": "plain English Quick Quote prompt starting with matched service label/service_type and using Price Rule keywords",
  "warning": "short warning if uncertain or no match"
}

Rules:
- If the photo is unrelated, like a flower, food, animal, random object, return matched=false.
- If confidence is below 0.60, return matched=false.
- You MUST match only one of the provided Price Rules.
- Do NOT invent a service that is not in Price Rules.
- Do NOT create prices.
- Do NOT create an estimate.
- The suggested_prompt MUST start with the matched service label or service_type.
- The suggested_prompt MUST use words from the matched rule aliases and ai_keywords when relevant.
- The suggested_prompt must be strong enough for the pricing engine to find the same Price Rule later.
- If the image shows an outlet, plug, switch, wire, breaker, electrical panel, burned outlet, or electrical damage, use service words like: "Electrical repair", "outlet", "wiring", "diagnostic", "replace", "inspect".
- If the image shows plumbing, sink, faucet, pipe, drain, valve, leak, clog, or water damage, use service words like: "Plumbing repair", "leak", "pipe", "drain", "fixture", "valve", "replace", "inspect".
- If the image shows roofing, shingles, flashing, roof leak, roof damage, or storm damage, use service words like: "Roofing repair", "shingles", "leak", "flashing", "inspection", "repair".
- If materials are visible but quantity is uncertain, say "materials not specified".
- If a single damaged visible item is clear, include quantity 1.
- If safety risk is visible, mention inspection.
- For a burned or discolored electrical outlet, suggested_prompt should look like:
  "Electrical repair. Replace damaged/burned electrical outlet. Inspect wiring and outlet box. Materials included: 1 electrical outlet."
`;

        const response = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${openAiKey}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                model: "gpt-4o-mini",
                temperature: 0.1,
                response_format: { type: "json_object" },
                messages: [
                    {
                        role: "user",
                        content: [
                            { type: "text", text: prompt },
                            {
                                type: "image_url",
                                image_url: {
                                    url: `data:${mimeType};base64,${imageBase64}`,
                                },
                            },
                        ],
                    },
                ],
            }),
        });

        if (!response.ok) {
            const errorText = await response.text();
            return jsonResponse({ error: errorText }, 500);
        }

        const data = await response.json();
        const content = data?.choices?.[0]?.message?.content ?? "{}";

        let parsed: Record<string, unknown>;
        try {
            parsed = JSON.parse(content);
        } catch (_) {
            parsed = {};
        }

        const matched = parsed.matched === true;
        const confidence = Number(parsed.confidence ?? 0);

        if (!matched || confidence < 0.60) {
            return jsonResponse({
                matched: false,
                confidence,
                service_type: "",
                service_label: "",
                detected_issue: String(parsed.detected_issue ?? ""),
                suggested_prompt: "",
                warning: String(
                    parsed.warning ??
                    "No matching Price Rule found for this photo."
                ),
            });
        }

        const serviceType = String(parsed.service_type ?? "").trim();
        const exists = priceRules.some(
            (r) => r.service_type.trim().toLowerCase() === serviceType.toLowerCase()
        );

        if (!exists) {
            return jsonResponse({
                matched: false,
                confidence: 0,
                service_type: "",
                service_label: "",
                detected_issue: String(parsed.detected_issue ?? ""),
                suggested_prompt: "",
                warning: "AI returned a service that is not in Price Rules.",
            });
        }

        return jsonResponse({
            matched: true,
            confidence,
            service_type: serviceType,
            service_label: String(parsed.service_label ?? serviceType),
            detected_issue: String(parsed.detected_issue ?? ""),
            suggested_prompt: String(parsed.suggested_prompt ?? ""),
            warning: String(parsed.warning ?? ""),
        });
    } catch (e) {
        return jsonResponse({ error: String(e) }, 500);
    }
});

function jsonResponse(data: unknown, status = 200) {
    return new Response(JSON.stringify(data), {
        status,
        headers: {
            "Content-Type": "application/json",
        },
    });
}