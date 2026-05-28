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

interface ItemAnalysis {
    distinctTaskCount: number;
    distinctTaskTitles: string[];
    auxiliaryCount: number;
    auxiliaryTitles: string[];
}

// Identify auxiliary line items (materials, rush fees, service charges) so they
// are not counted as separate work tasks for multi-task detection.
function isAuxiliaryLine(title: string): boolean {
    const t = title.toLowerCase();
    if (!t) return true;
    if (/(^|\s)materials?(\s|$)/.test(t)) return true;
    if (/\brush\s*fee\b/.test(t)) return true;
    if (/\b(service|trip|travel|booking|admin|cancellation|emergency|after.?hours?)\s+(fee|charge|surcharge)\b/.test(t)) return true;
    if (/\b(disposal|haul.?away|dump)\s+(fee|charge)\b/.test(t)) return true;
    return false;
}

function analyzeItems(items: Item[]): ItemAnalysis {
    const seenTasks = new Set<string>();
    const taskTitles: string[] = [];
    const auxiliaryTitles: string[] = [];
    for (const it of items) {
        const title = cleanString(it.title);
        const lower = title.toLowerCase();
        if (!lower) continue;
        if (isAuxiliaryLine(title)) {
            auxiliaryTitles.push(title);
            continue;
        }
        if (!seenTasks.has(lower)) {
            seenTasks.add(lower);
            taskTitles.push(title);
        }
    }
    return {
        distinctTaskCount: seenTasks.size,
        distinctTaskTitles: taskTitles,
        auxiliaryCount: auxiliaryTitles.length,
        auxiliaryTitles,
    };
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

        const locationContext = cleanString(body?.locationContext);
        const objectContext = cleanString(body?.objectContext);
        const tradeHints: string[] = Array.isArray(body?.tradeHints)
            ? body.tradeHints.map(cleanString).filter(Boolean)
            : [];

        // Multi-task analysis
        const analysis = analyzeItems(items);
        const isMultiTask = analysis.distinctTaskCount >= 2;

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
RULE 4: MULTI-TASK ESTIMATES (CRITICAL — READ CAREFULLY)
═══════════════════════════════════════════════════════════

If the user prompt contains MULTI-TASK: YES, this estimate covers MULTIPLE DISTINCT JOBS.

In multi-task estimates the DISTINCT WORK TASKS list is the AUTHORITATIVE scope. The SERVICE
and TRADE CATEGORY fields describe ONLY the primary trade context — they are NOT the full job.

──── TITLE OVERRIDE (multi-task only) ────────────────────

When MULTI-TASK is YES, IGNORE the SERVICE field for title purposes. Do NOT title the estimate
after a single one of the line items.

Choose ONE of these multi-task title patterns:

A) When all distinct tasks are within the SAME trade:
   "{Trade} Service Package • {City}"
   Example: "Electrical Service Package • Montreal" (for 3 outlet jobs + 1 panel inspection)

B) When distinct tasks span MULTIPLE trades:
   "{Trade A} & {Trade B} Service • {City}" (for exactly 2 trades)
   "Multi-Trade Service • {City}" (for 3+ trades)
   Example: "Plumbing & Electrical Service • Laval"
   Example: "Multi-Trade Service • Montreal" (paint + appliance + electrical + plumbing)

C) When the prompt clearly reads like a punch list / move-in / renovation:
   "Renovation Punch List • {City}"
   "Move-In Service Bundle • {City}"

NEVER title a multi-task job with a single line item's name (e.g. "Faucet Repair" on a 5-task job
is a HARD FAIL — regenerate the title).

──── SCOPE OF WORK (multi-task only) ─────────────────────

scope_of_work MUST give task-specific detail for EACH distinct task. NOT a generic closing line
like "each task will be executed following standard procedures" — that is FILLER and a HARD FAIL.

Instead, for each distinct task, name a concrete trade-specific action: surface prep, leveling,
hookup type, circuit/breaker handling, leak testing, fixture securing, finish step, etc.

❌ WRONG (generic filler at end):
"The project encompasses painting the balcony, installation of a washing machine, installation
of a microwave, replacement of two burnt outlets, and replacement of the bathroom faucet. Each
task will be executed following standard procedures and ensuring compliance with applicable codes."
⤷ The last sentence is filler. Every word in scope must add specific detail.

