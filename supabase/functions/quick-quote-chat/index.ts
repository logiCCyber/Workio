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

serve(async (req) => {
    if (req.method === "OPTIONS") return new Response(null, { status: 200, headers: corsHeaders });
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    try {
        const body = await req.json().catch(() => ({}));
        const prompt = String(body?.prompt ?? "").trim();
        const priceRules = Array.isArray(body?.priceRules) ? body.priceRules : [];
        const language = String(body?.language ?? "en").trim(); // "ru" or "en"

        if (!prompt) throw new Error("prompt is required");

        const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
        if (!OPENAI_API_KEY) throw new Error("OPENAI_API_KEY missing");

        const rulesText = priceRules.length > 0
            ? `COMPANY PRICE RULES (use these first):\n${priceRules.map((r: any) =>
                `- ${r.displayName ?? r.display_name}: $${r.baseRate ?? r.base_rate} per ${r.unit}, aliases: ${(r.aliases ?? []).join(", ")}`
            ).join("\n")}`
            : "No company price rules — use North American market rates.";

        const replyLang = language === "ru"
            ? "Reply in Russian. Be natural and friendly, not robotic."
            : "Reply in English. Be natural and friendly, not robotic.";

        const systemPrompt = `You are WorkIO — a smart assistant for a construction and home services company.
Your job: understand what the admin needs, calculate the price, and respond naturally.

${rulesText}

Market rates fallback (use when no rule matches):
- Outlet replacement: $95/each
- Sink installation: $280 fixed
- Toilet installation: $200 fixed  
- Dishwasher install: $250 fixed
- Washer replacement: $150 fixed
- Dryer replacement: $150 fixed
- Painting: $1.80/sqft
- Flooring: $5.00/sqft
- Drywall: $2.00/sqft
- Plumbing call: $200 fixed
- Electrical call: $200 fixed
- General handyman: $95/hour

Rules:
- Understand ANY language: English, Russian, transliteration (zamenit=replace, ustanovit=install, srochno=urgent), Uzbek, French, mixed
- Fix typos and understand context automatically — NEVER ask for clarification on obvious requests
- If urgent (srochno/rush/urgent) add rush fee: $90 per visit
- Only ask ONE clarifying question if something is truly impossible to price without it (e.g. sqft for painting)
- For everything else — just calculate and respond

Response format — return JSON:
{
  "type": "quote" | "question",
  "message": "your friendly message to admin",
  "jobs": [
    {
      "title": "Service name",
      "quantity": 1,
      "unitPrice": 150,
      "lineTotal": 150,
      "unit": "fixed",
      "isMarketRate": true/false,
      "iconKey": "washer/dryer/outlet/sink/toilet/dishwasher/painting/flooring/plumbing/electrical/handyman/rush"
    }
  ],
  "subtotal": 300,
  "tax": 39,
  "taxRate": 0.13,
  "total": 339,
  "currency": "CAD",
  "needsSaving": true/false
}

- type="quote": you have enough info, calculated the price
- type="question": need ONE missing detail to calculate (only for truly ambiguous cases like sqft)
- needsSaving=true when you used market rates (no company rule matched)
- message: short, friendly, natural. Examples:
  - "Got it! Here's the breakdown 👇"
  - "Понял! Вот расчёт 👇"
  - "Washer + dryer install, urgent — $435 CAD total. Send to Mike?"
  - "Стиралка + сушилка срочно — $435 CAD. Отправить Майку?"
- Always include tax in total
- Return ONLY valid JSON, no markdown`;

        const response = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${OPENAI_API_KEY}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                model: "gpt-4o",
                messages: [
                    { role: "system", content: systemPrompt },
                    { role: "user", content: prompt },
                ],
                response_format: { type: "json_object" },
                temperature: 0.2,
            }),
        });

        const data = await response.json();

        if (!response.ok) {
            throw new Error(data?.error?.message ?? "OpenAI error");
        }

        const content = data?.choices?.[0]?.message?.content;
        if (!content) throw new Error("Empty response from AI");

        const parsed = JSON.parse(content);
        return json(parsed);

    } catch (e) {
        return json({ error: e instanceof Error ? e.message : String(e) }, 400);
    }
});