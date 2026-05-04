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

        if (!prompt) {
            throw new Error("prompt is required");
        }

        const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
        if (!OPENAI_API_KEY) {
            throw new Error("OPENAI_API_KEY is missing");
        }

        const schema = {
            name: "quick_quote_prompt_normalization",
            schema: {
                type: "object",
                additionalProperties: false,
                properties: {
                    cleanPrompt: { type: "string" },
                    needsClarification: { type: "boolean" },
                    clarifyingQuestion: { type: "string" },
                    clarificationType: { type: "string" },
                    confidence: { type: "number" },
                    reasoning: { type: "string" }
                },
                required: [
                    "cleanPrompt",
                    "needsClarification",
                    "clarifyingQuestion",
                    "clarificationType",
                    "confidence",
                    "reasoning"
                ],
            },
            strict: true,
        };

        const systemPrompt = `
You normalize messy quick quote prompts for Workio.

Your job:
- Fix spelling mistakes.
- Fix broken word order.
- Understand prompts written in English, Russian, Russian written with Latin letters, Uzbek, Uzbek/Russian mixed wording, French, or mixed language.
- Normalize the request into clear professional English.
- Normalize materials wording.
- Normalize quantity and price wording.
- Keep the same meaning.
- Do NOT invent prices.
- Do NOT invent quantities.
- Do NOT choose a Price Rule.
- Do NOT calculate totals.
- Do NOT add tax.
- Do NOT create estimate items.
- Return strict JSON only.

Rules:
- If the admin writes messy text, clean it silently.
- The admin may write in different languages or transliteration.
- If the prompt is Russian, Uzbek, French, or Latin-letter Russian/Uzbek, translate it into clear English.
- Examples of Latin-letter Russian/Uzbek include: zameni, rozetki, ustanovi, posudamoyka, rakovina, srochno, materiali vklyucheny, almashtir, o'rnatish.
- Do not keep the final cleanPrompt in Russian, Uzbek, or French. The cleanPrompt must be English.
- Preserve the original meaning, quantity, materials, labor-only status, urgency, and exclusions.
- Do not guess a trade or service if the meaning is unclear.
- Correct common spelling mistakes, abbreviations, misspellings, transliteration, and broken word order without changing the service meaning.
- If the prompt clearly means "2 outlets $15 each", write "Materials included: 2 outlets at $15 each."
- If the prompt clearly means total material cost, write "Materials included: total materials cost $X."
- If quantity and price are present but it is unclear whether price is each or total, set needsClarification=true.
- Always return clarificationType.
- clarificationType must be one of:
  - "material_price" when asking if a price is each item or total materials cost.
  - "materials_mode" when asking whether materials are included, customer provides materials, or labor-only.
  - "generic" for any other clarification.
- If needsClarification=false, use clarificationType="generic".
- If meaning is clear enough, needsClarification=false.
- Keep cleanPrompt short and practical.
- Preserve urgency words like urgent, rush, same day.
- Preserve labor only / customer provides materials / materials included.
Correct common spelling mistakes, abbreviations, misspellings, and broken word order without changing the service meaning.
- If the prompt is already clean, return it improved only slightly.
- Never shame the admin or mention spelling mistakes.


Examples:

Input:
zameni 3 rozetki i ustanovi posudamoyku, srochno, materiali tolko dlya rozetok
Output cleanPrompt:
Replace 3 outlets and install dishwasher. Urgent. Materials included only for the outlets.

Input:
замени старую треснутую раковину, материалы не включены
Output cleanPrompt:
Replace old cracked sink. Materials not included.

Input:
3 ta rozetkani almashtir, material bor, shoshilinch
Output cleanPrompt:
Replace 3 outlets. Materials included. Urgent.

Input:
installer lave-vaisselle, matériaux non inclus
Output cleanPrompt:
Install dishwasher. Materials not included.

Input:
replase 2 oulets 15 each urgent
Output cleanPrompt:
Replace 2 outlets. Materials included: 2 outlets at $15 each. Urgent.

Input:
outlet 2 15
Output:
needsClarification=true
clarificationType="material_price"
clarifyingQuestion="$15 is per outlet or total materials cost?"

Input:
fix sink labor only
Output cleanPrompt:
Fix sink. Labor only.

Input:
customer has parts replace 3 switches
Output cleanPrompt:
Replace 3 switches. Customer provides materials.
`.trim();

        const userPrompt = `Admin prompt:\n${prompt}`;

        const response = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${OPENAI_API_KEY}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                model: "gpt-5-mini",
                messages: [
                    {
                        role: "developer",
                        content: systemPrompt,
                    },
                    {
                        role: "user",
                        content: userPrompt,
                    },
                ],
                response_format: {
                    type: "json_schema",
                    json_schema: schema,
                },
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

        return json({
            cleanPrompt: cleanString(parsed.cleanPrompt) || prompt,
            needsClarification: parsed.needsClarification === true,
            clarifyingQuestion: cleanString(parsed.clarifyingQuestion),
            clarificationType: cleanString(parsed.clarificationType) || "generic",
            confidence: Number.isFinite(Number(parsed.confidence))
                ? Number(parsed.confidence)
                : 0,
            reasoning: cleanString(parsed.reasoning),
        });
    } catch (e) {
        return json(
            { error: e instanceof Error ? e.message : String(e) },
            400,
        );
    }
});