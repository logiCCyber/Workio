import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
    if (req.method === "OPTIONS") {
        return new Response(null, { status: 200, headers: corsHeaders });
    }

    try {
        const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
        if (!OPENAI_API_KEY) throw new Error("Missing OPENAI_API_KEY");

        const body = await req.json();
        const items: { title: string; quantity: number; unitPrice: number; unit: string }[] =
            body.items ?? [];
        const hasRush: boolean = body.hasRush ?? false;
        const hasMaterials: boolean = body.hasMaterials ?? false;
        const clientName: string = body.clientName ?? "";
        const propertyAddress: string = body.propertyAddress ?? "";
        const propertyCity: string = body.propertyCity ?? "";
        const originalPrompt: string = body.originalPrompt ?? "";

        if (items.length === 0) {
            return json({ scope: "", notes: "" });
        }

        const itemLines = items
            .map((i) => `- ${i.title} (qty: ${i.quantity}, unit price: $${i.unitPrice})`)
            .join("\n");

        const systemPrompt = `
You are a professional estimating assistant for a home service business.
Write a Scope of Work and a Notes section for an estimate based on the provided line items.

Rules:
- Always respond in English only.
- Scope: 2-4 sentences. Describe exactly what work will be done, referencing the specific services listed. Be precise and professional. Do NOT use generic phrases like "as described by the client" or "complete the requested work". Use action verbs: install, replace, repair, inspect, remove. Mention materials and rush if applicable.
- Notes: 2-3 sentences. Professional disclaimers about pricing, site conditions, and scope changes. Vary the wording each time — do not repeat the same sentences verbatim.
- Sound like a real contractor wrote it, not a template.
- Do not include markdown, bullets, or headers in your response.
- Return ONLY valid JSON: { "scope": "...", "notes": "..." }
`.trim();

        const userPrompt = `
Line items:
${itemLines}
Rush job: ${hasRush ? "Yes" : "No"}
Materials included: ${hasMaterials ? "Yes" : "No"}
${clientName ? `Client: ${clientName}` : ""}
${propertyAddress ? `Property: ${propertyAddress}${propertyCity ? ", " + propertyCity : ""}` : ""}
${originalPrompt ? `Original job description: ${originalPrompt}` : ""}

Generate a professional scope and notes for this estimate.
`.trim();

        const response = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${OPENAI_API_KEY}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                model: "gpt-4o-mini",
                temperature: 0.7,
                response_format: { type: "json_object" },
                messages: [
                    { role: "system", content: systemPrompt },
                    { role: "user", content: userPrompt },
                ],
            }),
        });

        const data = await response.json();
        const content = data?.choices?.[0]?.message?.content ?? "{}";

        let parsed: { scope?: string; notes?: string } = {};
        try {
            parsed = JSON.parse(content);
        } catch (_) {}

        return json({
            scope: (parsed.scope ?? "").trim(),
            notes: (parsed.notes ?? "").trim(),
        });
    } catch (e) {
        return json({ error: String(e) }, 500);
    }
});

function json(data: unknown, status = 200) {
    return new Response(JSON.stringify(data), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
}