✅ CORRECT (task-specific details):
"Painting will include surface prep, masking of adjacent areas, and finish coats applied to the
balcony surface. The washing machine will be leveled, connected to the supply line and standpipe
drain, and run-tested. The microwave will be mounted above the stove using the manufacturer
template and connected to the existing circuit. Two burnt kitchen receptacles will be replaced
with GFCI-protected units per local code, with circuit verification. The bathroom faucet will be
removed, supply lines reused, and the new client-supplied unit installed with leak testing under
pressure."

──── INCLUSIONS (multi-task only) ────────────────────────

At least one inclusion line per distinct task, written in trade-specific language. Aim for
8-12 inclusions total on a 4-5 task job. Code-required items (GFCI, AFCI, P-traps) count as
additional inclusions, not substitutes for the per-task line.

──── EXCLUSIONS (multi-task only) ────────────────────────

Must cover ALL trades present. At least one exclusion per trade category:
- Painting present → "Paint beyond the specified surface area" + "Repair of drywall cracks or holes prior to paint"
- Appliance install present → "Supply of appliances" + "Modifications to cabinetry, countertops, or vent ducting"
- Electrical present → "Panel or service upgrades not specified in scope" + "Concealed wiring repairs"
- Plumbing present → "Supply of fixtures" + "Repair of corroded supply lines or shutoff valves"

──── ASSUMPTIONS (multi-task only) ───────────────────────

Assumptions MUST be split PER TRADE. Do NOT combine multiple trades into one assumption line.

❌ WRONG (combined trades into one line):
- "Existing electrical and plumbing systems are up to code and fully functional"

✅ CORRECT (separate lines per trade):
- "Existing electrical service and circuits are to local code and have available capacity"
- "Existing plumbing supply and drain connections are to local code and leak-free"
- "Surfaces designated for paint are sound, clean, and free of major defects"
- "Appliances and fixtures will be on-site and accessible before the scheduled visit"
- "Work areas will be cleared and accessible at the scheduled time"

──── NOTES (multi-task only) ─────────────────────────────

notes MUST explicitly state the multi-trade nature of the job. Mention which trades are involved
and any client-supplied items (paint, fixtures, appliances) the client must have on-site.

If RUSH is yes, mention that expedited scheduling fees apply per task / line.

──── FINAL VALIDATION (multi-task only) ──────────────────

Before returning, verify:
- scope_of_work mentions EVERY distinct task by name with a trade-specific verb. If any task is
  missing or only referenced generically, REGENERATE the scope.
- inclusions contains ≥1 line per distinct task.
- assumptions has separate lines per trade present.
- title uses one of the multi-task patterns above, NOT a single task name.
- No filler sentences like "each task will be executed following standard procedures".

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
- Plumbing: shutoff valve, supply line, P-trap, vent stack, fixture, rough-in, PEX, copper, drain, standpipe
- HVAC: refrigerant, condenser, evaporator, BTU, ductwork, return air, supply plenum
- Appliances: leveling, hardwiring, water connection, dedicated circuit, manufacturer template
- Painting: surface prep, priming, finish coat, cut-in, masking, sheen

═══════════════════════════════════════════════════════════
INFERENCE CONTEXT
═══════════════════════════════════════════════════════════

When LOCATION or OBJECT context is provided, apply local code requirements naturally:
- Determine the correct standard based on CITY (CSA in Canada, NEC in USA, BS in UK, etc.)
- Add code-required items to INCLUSIONS naturally without quoting the trade hints verbatim
- Example: location=kitchen + object=outlet → inclusion: "GFCI-protected receptacles per local electrical code"

TRADE HINTS are internal guidance — translate them into professional inclusions/assumptions, don't paste them.

═══════════════════════════════════════════════════════════
LENGTH GUIDELINES
═══════════════════════════════════════════════════════════

- Small task (1-3 items): scope 1-2 sentences, 3-5 inclusions, 2-4 exclusions
- Medium job (4-6 items OR multi-task): scope 3-5 sentences, 6-9 inclusions, 4-6 exclusions
- Complex job (7+ items OR multi-trade): scope 5-8 sentences, 8-12 inclusions, 6-9 exclusions

Never pad. Never repeat the same idea in different words. On multi-task jobs, length comes
from genuinely covering every line item with trade-specific detail, not from filler.

═══════════════════════════════════════════════════════════
INCLUSIONS (general guidance)
═══════════════════════════════════════════════════════════

- Specific to THIS exact job, not generic
- Code-required items (GFCI for kitchen/bath, AFCI for bedrooms, P-traps under sinks)
- Trade-specific testing (load test, leak test, pressure test, functional verification)
- Disposal of removed materials when applicable
- NEVER list "materials included" when MATERIALS MODE is labor_only

