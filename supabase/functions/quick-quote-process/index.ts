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

        const hasRules = compactRules.length > 0;

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
                                isMarketRate: { type: "boolean" },
                                marketRateNote: { type: "string" },
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
                                "isMarketRate",
                                "marketRateNote",
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
You are a universal quick quote engine for Workio — a construction and home services company management app.

Your job:
1. Translate and normalize the admin prompt into clear English.
2. Split the prompt into separate jobs if it contains multiple tasks.
3. For each job, find the best matching Price Rule from the provided list.
4. If NO matching Price Rule exists — use your knowledge of North American market rates and set isMarketRate=true.
5. Extract quantity, labor price override, urgency, and materials for each job.

Language rules:
- Understand any language: English, Russian, Russian transliteration, Uzbek, French, or mixed.
- Translate action words correctly: zamenit/pomenyat = replace, ustanovit = install, pochinit = repair.

Price Rule matching:
- Match each job to exactly one Price Rule using aliases and aiKeywords.
- Use negativeKeywords to exclude wrong rules.
- If no rule matches a job, set ruleId = null AND set isMarketRate = true.

CRITICAL — Market Rate Fallback (when ruleId = null):
- NEVER return laborUnitPrice = null when ruleId = null.
- You MUST estimate a realistic North American market rate for the service.
- Set laborUnitPrice = your estimated market rate per unit.
- Set isMarketRate = true.
- Set marketRateNote = short note explaining the rate, e.g. "Market rate estimate — no price rule found. You can save this to Price Rules."
- Examples of market rates:
  - Outlet replacement: $85-120 per outlet
  - Sink installation: $200-350 fixed
  - Toilet installation: $150-250 fixed
  - Dishwasher installation: $150-300 fixed
  - Dryer replacement: $100-200 fixed
  - Washer replacement: $100-200 fixed
  - Painting per sqft: $1.50-3.00/sqft
  - Flooring per sqft: $3.00-8.00/sqft
  - Drywall per sqft: $1.50-3.00/sqft
  - General handyman: $75-120/hour
  - Plumbing service call: $150-250
  - Electrical service call: $150-250

Quantity rules:
- quantity: extract the number clearly associated with the service object. Examples: "2 outlets" = 2, "1200 sqft" = 1200. Default 1 only if truly not specified.

Price override rules:
- laborUnitPrice: set if the prompt states a price for the service itself.
  - "po $X", "$X each", "$X per item" → unit price per item, laborUnitPrice = X
  - "za $X", "for $X total" (without "vse") → TOTAL price, laborUnitPrice = X / quantity
  - "za vse $X" + urgency → Visit Rush Fee, not labor override
- materials: only add if prompt explicitly states material price. Never invent materials.
- isUrgent: true if prompt says urgent, rush, srochno, same day, asap.
- materialsIncluded: true only if prompt explicitly says materials included.
- isMarketRate: true if no price rule matched and you used market rate. false if price rule matched.
- marketRateNote: non-empty only when isMarketRate=true.

Visit Rush Fee rule:
- If urgency + total price "za vse" → one job: ruleId=null, description="Visit Rush Fee", quantity=1, laborUnitPrice=that price, isMarketRate=false, marketRateNote="".

Never calculate totals or taxes.
Return strict JSON only.

${hasRules ? `Available Price Rules:\n${JSON.stringify(compactRules, null, 2)}` : 'No Price Rules available — use market rates for all jobs.'}
`.trim();

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
                    { role: "user", content: `Admin prompt:\n${rawPrompt}` },
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
                isMarketRate: job.isMarketRate === true,
                marketRateNote: cleanString(job.marketRateNote),
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