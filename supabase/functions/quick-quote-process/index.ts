import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
    return new Response(JSON.stringify(data), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
}

function cleanString(value: unknown) {
    return String(value ?? "").trim();
}

function toNumberOrNull(value: unknown): number | null {
    if (value == null) return null;
    const parsed = Number(String(value).replace(",", "."));
    return Number.isFinite(parsed) ? parsed : null;
}

serve(async (req) => {
    if (req.method === "OPTIONS") {
        return new Response(null, { status: 200, headers: corsHeaders });
    }

    if (req.method !== "POST") {
        return json({ error: "Method not allowed" }, 405);
    }

    try {
        const body = await req.json().catch(() => ({}));
        const rawPrompt = cleanString(body?.prompt);
        const priceRules = Array.isArray(body?.priceRules) ? body.priceRules : [];

        if (!rawPrompt) throw new Error("prompt is required");
        if (!priceRules.length) throw new Error("priceRules is required");

        const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
        if (!OPENAI_API_KEY) throw new Error("OPENAI_API_KEY is missing");

        const compactRules = priceRules.map((r: any) => ({
            ruleId: cleanString(r.ruleId ?? r.id),
            displayName: cleanString(r.displayName ?? r.display_name),
            serviceType: cleanString(r.serviceType ?? r.service_type),
            unit: cleanString(r.unit),
            baseRate: toNumberOrNull(r.baseRate ?? r.base_rate) ?? 0,
            rushFixedRate: toNumberOrNull(r.rushFixedRate ?? r.rush_fixed_rate),
            aliases: Array.isArray(r.aliases) ? r.aliases.map(cleanString) : [],
            aiKeywords: Array.isArray(r.aiKeywords ?? r.ai_keywords)
                ? (r.aiKeywords ?? r.ai_keywords).map(cleanString)
                : [],
            negativeKeywords: Array.isArray(r.negativeKeywords ?? r.negative_keywords)
                ? (r.negativeKeywords ?? r.negative_keywords).map(cleanString)
                : [],
        }));

        const schema = {
            name: "quick_quote_result",
            schema: {
                type: "object",
                additionalProperties: false,
                properties: {
                    cleanPrompt: { type: "string" },
                    jobs: {
                        type: "array",
                        items: {
                            type: "object",
                            additionalProperties: false,
                            properties: {
                                ruleId: { type: ["string", "null"] },
                                description: { type: "string" },
                                quantity: { type: "number" },
                                laborUnitPrice: { type: ["number", "null"] },
                                isUrgent: { type: "boolean" },
                                materialsIncluded: { type: "boolean" },
                                materials: {
                                    type: "array",
                                    items: {
                                        type: "object",
                                        additionalProperties: false,
                                        properties: {
                                            name: { type: "string" },
                                            quantity: { type: "number" },
                                            unitPrice: { type: "number" },
                                            lineTotal: { type: "number" },
                                        },
                                        required: ["name", "quantity", "unitPrice", "lineTotal"],
                                    },
                                },
                            },
                            required: [
                                "ruleId",
                                "description",
                                "quantity",
                                "laborUnitPrice",
                                "isUrgent",
                                "materialsIncluded",
                                "materials",
                            ],
                        },
                    },
                },
                required: ["cleanPrompt", "jobs"],
            },
            strict: true,
        };

        const systemPrompt = `
You are a universal quick quote engine for Workio.

Your job:
1. Translate and normalize the admin prompt into clear English.
2. Split the prompt into separate jobs if it contains multiple tasks.
3. For each job, find the best matching Price Rule from the provided list.
4. Extract quantity, labor price override, urgency, and materials for each job.

Rules:
- Understand any language: English, Russian, Russian transliteration, Uzbek, French, or mixed.
- Translate action words correctly: zamenit/pomenyat = replace, ustanovit = install, pochinit = repair.
- Match each job to exactly one Price Rule using aliases and aiKeywords.
- Use negativeKeywords to exclude wrong rules.
- If no rule matches a job, set ruleId = null for that job.
- quantity: extract the number that is clearly associated with the service object in the prompt. Examples: "2 outlets" = 2, "1200 sqft" = 1200, "2 loads" = 2. Default 1 only if truly not specified.
- laborUnitPrice: set if the prompt states a price for the service itself. CRITICAL distinction:
  - "po $X", "по $X", "$X each", "$X per item", "po $X kazhdiy" → unit price per item, set laborUnitPrice = X
  - "za $X", "за $X", "for $X total" (without "vse/все") → TOTAL price for all units, set laborUnitPrice = X / quantity (round to 2 decimals)
  - "za vse $X", "за все $X", "$X za vse" + urgency present → this is a Visit Rush Fee, NOT a labor override. See the Visit Rush Fee rule below.
  - Example: "3 shtuki za $200" → quantity=3, laborUnitPrice=66.67
  - Example: "3 shtuki po $200" → quantity=3, laborUnitPrice=200
  - IMPORTANT: "za $X" is the TOTAL labor price only. Never subtract materials from it. Labor and materials are always independent.
- materials: only add if prompt explicitly says "materials included" or "materiali vklyucheny" WITH a price. If prompt says only a service price per item without mentioning materials, do NOT add materials.
- If the prompt says "materiali vklyucheny tolko X za $Y", set laborUnitPrice=null and put the price in materials only for that specific item.
- isUrgent: true if prompt says urgent, rush, srochno, same day, asap, shoshilinch, etc. Set isUrgent=false and do NOT create any rush fee job if prompt says: "ne srochnaya", "ne srochno", "not urgent", "no rush", "bez srochnosti".
- materialsIncluded: true only if prompt explicitly says materials included for this job.
- materials: parse only if prompt explicitly lists material items with prices. Do NOT invent materials.
  - "po $X kazhdiy", "po $X", "$X each", "$X per item" → material unit price per item. Set quantity = same as job quantity, unitPrice = X, lineTotal = quantity × X.
  - "za $X", single price without "po/each/kazhdiy" (e.g. "rakovina 200$") → total materials price. Set quantity=1, unitPrice=X, lineTotal=X.
  - Example: "razetki po $30 kazhdiy", job qty=3 → materials quantity=3, unitPrice=30, lineTotal=90.
  - Example: "materiali $200" (no "po") → quantity=1, unitPrice=200, lineTotal=200.
- If urgency applies to all jobs, set isUrgent=true for every job.
- Never skip or merge jobs. Count all action verbs in the prompt and return exactly that many jobs.
- Each unique object mentioned with an action verb must become its own separate job. If one action verb applies to multiple objects connected by "and", "i", "и", or comma, create a separate job for each object.
- When matching jobs to Price Rules, prefer the rule whose aliases or aiKeywords contain the specific object from the prompt. Do not match by room name or location.
- If the prompt mentions urgency (srochnaya, rush, urgent, etc.) AND a total price with "za vse", "за все", "for everything", "for all", "total for visit" — that price is the Visit Rush Fee ONLY. Create one job: ruleId=null, description="Visit Rush Fee", quantity=1, laborUnitPrice=that price. All other jobs keep their Price Rule base rates, do NOT override them.
- If no urgency is mentioned but there's a single total price "za vse" — that price is the total labor override, divide by number of jobs.
- Never calculate totals or taxes.
- Return strict JSON only.

Available Price Rules:
${JSON.stringify(compactRules, null, 2)}
`.trim();

        const userPrompt = `Admin prompt:\n${rawPrompt}`;

        const response = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${OPENAI_API_KEY}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                model: "gpt-4o",
                messages: [
                    { role: "system", content: systemPrompt },
                    { role: "user", content: userPrompt },
                ],
                response_format: {
                    type: "json_schema",
                    json_schema: schema,
                },
                temperature: 0.1,
            }),
        });

        const data = await response.json().catch(() => ({}));

        if (!response.ok) {
            throw new Error(
                typeof data?.error?.message === "string"
                    ? data.error.message
                    : "OpenAI request failed",
            );
        }

        const content = data?.choices?.[0]?.message?.content;
        if (typeof content !== "string" || !content.trim()) {
            throw new Error("Model returned empty content");
        }

        const parsed = JSON.parse(content);

        const ruleIds = new Set(compactRules.map((r: any) => r.ruleId));

        const jobs = Array.isArray(parsed.jobs)
            ? parsed.jobs.map((job: any) => ({
                ruleId: job.ruleId && ruleIds.has(job.ruleId) ? job.ruleId : null,
                description: cleanString(job.description),
                quantity: toNumberOrNull(job.quantity) ?? 1,
                laborUnitPrice: toNumberOrNull(job.laborUnitPrice),
                isUrgent: job.isUrgent === true,
                materialsIncluded: job.materialsIncluded === true,
                materials: Array.isArray(job.materials)
                    ? job.materials.map((m: any) => ({
                        name: cleanString(m.name),
                        quantity: toNumberOrNull(m.quantity) ?? 1,
                        unitPrice: toNumberOrNull(m.unitPrice) ?? 0,
                        lineTotal: toNumberOrNull(m.lineTotal) ?? 0,
                    })).filter((m: any) => m.unitPrice > 0)
                    : [],
            }))
            : [];

        return json({
            cleanPrompt: cleanString(parsed.cleanPrompt) || rawPrompt,
            jobs,
        });

    } catch (e) {
        return json({ error: e instanceof Error ? e.message : String(e) }, 400);
    }
});