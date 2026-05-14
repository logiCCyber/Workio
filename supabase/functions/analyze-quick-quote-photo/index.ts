import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type PriceRuleForVision = {
    rule_id: string;
    service_type: string;
    display_name?: string | null;
    category?: string | null;
    unit?: string | null;
    aliases?: string[];
    ai_keywords?: string[];
    negative_keywords?: string[];
};

type PossibleAction = {
    rule_id: string;
    label: string;
    action_type: string;
};

type Detection = {
    image_index: number;
    object_label: string;
    confidence: number;
    possible_actions: PossibleAction[];
    warning: string;
};

serve(async (req) => {
    try {
        if (req.method === "OPTIONS") {
            return new Response(null, { status: 200, headers: corsHeaders });
        }

        if (req.method !== "POST") {
            return jsonResponse({ error: "Method not allowed" }, 405);
        }

        const openAiKey = Deno.env.get("OPENAI_API_KEY");
        if (!openAiKey) {
            return jsonResponse({ error: "Missing OPENAI_API_KEY" }, 500);
        }

        const body = await req.json();

        const priceRules = Array.isArray(body.priceRules)
            ? body.priceRules as PriceRuleForVision[]
            : [];

        const rawImages = Array.isArray(body.images) ? body.images : [];

        const images = rawImages
            .map((item: Record<string, unknown>) => ({
                imageBase64: String(item.imageBase64 ?? "").trim(),
                mimeType: String(item.mimeType ?? "image/jpeg").trim() || "image/jpeg",
            }))
            .filter((item) => item.imageBase64.length > 0)
            .slice(0, 5);

        if (images.length === 0) {
            return jsonResponse({ error: "Missing images" }, 400);
        }

        if (priceRules.length === 0) {
            return jsonResponse({
                detections: [],
                global_warning: "No active Price Rules found. Add Price Rules before using Photo Quick Quote.",
            });
        }

        const rulesText = priceRules.map((rule) => ({
            rule_id: rule.rule_id,
            service_type: rule.service_type,
            display_name: rule.display_name ?? rule.service_type,
            category: rule.category ?? "",
            unit: rule.unit ?? "",
            aliases: rule.aliases ?? [],
            ai_keywords: rule.ai_keywords ?? [],
            negative_keywords: rule.negative_keywords ?? [],
        }));

        const prompt = `
You are Workio Photo Quick Quote Vision.

Your job:
1. Analyze each image SEPARATELY and independently.
2. For each image, identify the main service object visible (appliance, fixture, pipe, outlet, surface, etc.).
3. For each detected object, suggest 2-4 possible service actions from the provided Price Rules.
4. Return a structured JSON with one detection per image.

CRITICAL RULES:
- You MUST only use rule_ids from the provided Price Rules list.
- Never invent rule_ids or service types not in the list.
- If an image does not match any Price Rule, still return a detection with empty possible_actions and a warning.
- Use negative_keywords to exclude wrong rules.
- For each object, think: what could an admin need to do with it? (inspect, repair, replace, install, service, clean, etc.)
- Match each possible action to the BEST fitting Price Rule for that action type.
- Different actions on the same object may map to different rule_ids if different rules exist.
- If only one matching rule exists for an object, still return it as a possible action.
- IMPORTANT: If an item looks intact or undamaged, always include "Inspect" as one of the possible actions because admin photographs items for a reason.
- Confidence: how certain are you this image matches the provided Price Rules (0.0 to 1.0).
- If confidence < 0.5 for an image, return empty possible_actions and explain in warning.

action_type values to use:
- "inspect" → checking, diagnosing, testing
- "repair" → fixing existing item
- "replace" → removing old and putting new
- "install" → brand new installation
- "service" → maintenance, cleaning, general service
- "remove" → removal only

Label format: "[Action] [Object]" — e.g. "Inspect Outlet", "Replace Fridge", "Repair Sink"

Available Price Rules:
${JSON.stringify(rulesText, null, 2)}

Return ONLY this JSON shape (no markdown, no explanation):
{
  "detections": [
    {
      "image_index": 1,
      "object_label": "short name of detected object",
      "confidence": 0.0-1.0,
      "possible_actions": [
        {
          "rule_id": "exact rule_id from Price Rules",
          "label": "Action Object",
          "action_type": "inspect|repair|replace|install|service|remove"
        }
      ],
      "warning": "short warning if uncertain, else empty string"
    }
  ],
  "global_warning": "overall warning if needed, else empty string"
}

Rules for possible_actions order:
1. Most likely action first (based on visible condition)
2. Then alternative actions
3. Maximum 4 actions per detection
`.trim();

        const response = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${openAiKey}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                model: "gpt-4o",
                temperature: 0.1,
                response_format: { type: "json_object" },
                messages: [
                    {
                        role: "user",
                        content: [
                            { type: "text", text: prompt },
                            ...images.map((image) => ({
                                type: "image_url",
                                image_url: {
                                    url: `data:${image.mimeType};base64,${image.imageBase64}`,
                                    detail: "high",
                                },
                            })),
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

        const validRuleIds = new Set(priceRules.map((r) => r.rule_id));

        const rawDetections = Array.isArray(parsed.detections) ? parsed.detections : [];

        const detections: Detection[] = rawDetections.map((d: any) => {
            const rawActions = Array.isArray(d.possible_actions) ? d.possible_actions : [];

            // Filter only valid rule_ids that exist in Price Rules
            const validActions: PossibleAction[] = rawActions
                .filter((a: any) => {
                    const rid = String(a.rule_id ?? "").trim();
                    return rid.length > 0 && validRuleIds.has(rid);
                })
                .map((a: any) => ({
                    rule_id: String(a.rule_id).trim(),
                    label: String(a.label ?? "").trim(),
                    action_type: String(a.action_type ?? "service").trim(),
                }))
                .slice(0, 4);

            return {
                image_index: Number(d.image_index ?? 0),
                object_label: String(d.object_label ?? "Unknown").trim(),
                confidence: Math.min(1, Math.max(0, Number(d.confidence ?? 0))),
                possible_actions: validActions,
                warning: String(d.warning ?? "").trim(),
            };
        });

        return jsonResponse({
            detections,
            global_warning: String(parsed.global_warning ?? "").trim(),
        });

    } catch (e) {
        return jsonResponse({ error: String(e) }, 500);
    }
});

function jsonResponse(data: unknown, status = 200) {
    return new Response(JSON.stringify(data), {
        status,
        headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
        },
    });
}