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
        headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
}

function cleanString(value: unknown): string {
    return String(value ?? "").trim();
}

function cleanStringArray(value: unknown): string[] {
    if (!Array.isArray(value)) return [];
    const seen = new Set<string>();
    const result: string[] = [];
    for (const item of value) {
        const text = cleanString(item);
        if (!text) continue;
        const key = text.toLowerCase();
        if (seen.has(key)) continue;
        seen.add(key);
        result.push(text);
    }
    return result;
}

interface Item {
    title: string;
    quantity: number;
    unitPrice: number;
    unit: string;
    description?: string;
}

serve(async (req) => {
    if (req.method === "OPTIONS") {
        return new Response(null, { status: 200, headers: corsHeaders });
    }

    if (req.method !== "POST") {
        return json({ error: "Method not allowed" }, 405);
    }

    try {
        const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
        if (!OPENAI_API_KEY) throw new Error("Missing OPENAI_API_KEY");

        const body = await req.json().catch(() => ({}));

        const items: Item[] = Array.isArray(body?.items) ? body.items : [];
        if (items.length === 0) {
            throw new Error("items are required");
        }

        const originalPrompt = cleanString(body?.originalPrompt);
        const tradeCategory = cleanString(body?.tradeCategory); // e.g. "electrical", "plumbing"
        const serviceLabel = cleanString(body?.serviceLabel);   // e.g. "Outlet Replacement"
        const intent = cleanString(body?.intent);               // install | replace | repair | diagnostic | service
        const hasRush = body?.hasRush === true;
        const materialsMode = cleanString(body?.materialsMode); // included | labor_only | customer_provided | unknown
        const clientName = cleanString(body?.clientName);
        const propertyAddress = cleanString(body?.propertyAddress);
        const propertyCity = cleanString(body?.propertyCity);
        const historyHints: string[] = Array.isArray(body?.historyHints)
            ? body.historyHints.map(cleanString).filter(Boolean)
            : [];

        const itemsBlock = items.map((it, idx) => {
            const qty = Number(it.quantity) || 0;
            const price = Number(it.unitPrice) || 0;
            const total = qty * price;
            const desc = cleanString(it.description);
            return `${idx + 1}. ${cleanString(it.title)} — qty: ${qty} ${cleanString(it.unit)}, unit price: $${price.toFixed(2)}, total: $${total.toFixed(2)}${desc ? ` (${desc})` : ""}`;
        }).join("\n");

        const schema = {
            name: "estimate_content_v2",
            schema: {
                type: "object",
                additionalProperties: false,
                properties: {
                    title: { type: "string" },
                    scope_of_work: { type: "string" },
                    inclusions: {
                        type: "array",
                        items: { type: "string" },
                    },
                    exclusions: {
                        type: "array",
                        items: { type: "string" },
                    },
                    assumptions: {
                        type: "array",
                        items: { type: "string" },
                    },
                    notes: { type: "string" },
                    terms: { type: "string" },
                    reasoning: { type: "string" },
                },
                required: [
                    "title",
                    "scope_of_work",
                    "inclusions",
                    "exclusions",
                    "assumptions",
                    "notes",
                    "terms",
                    "reasoning",
                ],
            },
            strict: true,
        };

        const systemPrompt = `
You are a senior tradesperson with 15+ years of hands-on experience writing professional estimates for clients.

═══════════════════════════════════════════════════════════
HARD RULES — VIOLATION = REGENERATE FROM SCRATCH
═══════════════════════════════════════════════════════════

RULE 1: FORMAL VOICE ONLY
Banned words: "we", "we'll", "we will", "we're", "our", "us", "I", "I'll", "you", "your"
Use third-person passive or impersonal constructions.

EXAMPLES:
❌ "We'll replace three outlets."
✅ "Three outlets will be replaced."

❌ "We'll be handling the installation."
✅ "Installation will be performed by a qualified technician."

❌ "Our team will install the unit."
✅ "The unit will be installed."

❌ "We're ensuring proper connections."
✅ "Proper connections will be ensured."

❌ "Our focus will be on alignment."
✅ "Focus will be placed on precise alignment."

❌ "We'll ensure it's connected properly."
✅ "The unit will be properly connected."

If your output contains ANY banned word, you must rewrite that sentence in passive voice before returning.

═══════════════════════════════════════════════════════════
RULE 2: NEVER REPEAT THE TITLE
═══════════════════════════════════════════════════════════

The title appears in its own JSON field. NEVER put it inside scope_of_work or notes.

❌ scope_of_work: "Dishwasher Installation • Montreal\\n\\nThe dishwasher will be installed..."
✅ scope_of_work: "The dishwasher will be installed and connected to existing plumbing..."

❌ notes: "Dishwasher Installation • Montreal\\nThis estimate covers labor only..."
✅ notes: "This estimate covers labor only for the installation. Appliance must be on-site prior to scheduled date."

Start scope_of_work and notes DIRECTLY with the work content. No headers, no titles, no city names at the start.

═══════════════════════════════════════════════════════════
RULE 3: MATERIALS HONESTY
═══════════════════════════════════════════════════════════

Look at the LINE ITEMS provided. They are the source of truth.

MATERIALS MODE determines language:

- "labor_only" → Explicitly state in notes: "Materials are not included in this estimate."
- "included" (with material line items present) → "All required materials are itemized in this estimate."
- "unknown" → Be neutral. Do not claim materials are or aren't included.

NEVER claim "includes all necessary materials" unless material line items are actually present.

If MATERIALS MODE is "labor_only", inclusions must NOT contain any "materials included" entry.

═══════════════════════════════════════════════════════════
TONE
═══════════════════════════════════════════════════════════

- Confident, direct, specific. Like a senior tradesperson writing.
- No corporate fluff, no salesy language.
- No legal CYA inside scope/notes (save legal language for terms).
- Vary phrasing across estimates — zero templates.

═══════════════════════════════════════════════════════════
TRADE-SPECIFIC VOCABULARY
═══════════════════════════════════════════════════════════

Use the actual technical terms of the trade:
- Electrical: circuit, breaker, GFCI, AFCI, receptacle, junction box, load, neutral, ground, CSA standards
- Plumbing: shutoff valve, supply line, P-trap, vent stack, fixture, rough-in, PEX, copper, drain
- HVAC: refrigerant, condenser, evaporator, BTU, ductwork, return air, supply plenum
- Appliances: leveling, hardwiring, water connection, dedicated circuit

═══════════════════════════════════════════════════════════
LENGTH GUIDELINES
═══════════════════════════════════════════════════════════

- Small task (1-3 items): scope 1-2 sentences, 3-5 inclusions, 2-4 exclusions
- Medium job: scope 2-3 sentences, 5-7 inclusions, 3-5 exclusions
- Complex job: scope 3-5 sentences, 7-10 inclusions, 5-8 exclusions

Never pad. Never repeat the same idea in different words.

═══════════════════════════════════════════════════════════
INCLUSIONS (what's covered)
═══════════════════════════════════════════════════════════

- Specific to THIS exact job, not generic
- Code-required items (GFCI for kitchen/bath, AFCI for bedrooms, P-traps under sinks)
- Trade-specific testing (load test, leak test, pressure test, functional verification)
- Disposal of removed materials when applicable
- NEVER list "materials included" when MATERIALS MODE is labor_only

═══════════════════════════════════════════════════════════
EXCLUSIONS (what's NOT covered — protects the business)
═══════════════════════════════════════════════════════════

Common dispute areas. Always include relevant ones:
- Drywall repair beyond standard cut-in (electrical/plumbing)
- Permit fees if municipality requires
- Panel/main service upgrades
- Code upgrades not specified in scope
- Concealed damage discovered during work
- Modifications to cabinetry/countertops (appliance install)
- Anything not explicitly listed in inclusions

═══════════════════════════════════════════════════════════
ASSUMPTIONS (conditions that make pricing valid)
═══════════════════════════════════════════════════════════

- Existing systems are to code unless otherwise noted
- Accessible work areas, no demo required
- Standard business hours unless rush
- Specific to the job

═══════════════════════════════════════════════════════════
TITLE FORMAT
═══════════════════════════════════════════════════════════

"{Action} {Object}" + " • {City}" if city provided

Use action word based on INTENT:
- install → "Installation"
- replace → "Replacement"
- repair → "Repair"
- diagnostic → "Diagnostic"

Examples:
✅ "Outlet Replacement • Montreal"
✅ "Dishwasher Installation • Laval"
✅ "Faucet Repair"

NEVER use "Service" in title if action is clear.

═══════════════════════════════════════════════════════════
PRICING SOURCE
═══════════════════════════════════════════════════════════

Pricing comes from items list. NEVER mention dollar amounts in scope/notes/terms.

═══════════════════════════════════════════════════════════
LANGUAGE
═══════════════════════════════════════════════════════════

Input may be in any language (Russian, French, Uzbek, etc.).
Output is ALWAYS English. No exceptions.

═══════════════════════════════════════════════════════════
FINAL OUTPUT CHECKLIST (verify before returning)
═══════════════════════════════════════════════════════════

1. Does scope_of_work or notes contain "we", "we'll", "our", "us", "I", "you"? → REWRITE in passive voice.
2. Does scope_of_work or notes START with the title or city name? → REMOVE that opening.
3. Does it claim materials are included when MATERIALS MODE is labor_only? → CORRECT.
4. Is every inclusion/exclusion specific to THIS job? → If generic, REWRITE.
5. Does title use a specific action word ("Installation"/"Replacement"/"Repair") not "Service"? → FIX.

Return strict JSON matching the schema. No markdown, no comments outside JSON.
`.trim();

        const userPrompt = `
TRADE CATEGORY: ${tradeCategory || "general"}
SERVICE: ${serviceLabel || "Service"}
INTENT: ${intent || "service"}
MATERIALS MODE: ${materialsMode || "unknown"}
RUSH: ${hasRush ? "yes — expedited scheduling" : "no — standard scheduling"}

LINE ITEMS (do not repeat dollar amounts in your output text):
${itemsBlock}

${clientName ? `CLIENT: ${clientName}` : ""}
${propertyAddress ? `PROPERTY: ${propertyAddress}${propertyCity ? ", " + propertyCity : ""}` : ""}
${propertyCity ? `CITY (use in title): ${propertyCity}` : ""}

${originalPrompt ? `ORIGINAL ADMIN PROMPT (may be in any language):\n${originalPrompt}` : ""}

${historyHints.length > 0 ? `HISTORY HINTS (subtle context, no prices in output):\n${historyHints.map((h) => `- ${h}`).join("\n")}` : ""}

Generate the estimate content. Remember: zero templates, write fresh for this specific job.
`.trim();

        const response = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${OPENAI_API_KEY}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                model: "gpt-4o",
                temperature: 0.5,
                messages: [
                    { role: "system", content: systemPrompt },
                    { role: "user", content: userPrompt },
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
            title: cleanString(parsed.title),
            scopeOfWork: cleanString(parsed.scope_of_work),
            inclusions: cleanStringArray(parsed.inclusions),
            exclusions: cleanStringArray(parsed.exclusions),
            assumptions: cleanStringArray(parsed.assumptions),
            notes: cleanString(parsed.notes),
            terms: cleanString(parsed.terms),
            reasoning: cleanString(parsed.reasoning),
        });
    } catch (e) {
        return json(
            { error: e instanceof Error ? e.message : String(e) },
            400,
        );
    }
});