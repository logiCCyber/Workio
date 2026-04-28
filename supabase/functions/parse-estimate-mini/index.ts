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

function toNumberOrNull(value: unknown): number | null {
    if (value == null) return null;
    const parsed = Number(String(value).replace(",", "."));
    return Number.isFinite(parsed) ? parsed : null;
}

function toBoolOrNull(value: unknown): boolean | null {
    if (typeof value === "boolean") return value;

    const normalized = cleanString(value).toLowerCase();
    if (!normalized) return null;

    if (["true", "1", "yes", "included"].includes(normalized)) return true;
    if (["false", "0", "no", "excluded"].includes(normalized)) return false;

    return null;
}

function toStringArray(value: unknown): string[] {
    if (!Array.isArray(value)) return [];

    const seen = new Set<string>();
    const result: string[] = [];

    for (const item of value) {
        const text = cleanString(item).toLowerCase();
        if (!text) continue;
        if (seen.has(text)) continue;
        seen.add(text);
        result.push(text);
    }

    return result;
}

function toParsedMaterials(value: unknown): Array<Record<string, unknown>> {
    if (!Array.isArray(value)) return [];

    return value
        .filter((item) => item && typeof item === "object")
        .map((item) => {
            const map = item as Record<string, unknown>;
            return {
                name: cleanString(map.name),
                quantity: toNumberOrNull(map.quantity),
                measure_value: toNumberOrNull(map.measure_value),
                measure_unit: cleanString(map.measure_unit).toLowerCase(),
                unit_price: toNumberOrNull(map.unit_price),
                line_total: toNumberOrNull(map.line_total),
                raw_text: cleanString(map.raw_text),
            };
        })
        .filter((item) => cleanString(item.name).length > 0 || cleanString(item.raw_text).length > 0);
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
        const localParsed =
            body?.localParsed && typeof body.localParsed === "object"
                ? body.localParsed
                : {};

        if (!prompt) {
            throw new Error("prompt is required");
        }

        const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
        if (!OPENAI_API_KEY) {
            throw new Error("OPENAI_API_KEY is missing");
        }

        const input = `
You are a parsing assistant for a field-service estimate system.

Your job:
- Parse messy estimate prompts.
- Improve service type detection.
- Detect whether project size is truly missing.
- Parse detailed material lines.
- Do NOT calculate taxes.
- Do NOT generate pricing totals.
- Do NOT write scope or notes.
- Return only structured JSON.

Rules:
- If the prompt contains "service_type: X", return exactly X as serviceType. Do not translate it, rename it, or replace it with another trade.
- If the prompt contains "service_label: X", use it only as display/context. The serviceType must still come from "service_type" when present.
- If there is no explicit service_type, infer serviceType only when the full prompt clearly describes a service. If unsure, return null.
- Never use a material/product word as serviceType. Materials like sheet, wire, pipe, screw, outlet, paint, tile, board, box, bag are not service types.
- If the local parser likely overfit to one material word, correct it if the full prompt suggests a broader service request.
- If detailed materials are present, parse them carefully.
- If prompt clearly contains a material list, set materialsIncluded=true unless the prompt clearly says labor only, customer provides materials, materials not included, or materials after inspection.
- If prompt says labor only, set laborOnly=true and materialsIncluded=false.
- If prompt says customer provides materials, set laborOnly=false and materialsIncluded=false.
- If prompt says materials/parts after inspection, set laborOnly=false and materialsIncluded=null.
- If prompt contains detailed materials, projectSizeRequired can be false even if sqft/rooms are missing.
- Do NOT calculate prices, taxes, subtotals, totals, discounts, or rates.
- Keep followupHints short and practical.
- Keep reasoningHints short and practical.

Prompt:
${prompt}

Local parsed snapshot:
${JSON.stringify(localParsed, null, 2)}
`.trim();

        const schema = {
            type: "object",
            additionalProperties: false,
            properties: {
                serviceType: { type: ["string", "null"] },
                sqft: { type: ["number", "null"] },
                rooms: { type: ["integer", "null"] },
                hours: { type: ["number", "null"] },
                materialsIncluded: { type: ["boolean", "null"] },
                laborOnly: { type: ["boolean", "null"] },
                projectSizeRequired: { type: "boolean" },
                parsedMaterials: {
                    type: "array",
                    items: {
                        type: "object",
                        additionalProperties: false,
                        properties: {
                            name: { type: "string" },
                            quantity: { type: ["number", "null"] },
                            measure_value: { type: ["number", "null"] },
                            measure_unit: { type: "string" },
                            unit_price: { type: ["number", "null"] },
                            line_total: { type: ["number", "null"] },
                            raw_text: { type: "string" },
                        },
                        required: [
                            "name",
                            "quantity",
                            "measure_value",
                            "measure_unit",
                            "unit_price",
                            "line_total",
                            "raw_text",
                        ],
                    },
                },
                reasoningHints: {
                    type: "array",
                    items: { type: "string" },
                },
                followupHints: {
                    type: "array",
                    items: { type: "string" },
                },
            },
            required: [
                "serviceType",
                "sqft",
                "rooms",
                "hours",
                "materialsIncluded",
                "laborOnly",
                "projectSizeRequired",
                "parsedMaterials",
                "reasoningHints",
                "followupHints",
            ],
        };

        const response = await fetch("https://api.openai.com/v1/responses", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${OPENAI_API_KEY}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                model: "gpt-5.4-nano",
                input: [
                    {
                        role: "developer",
                        content: [
                            {
                                type: "input_text",
                                text: "You parse estimate prompts into strict JSON. No markdown. No extra explanation.",
                            },
                        ],
                    },
                    {
                        role: "user",
                        content: [
                            {
                                type: "input_text",
                                text: input,
                            },
                        ],
                    },
                ],
                text: {
                    format: {
                        type: "json_schema",
                        name: "estimate_mini_parse",
                        strict: true,
                        schema,
                    },
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

        const content =
            data?.output?.[0]?.content?.[0]?.text ??
            data?.output_text ??
            "";

        if (typeof content !== "string" || !content.trim()) {
            throw new Error("Model returned empty content");
        }

        const parsed = JSON.parse(content);

        return json({
            serviceType: cleanString(parsed.serviceType) || null,
            sqft: toNumberOrNull(parsed.sqft),
            rooms: Number.isInteger(parsed.rooms) ? parsed.rooms : (toNumberOrNull(parsed.rooms) != null ? Math.round(Number(parsed.rooms)) : null),
            hours: toNumberOrNull(parsed.hours),
            materialsIncluded: toBoolOrNull(parsed.materialsIncluded),
            laborOnly: toBoolOrNull(parsed.laborOnly),
            projectSizeRequired: parsed.projectSizeRequired === true,
            parsedMaterials: toParsedMaterials(parsed.parsedMaterials),
            reasoningHints: toStringArray(parsed.reasoningHints),
            followupHints: toStringArray(parsed.followupHints),
        });
    } catch (e) {
        return json(
            { error: e instanceof Error ? e.message : String(e) },
            400,
        );
    }
});