═══════════════════════════════════════════════════════════
EXCLUSIONS (general guidance)
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
ASSUMPTIONS (general guidance)
═══════════════════════════════════════════════════════════

- Existing systems are to code unless otherwise noted
- Accessible work areas, no demo required
- Standard business hours unless rush
- Specific to the job

═══════════════════════════════════════════════════════════
TITLE FORMAT (single-task — see RULE 4 for multi-task)
═══════════════════════════════════════════════════════════

SINGLE-TASK estimates: "{Action} {Object}" + " • {City}" if city provided
- install → "Installation"
- replace → "Replacement"
- repair → "Repair"
- diagnostic → "Diagnostic"

Examples:
✅ "Outlet Replacement • Montreal"
✅ "Dishwasher Installation • Laval"
✅ "Faucet Repair"

NEVER use "Service" alone in a single-task title if action is clear.

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

1. Banned pronouns ("we", "our", "I", "you") in scope_of_work or notes? → REWRITE in passive voice.
2. Does scope_of_work or notes START with the title or city name? → REMOVE that opening.
3. Claims materials are included when MATERIALS MODE is labor_only? → CORRECT.
4. Every inclusion/exclusion specific to THIS job? → If generic, REWRITE.
5. Single-task title uses a specific action word ("Installation"/"Replacement"/"Repair") not "Service"? → FIX.
6. MULTI-TASK = YES — does scope mention EVERY distinct task with a trade-specific verb? → If any missing or only generically referenced, REGENERATE scope.
7. MULTI-TASK = YES — does title use a multi-task pattern from RULE 4, not a single task name? → CHANGE.
8. MULTI-TASK = YES — are assumptions split per trade (no combined "electrical and plumbing" lines)? → SPLIT them.
9. MULTI-TASK = YES — any filler sentence like "each task will be executed following standard procedures"? → DELETE and add real per-task detail instead.

Return strict JSON matching the schema. No markdown, no comments outside JSON.
`.trim();

        const taskListBlock = analysis.distinctTaskTitles.length > 0
            ? analysis.distinctTaskTitles.map((t, i) => `  ${i + 1}. ${t}`).join("\n")
            : "  (none detected)";

        const userPrompt = `
TRADE CATEGORY: ${tradeCategory || "general"}
SERVICE: ${serviceLabel || "Service"}${isMultiTask ? " (PRIMARY TRADE ONLY — see DISTINCT WORK TASKS for full scope; ignore for title)" : ""}
INTENT: ${intent || "service"}
MATERIALS MODE: ${materialsMode || "unknown"}
RUSH: ${hasRush ? "yes — expedited scheduling (mention rush fees apply per task in notes if multi-task)" : "no — standard scheduling"}
MULTI-TASK: ${isMultiTask ? "YES" : "no"}

${isMultiTask ? `DISTINCT WORK TASKS (${analysis.distinctTaskCount} — every one MUST appear in scope, inclusions, etc.):
${taskListBlock}

AUXILIARY LINES: ${analysis.auxiliaryCount} (rush fees, materials, service charges — these are NOT separate tasks, do not list them in inclusions as standalone work).
` : ""}
LINE ITEMS (do not repeat dollar amounts in your output text):
${itemsBlock}

${clientName ? `CLIENT: ${clientName}` : ""}
${propertyAddress ? `PROPERTY: ${propertyAddress}${propertyCity ? ", " + propertyCity : ""}` : ""}
${propertyCity ? `CITY (use in title): ${propertyCity}` : ""}

${originalPrompt ? `ORIGINAL ADMIN PROMPT (may be in any language):\n${originalPrompt}` : ""}

${historyHints.length > 0 ? `HISTORY HINTS (subtle context, no prices in output):\n${historyHints.map((h) => `- ${h}`).join("\n")}` : ""}

${locationContext ? `WORK LOCATION: ${locationContext}` : ""}
${objectContext ? `WORK OBJECT: ${objectContext}` : ""}
${tradeHints.length > 0 ? `TRADE-SPECIFIC HINTS (apply naturally in inclusions, use the local code standard for the city):\n${tradeHints.map((h) => `- ${h}`).join("\n")}` : ""}

Generate the estimate content. Remember: zero templates, write fresh for this specific job.${isMultiTask ? " This is a MULTI-TASK job — every distinct task above must be reflected in scope (with a trade-specific verb), inclusions, exclusions, assumptions (split per trade), and notes. Title must use a multi-task pattern, NOT a single task name." : ""}
`.trim();

        const response = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${OPENAI_API_KEY}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                model: "gpt-4o",
                temperature: 0.4,
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