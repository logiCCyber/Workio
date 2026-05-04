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

serve(async (req) => {
    try {
        if (req.method === "OPTIONS") {
            return new Response(null, {
                status: 200,
                headers: corsHeaders,
            });
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
            .map((item: Record<string, unknown>) => {
                return {
                    imageBase64: String(item.imageBase64 ?? "").trim(),
                    mimeType: String(item.mimeType ?? "image/jpeg").trim() || "image/jpeg",
                };
            })
            .filter((item) => item.imageBase64.length > 0)
            .slice(0, 5);

        if (images.length === 0) {
            return jsonResponse({ error: "Missing images" }, 400);
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
                rule_id: rule.rule_id,
                service_type: rule.service_type,
                display_name: rule.display_name ?? rule.service_type,
                category: rule.category ?? "",
                unit: rule.unit ?? "",
                aliases: rule.aliases ?? [],
                ai_keywords: rule.ai_keywords ?? [],
                negative_keywords: rule.negative_keywords ?? [],
            };
        });

        const prompt = `
You are Workio Photo Quick Quote Vision.

Your job:
1. Look at all provided images together.
2. Decide if the images show one or more real service jobs relevant to the provided Price Rules.
3. Do NOT select only one job. Build a suggested_prompt that includes every relevant visible job.
4. If the images do not clearly match any provided Price Rule, return matched=false.
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
  "rule_id": "one of provided rule_id or empty",
  "service_type": "one of provided service_type or empty",
  "service_label": "display name from matched rule or empty",
  "image_observations": [
    {
      "image_index": 1,
      "visible_issue": "short description of this specific image",
      "relevant": true
    }
  ],
  "detected_issue": "combined short neutral description from all relevant images",
  "suggested_prompt": "plain English Quick Quote prompt for admin review",
  "warning": "short warning if uncertain or no match"
}

Universal rules:
- You MUST choose only from the provided Price Rules.
- You MUST NOT use any service name that is not in the provided Price Rules.
- If the images are unrelated to the provided Price Rules, return matched=false.
- If the visible job is unclear, return matched=false.
- If confidence is below 0.60, return matched=false.
- The suggested_prompt SHOULD reference the matched rule, but it must describe the visible work accurately. Do not force the display name if it makes the wording wrong.
- The suggested_prompt should describe what is visible in the images as a practical work request.
- If multiple photos show multiple separate jobs, the suggested_prompt MUST list all jobs in one clear prompt.
- If different images show different service needs, do not merge them into one vague issue.
- Write the suggested_prompt so the next step can split it into separate jobs.
- For multiple photos, your main task is to create a multi-job suggested_prompt, not to choose only one rule.
- The suggested_prompt may include several service jobs if several photos show different issues.
- Do NOT let rule_id/service_type limit the suggested_prompt to one job.
- If multiple relevant images match different Price Rules, still return one combined suggested_prompt containing all relevant jobs.
- Use clear action-object wording for each job, such as "Replace 1 outlet", "Install toilet", "Repair sink leak", "Remove debris".
- If one image shows damage and another image shows an installation target, include both jobs separately.
- If a photo is relevant but the exact action is unclear, write "Inspect..." for that item instead of ignoring it.
- For multiple images, combine all relevant visible issues into one clear work request.
- Do not collapse clearly different visible issues into one vague item.
- Do not calculate price, tax, total, rates, or line items.
- Do not create estimate or invoice wording.
- Do not force materials.
- Do not write uncertain alternatives like "install or repair", "repair or replace", "replace or inspect", or "install/repair" in suggested_prompt.
- If the exact action is unclear from the photo, use "Inspect" or "Diagnose" instead of listing multiple alternatives.
- If visible damage exists but the final action is uncertain, write "Inspect and repair as needed" only when appropriate.
- suggested_prompt must be directly priceable by Workio. Avoid "or" choices that require different Price Rules.
- If the photo does not clearly show whether work is installation, repair, or replacement, prefer inspection wording.
Examples:

Bad:
Replace or inspect 1 burned outlet. Inspect 1 additional outlet.

Good:
Inspect 1 burned outlet and repair or replace as needed. Inspect 1 additional outlet. Materials not specified.
- Mention materials only if the images clearly show replaceable parts and mentioning them is useful for admin review.
- If materials are uncertain, write "Materials not specified."
- If quantity is clearly visible and useful, include it in the work request.
- If quantity is uncertain, do not guess.
- If the images suggest safety concerns, unclear conditions, or inspection is reasonably needed, mention inspection.
- If multiple relevant images show different conditions, the suggested_prompt MUST mention each relevant condition separately.
- If one image shows clear damage and another image shows discoloration or possible damage, write that one item needs repair/replacement and the other needs inspection.
- Do NOT ignore a second relevant image just because the first image has a stronger visible issue.
- If damage is visible, prefer practical wording like inspect, repair, replace, or service.
- Do NOT use installation wording unless the image clearly shows a new installation request.
- If the matched Price Rule display name says installation but the image shows damage, keep the matched rule_id but write the suggested_prompt as repair/replacement/inspection wording.
- suggested_prompt must be plain English only.
- suggested_prompt must be suitable for Workio Text Quick Quote multi-job processing.
- Do not include JSON, bullets, markdown, or numbering inside suggested_prompt. Use short sentences.
- The admin will review and edit the suggested_prompt before pricing.
- The pricing engine will calculate pricing later using Price Rules.
- Use wording from the matched rule display_name, aliases, and ai_keywords when helpful, but do not force words that are not supported by the images.
- negative_keywords are exclusion clues. If the image clearly matches a candidate's negative_keywords, do NOT choose that rule unless the rest of the rule is still clearly the best match.
- Analyze each image individually before creating the final suggested_prompt.
- For every provided image, add one entry to image_observations with image_index starting at 1.
- The final suggested_prompt must be based on all relevant image_observations.
- If image_observations contain 2 or more relevant issues, suggested_prompt should mention each as a separate sentence.
- Never drop a relevant image just because another image has a stronger issue.
- Each image_observation must describe only what is visible in that specific image.
- After image_observations are completed, combine all relevant observations into detected_issue and suggested_prompt.
- The final suggested_prompt must not ignore relevant images.
- If one image is unrelated but the others clearly match one Price Rule, mention this in warning and build prompt from relevant images only.
- You MUST return rule_id from the matched Price Rule.
- rule_id is the primary match. service_type is only supporting text.
- Return ONLY valid JSON.
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
                            ...images.map((image) => ({
                                type: "image_url",
                                image_url: {
                                    url: `data:${image.mimeType};base64,${image.imageBase64}`,
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

        const ruleId = String(parsed.rule_id ?? "").trim();
        const matchedRule = priceRules.find(
            (r) => String(r.rule_id ?? "").trim() === ruleId
        );

        const serviceType = String(
            parsed.service_type ?? matchedRule?.service_type ?? ""
        ).trim();

        if (!matchedRule) {
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
            rule_id: ruleId,
            service_type: matchedRule.service_type,
            service_label: String(
                parsed.service_label ?? matchedRule.display_name ?? matchedRule.service_type
            ),
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
            ...corsHeaders,
            "Content-Type": "application/json",
        },
    });
}