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

serve(async (req) => {
    if (req.method === "OPTIONS") {
        return new Response(null, { status: 200, headers: corsHeaders });
    }

    if (req.method !== "POST") {
        return json({ error: "Method not allowed" }, 405);
    }

    try {
        const body = await req.json().catch(() => ({}));
        const prompt = cleanString(body?.prompt);
        const priceRules = Array.isArray(body?.priceRules) ? body.priceRules : [];

        if (!prompt) return json({ hint: null });
        if (prompt.length < 3) return json({ hint: null });

        const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
        if (!OPENAI_API_KEY) throw new Error("OPENAI_API_KEY is missing");

        const compactRules = priceRules.slice(0, 30).map((r: any) => ({
            displayName: cleanString(r.displayName ?? r.display_name),
            unit: cleanString(r.unit),
            aliases: Array.isArray(r.aliases) ? r.aliases.slice(0, 5).map(cleanString) : [],
        }));

        const systemPrompt = `
You are Workio Coach — a smart assistant that helps admins write better quick quote prompts.

Your job:
- Read the current admin prompt.
- Understand what service they are describing (any language: English, Russian, transliteration, Uzbek, French, mixed).
- Look at the available Price Rules to understand what information is needed.
- Return ONE short helpful hint telling the admin what to add to get a better quote.
- If the prompt already has everything needed, return a positive confirmation.

Rules:
- Return ONLY a JSON object: { "hint": "your hint here" } or { "hint": null } if prompt is too short or unclear.
- Hint must be short — max 8 words.
- Hint must be friendly and natural — never robotic.
- Vary your wording every time — never repeat the same phrase.
- If service is identified but quantity is missing — ask for quantity in a natural way.
- If quantity is there but materials status is unclear — ask about materials.
- If urgency is mentioned and there are clearly 2 or more different service objects in the prompt — ask "Rush fee per job or one visit charge?".
- Do not ask about quantity if multiple different objects are already listed.
- If urgency is mentioned with only one job — no need to ask about rush fee.
- If materials are mentioned with price but urgency not specified — ask about urgency.
- If everything is clear — say something positive and encouraging.
- Never mention specific rule names or technical terms.
- Understand any language but always reply in English.
- If prompt is too vague to understand — return null.

Available Price Rules:
${JSON.stringify(compactRules, null, 2)}
`.trim();

        const response = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${OPENAI_API_KEY}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                model: "gpt-4o-mini",
                messages: [
                    { role: "system", content: systemPrompt },
                    { role: "user", content: `Admin prompt: ${prompt}` },
                ],
                response_format: { type: "json_object" },
                temperature: 0.9,
                max_tokens: 60,
            }),
        });

        const data = await response.json().catch(() => ({}));

        if (!response.ok) {
            return json({ hint: null });
        }

        const content = data?.choices?.[0]?.message?.content;
        if (typeof content !== "string") return json({ hint: null });

        const parsed = JSON.parse(content);
        const hint = cleanString(parsed?.hint ?? '');

        return json({ hint: hint || null });

    } catch (_) {
        return json({ hint: null });
    }
});