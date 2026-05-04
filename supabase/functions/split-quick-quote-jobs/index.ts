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

function normalizeText(value: unknown) {
    return cleanString(value).replace(/\s+/g, " ").trim();
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

        const prompt = normalizeText(body?.prompt);

        if (!prompt) {
            throw new Error("prompt is required");
        }

        const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
        if (!OPENAI_API_KEY) {
            throw new Error("OPENAI_API_KEY is missing");
        }

        const schema = {
            name: "quick_quote_jobs_split",
            schema: {
                type: "object",
                additionalProperties: false,
                properties: {
                    isMultiJob: { type: "boolean" },
                    jobs: {
                        type: "array",
                        items: {
                            type: "object",
                            additionalProperties: false,
                            properties: {
                                description: { type: "string" },
                                categoryHint: { type: ["string", "null"] },
                                quantityHint: { type: ["number", "null"] },
                                materialHint: { type: ["string", "null"] },
                                urgencyHint: { type: ["string", "null"] },
                            },
                            required: [
                                "description",
                                "categoryHint",
                                "quantityHint",
                                "materialHint",
                                "urgencyHint"
                            ],
                        },
                    },
                    needsClarification: { type: "boolean" },
                    clarifyingQuestion: { type: "string" },
                    reasoning: { type: "string" },
                },
                required: [
                    "isMultiJob",
                    "jobs",
                    "needsClarification",
                    "clarifyingQuestion",
                    "reasoning"
                ],
            },
            strict: true,
        };

        const systemPrompt = `
You split a Workio quick quote prompt into separate service jobs.

Your job:
- Split one admin prompt into separate jobs when it clearly contains multiple different tasks.
- Do NOT choose Price Rules.
- Do NOT calculate prices.
- Do NOT create estimate items.
- Do NOT add tax.
- Do NOT invent work.
- Return strict JSON only.

Important:
- Keep each job description practical and self-contained.
- Preserve quantity, materials, labor-only, customer-provided materials, and urgency if they belong to that job.
- If urgency applies to the whole prompt, include it in every job description.
- If materials apply to one specific job, keep them only with that job.
- If materials apply globally and it is clear, include them where useful.
- If the prompt has one job only, return exactly one job.
- If the prompt contains multiple tasks in different trades/categories, split them.
- If the prompt contains multiple tasks in the same category but different services, split them.
- If the prompt is ambiguous and splitting could cause wrong pricing, set needsClarification=true.
- Do not split one simple task into many tiny steps.
- Do not split materials into separate jobs.
- Do not split prep/rush/travel into separate jobs.
- Never drop a task from the original prompt.
- If the prompt contains several verb-object tasks, each task must become its own job.
- Repeated verbs still count as separate jobs when they point to different objects.
- Example: "install toilet, install dishwasher" means two jobs, not one.
- If the prompt is written in Russian, Russian Latin transliteration, Uzbek, French, or mixed language, still split every task and return job descriptions in clear English.
- Preserve every mentioned service item.
- Do not merge two different objects into one job just because they share the same action.
- If the prompt says materials are included only for a specific item/job, attach that material detail ONLY to that matching job.
- If materials mention a quantity and item name, match them to the job with the same item/object.
- Do not drop material prices when splitting jobs.
- Preserve material unit price wording such as "$25 each", "$25 per item", or "total $50".
- Example: "materials included only for 2 outlets at $25 each" must stay inside the outlet job, not toilet or dishwasher.
- If materials are explicitly not included for other jobs, add "Materials not included" to those jobs.

Examples:

Input:
u klienta neskolko rabot, nado 2 razetki zamenit, ustanovit tualet, ustanovit posudamoyku. materiali vklyucheny tolko dlya 2 razetki 25$ kajdiy. rabota ne srochnaya.

Output jobs:
1. Replace 2 outlets. Materials included: 2 outlets at $25 each. Not urgent.
2. Install toilet. Materials not included. Not urgent.
3. Install dishwasher. Materials not included. Not urgent.

Input:
replace 2 outlets, install toilet, install dishwasher. materials included only for 2 outlets at $25 each. not urgent.

Output jobs:
1. Replace 2 outlets. Materials included: 2 outlets at $25 each. Not urgent.
2. Install toilet. Materials not included. Not urgent.
3. Install dishwasher. Materials not included. Not urgent.

Input:
Replace 2 outlets and fix sink leak.
Output jobs:
1. Replace 2 outlets.
2. Fix sink leak.

Input:
Paint 2 rooms and repair drywall hole.
Output jobs:
1. Paint 2 rooms.
2. Repair drywall hole.

Input:
Remove old furniture and demo small wall.
Output jobs:
1. Remove old furniture.
2. Demolish small wall.

Input:
Replace 2 outlets. Materials included: 2 outlets at $15 each. Urgent.
Output jobs:
1. Replace 2 outlets. Materials included: 2 outlets at $15 each. Urgent.

Input:
Fix outlet and sink, materials 30
Output:
needsClarification=true
clarifyingQuestion="Does the $30 materials cost apply to the outlet, the sink, or both?"
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

        const jobs = Array.isArray(parsed.jobs)
            ? parsed.jobs
                .map((job: Record<string, unknown>) => ({
                    description: normalizeText(job.description),
                    categoryHint: normalizeText(job.categoryHint) || null,
                    quantityHint: Number.isFinite(Number(job.quantityHint))
                        ? Number(job.quantityHint)
                        : null,
                    materialHint: normalizeText(job.materialHint) || null,
                    urgencyHint: normalizeText(job.urgencyHint) || null,
                }))
                .filter((job: Record<string, unknown>) =>
                    cleanString(job.description).length > 0
                )
            : [];

        return json({
            isMultiJob: jobs.length > 1,
            jobs: jobs.length > 0
                ? jobs
                : [
                    {
                        description: prompt,
                        categoryHint: null,
                        quantityHint: null,
                        materialHint: null,
                        urgencyHint: null,
                    },
                ],
            needsClarification: parsed.needsClarification === true,
            clarifyingQuestion: normalizeText(parsed.clarifyingQuestion),
            reasoning: normalizeText(parsed.reasoning),
        });
    } catch (e) {
        return json(
            { error: e instanceof Error ? e.message : String(e) },
            400,
        );
    }
});