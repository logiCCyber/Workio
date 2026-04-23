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

type RuleIntent = "repair" | "installation" | "replacement" | "inspection" | "broad";

function normalizeText(value: unknown): string {
    return cleanString(value).replace(/\s+/g, " ").trim();
}

function toTitleCase(value: string): string {
    return normalizeText(value)
        .split(/\s+/)
        .filter(Boolean)
        .map((part) => part.charAt(0).toUpperCase() + part.slice(1).toLowerCase())
        .join(" ");
}

function detectIntent(serviceType: string, displayName: string): RuleIntent {
    const text = `${serviceType} ${displayName}`.toLowerCase();

    if (/\b(repair|fix|issue|fault|leak|troubleshoot|service call)\b/.test(text)) {
        return "repair";
    }

    if (/\b(replace|replacement|swap)\b/.test(text)) {
        return "replacement";
    }

    if (/\b(install|installation|mount|mounted)\b/.test(text)) {
        return "installation";
    }

    if (/\b(inspection|inspect|diagnostic|diagnostics|troubleshooting)\b/.test(text)) {
        return "inspection";
    }

    return "broad";
}

function isSizeBasedUnit(unit: string): boolean {
    return unit === "sqft" || unit === "room";
}

function isNonSizeUnit(unit: string): boolean {
    return unit === "fixed" || unit === "item" || unit === "hour";
}

function sanitizeAliases(
    value: unknown,
    {
        serviceType,
        displayName,
        intent,
    }: {
        serviceType: string;
        displayName: string;
        intent: RuleIntent;
    },
): string[] {
    const raw = toStringArray(value);

    const bannedGeneric = new Set([
        "work",
        "job",
        "service",
        "help",
    ]);

    const bannedInflated = [
        "full renovation",
        "renovation",
        "remodel",
        "fit-out",
        "new build",
        "full install",
    ];

    const result: string[] = [];
    const seen = new Set<string>();

    for (const item of raw) {
        const text = normalizeText(item).toLowerCase();
        if (!text) continue;
        if (bannedGeneric.has(text)) continue;

        if (intent === "repair") {
            if (/(install|installation|remodel|renovation|fit-out|new build)/i.test(text)) {
                continue;
            }
        }

        if (intent === "installation") {
            if (/(repair|fault repair|issue repair|troubleshooting repair)/i.test(text)) {
                continue;
            }
        }

        if (intent === "broad") {
            if (bannedInflated.some((part) => text.includes(part))) {
                continue;
            }
        }

        if (seen.has(text)) continue;
        seen.add(text);
        result.push(text);
    }

    const preferred = [
        normalizeText(displayName).toLowerCase(),
        normalizeText(serviceType).toLowerCase(),
    ].filter(Boolean);

    for (const item of preferred) {
        if (!seen.has(item)) {
            seen.add(item);
            result.unshift(item);
        }
    }

    return result.slice(0, 8);
}

function sanitizeKeywords(
    value: unknown,
    {
        intent,
    }: {
        intent: RuleIntent;
    },
): string[] {
    const raw = toStringArray(value);
    const result: string[] = [];
    const seen = new Set<string>();

    for (const item of raw) {
        const text = normalizeText(item).toLowerCase();
        if (!text) continue;

        if (/(work|job|service|help)/i.test(text)) continue;

        if (intent === "repair" && /(install|installation|renovation|remodel)/i.test(text)) {
            continue;
        }

        if (intent === "installation" && /(repair|fault|issue repair)/i.test(text)) {
            continue;
        }

        if (seen.has(text)) continue;
        seen.add(text);
        result.push(text);
    }

    return result.slice(0, 8);
}

function buildScopeFallback(unit: string): string {
    if (unit === "sqft") {
        return "Complete the requested {service_label} work. Estimated project size: {sqft} sqft. {materials}. {prep}. Final cleanup upon completion.";
    }

    if (unit === "room") {
        return "Complete the requested {service_label} work. Estimated project size: {rooms} room(s). {materials}. {prep}. Final cleanup upon completion.";
    }

    return "Complete the requested {service_label} work. {materials}. {prep}. Final cleanup upon completion.";
}

function sanitizeScopeTemplate(
    value: unknown,
    {
        unit,
        intent,
    }: {
        unit: string;
        intent: RuleIntent;
    },
): string {
    let text = normalizeText(value);

    if (isNonSizeUnit(unit)) {
        text = text
            .replace(/Estimated project size:\s*\{sqft\}\s*sqft\s*or\s*\{rooms\}\s*room\(s\)\.\s*/gi, "")
            .replace(/Estimated project size:\s*\{sqft\}\s*sqft\.\s*/gi, "")
            .replace(/Estimated project size:\s*\{rooms\}\s*room\(s\)\.\s*/gi, "");
    }

    if (intent === "repair") {
        text = text
            .replace(/\bfixture installation\b/gi, "fixture repair or replacement")
            .replace(/\brough-in plumbing\b/gi, "necessary repair work")
            .replace(/\btiling and waterproofing\b/gi, "related finishing repairs")
            .replace(/\btrim and finishes\b/gi, "required finishing work");

        text = text.replace(/\binstallation\b/gi, "repair");
    }

    if (intent === "broad") {
        text = text
            .replace(/\bfull renovation\b/gi, "")
            .replace(/\bnew build\b/gi, "")
            .replace(/\bfit-out\b/gi, "");
    }

    text = text
        .replace(/\{materials\}(?!\.)/g, "{materials}.")
        .replace(/\{prep\}(?!\.)/g, "{prep}.")
        .replace(/\{rush\}(?!\.)/g, "{rush}.")
        .replace(/\s+\./g, ".")
        .replace(/\.\./g, ".")
        .replace(/\s+/g, " ")
        .trim();

    if (!text) {
        return buildScopeFallback(unit);
    }

    return text;
}

function sanitizeShortTitle(value: unknown, fallback: string): string {
    const text = normalizeText(value);
    if (!text) return fallback;

    const cleaned = text
        .replace(/\b(and consumables|and supplies|materials and consumables)\b/gi, "")
        .replace(/\s+/g, " ")
        .trim();

    return cleaned || fallback;
}

function sanitizeNotesTemplate(value: unknown): string {
    return normalizeText(value)
        .replace(/\.\./g, ".")
        .replace(/\s+/g, " ")
        .trim();
}

function sanitizeFollowupQuestions(
    value: unknown,
    {
        unit,
        intent,
    }: {
        unit: string;
        intent: RuleIntent;
    },
): Array<Record<string, unknown>> {
    if (!Array.isArray(value)) return [];

    const result: Array<Record<string, unknown>> = [];
    const seen = new Set<string>();

    for (const item of value) {
        if (!item || typeof item !== "object") continue;

        const map = item as Record<string, unknown>;
        const key = normalizeText(map.key).toLowerCase();
        const question = normalizeText(map.question);
        const answerType = normalizeText(map.answerType).toLowerCase();
        const hint = normalizeText(map.hint);
        const isRequired = map.isRequired === true;
        const options = Array.isArray(map.options)
            ? map.options.map((opt) => normalizeText(opt)).filter(Boolean)
            : [];

        if (!key || !question || !answerType) continue;
        if (seen.has(key)) continue;

        if (isNonSizeUnit(unit) && /(project_size|sqft|rooms|quantity_rooms)/i.test(key)) {
            continue;
        }

        if (intent === "repair" && /installation/i.test(question)) {
            continue;
        }

        if (answerType !== "text" && answerType !== "single_select") {
            continue;
        }

        seen.add(key);
        result.push({
            key,
            question,
            answerType,
            isRequired,
            options,
            hint,
        });
    }

    return result.slice(0, 4);
}

function sanitizeNormalizedServiceType(
    value: unknown,
    fallback: string,
): string {
    const text = normalizeText(value).toLowerCase();
    return text || fallback.toLowerCase();
}

function sanitizeSuggestedDisplayName(
    value: unknown,
    fallback: string,
): string {
    const text = normalizeText(value);
    if (!text) return toTitleCase(fallback);
    return toTitleCase(text);
}

serve(async (req) => {
    if (req.method === "OPTIONS") {
        return new Response(null, {
            status: 200,
            headers: corsHeaders,
        });
    }

    if (req.method !== "POST") {
        return json({ error: "Method not allowed" }, 405);
    }

    try {
        const body = await req.json().catch(() => ({}));

        const serviceType = cleanString(body?.serviceType).toLowerCase();
        const displayName = cleanString(body?.displayName);
        const category = cleanString(body?.category).toLowerCase() || "main";
        const unit = cleanString(body?.unit).toLowerCase() || "fixed";
        const aliases = toStringArray(body?.aliases);

        if (!serviceType) {
            throw new Error("serviceType is required");
        }

        const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
        if (!OPENAI_API_KEY) {
            throw new Error("OPENAI_API_KEY is missing");
        }

        const prompt = `
You generate AI metadata for ONE service pricing rule in a field-service app.

Return ONLY valid JSON matching the schema.

GOAL:
Generate clean, reusable metadata that helps:
- match estimate prompts,
- build estimate scope/notes,
- label labor/material/prep/rush items,
- ask useful follow-up questions.

GENERAL RULES:
- Do NOT generate prices or rates.
- Do NOT generate markdown.
- Do NOT generate sales copy.
- Use professional estimate wording in English.
- Be practical, short, reusable, and admin-friendly.
- Do NOT over-specialize.
- Do NOT drift into a different service type.
- Respect the exact meaning of the input.
- If input suggests repair, stay with repair.
- If input suggests installation, stay with installation.
- Do NOT silently turn repair into install, or install into remodel, or remodel into renovation.
- Avoid generic junk aliases like: work, job, service, help.
- Avoid broad unrelated aliases.
- Avoid inflated phrases like "full renovation", "fit-out", "new build" unless the serviceType explicitly says that.

SERVICE MEANING RULES:
- serviceType is the main truth.
- displayName is supporting context.
- category helps understand subtype.
- unit strongly affects template style.

UNIT RULES:
- If unit = "fixed", "item", or "hour":
  - do NOT mention {sqft} or {rooms} in aiScopeTemplate unless absolutely necessary.
  - do NOT make project size central.
- If unit = "sqft":
  - it is OK to mention {sqft}.
- If unit = "room":
  - it is OK to mention {rooms}.
- If unit is not size-based, prefer scope text without size placeholders.

PLACEHOLDERS:
Use ONLY these placeholders when truly useful:
{service_type}
{service_label}
{sqft}
{rooms}
{coats}
{materials}
{rush}
{prep}

DO NOT invent any other placeholders.

ALIASES RULES:
- 6 to 10 max.
- Search-friendly.
- Real phrases a client or admin may type.
- Keep them close to the actual service meaning.
- Do NOT include unrelated scope expansion.
- Do NOT include "remodel", "renovation", "new build", "fit-out", "full install" unless the input clearly means that.
- Good aliases are near-synonyms, wording variations, and common search variations.

DISPLAY NAME RULES:
- suggestedDisplayName must be short, clean, and admin-friendly.
- It should look good in UI.
- Prefer title case.
- Do not make it too broad.
- Do not make it too long.

SERVICE TYPE RULES:
- normalizedServiceType should be lowercase.
- Keep it close to the actual service meaning.
- Do not over-expand the scope.
- It should be stable and reusable as the canonical service key.

AI KEYWORDS RULES:
- 6 to 10 max.
- Helpful for prompt matching.
- Short.
- Relevant.
- No junk repetition.
- No broad unrelated construction words.

SCOPE TEMPLATE RULES:
- Must be reusable.
- Must sound like estimate scope.
- Must not be too long.
- Must not force project-size wording for non-size-based rules.
- Must not assume a full renovation if the rule is not for renovation.
- Must not assume rough-in plumbing, tiling, waterproofing, trim, permits, etc. unless the service type clearly implies them.
- Prefer simple structure:
  "Complete the requested {service_label} work. {materials}. {prep}. Final cleanup upon completion."
- Only mention size when unit really depends on size.

NOTES TEMPLATE RULES:
- Reusable.
- Practical.
- Mention hidden conditions / access / final confirmation only if appropriate.
- Avoid bloated renovation language.
- Keep it estimate-friendly.

ITEM LABEL RULES:
- aiLaborTitle should match the service meaning exactly.
- If the service is repair, use repair wording.
- If the service is installation, use installation wording.
- aiLaborDescription should be one short estimate sentence.
- aiMaterialsTitle / Description should be short and practical.
- aiPrepTitle / Description should be short and practical.
- aiRushTitle / Description should be short and practical.

FOLLOW-UP QUESTION RULES:
- 2 to 4 questions max.
- Only ask questions that actually help estimate this rule.
- Prefer broad but useful clarification.
- Do NOT ask nonsense.
- Do NOT ask room/sqft questions for non-size-based fixed/item/hour services unless genuinely needed.
- Do NOT ask materials-selection questions if the service rule itself usually does not require that distinction.
- Good examples:
  - repair vs replacement
  - issue type
  - quantity of fixtures/items
  - access condition
  - site condition
- Keep question text short and clean.
- answerType must be text or single_select.

STYLE EXAMPLES:

If serviceType = "bathroom repair" and unit = "fixed":
- aliases should stay near repair, not renovation.
- labor title should stay near bathroom repair.
- scope should NOT mention {sqft} or {rooms} by default.
- follow-up questions can ask issue type, number of bathrooms, site condition.

If serviceType = "sink installation" and unit = "item":
- aliases should stay near sink install / sink replacement.
- do NOT ask sqft/rooms by default.
- ask quantity or replacement/new install if needed.

If serviceType = "painting" and unit = "sqft":
- it is OK to mention {sqft} and {coats}.

Input:
serviceType: ${serviceType}
displayName: ${displayName || serviceType}
category: ${category}
unit: ${unit}
existingAliases: ${aliases.join(", ")}
`.trim();

        const schema = {
            name: "rule_ai_metadata",
            schema: {
                type: "object",
                additionalProperties: false,
                properties: {
                    normalizedServiceType: { type: "string" },
                    suggestedDisplayName: { type: "string" },
                    aliases: {
                        type: "array",
                        items: { type: "string" },
                    },
                    aiKeywords: {
                        type: "array",
                        items: { type: "string" },
                    },
                    aiScopeTemplate: { type: "string" },
                    aiNotesTemplate: { type: "string" },
                    aiLaborTitle: { type: "string" },
                    aiLaborDescription: { type: "string" },
                    aiMaterialsTitle: { type: "string" },
                    aiMaterialsDescription: { type: "string" },
                    aiPrepTitle: { type: "string" },
                    aiPrepDescription: { type: "string" },
                    aiRushTitle: { type: "string" },
                    aiRushDescription: { type: "string" },
                    aiFollowupQuestions: {
                        type: "array",
                        items: {
                            type: "object",
                            additionalProperties: false,
                            properties: {
                                key: { type: "string" },
                                question: { type: "string" },
                                answerType: { type: "string" },
                                isRequired: { type: "boolean" },
                                options: {
                                    type: "array",
                                    items: { type: "string" },
                                },
                                hint: { type: "string" },
                            },
                            required: [
                                "key",
                                "question",
                                "answerType",
                                "isRequired",
                                "options",
                                "hint",
                            ],
                        },
                    },
                },
                required: [
                    "aliases",
                    "aiKeywords",
                    "aiScopeTemplate",
                    "aiNotesTemplate",
                    "aiLaborTitle",
                    "aiLaborDescription",
                    "aiMaterialsTitle",
                    "aiMaterialsDescription",
                    "aiPrepTitle",
                    "aiPrepDescription",
                    "aiRushTitle",
                    "aiRushDescription",
                    "aiFollowupQuestions",
                    "normalizedServiceType",
                    "suggestedDisplayName",
                ],
            },
            strict: true,
        };

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
                        content:
                            "You generate strict JSON metadata for service rules. No markdown. No explanation.",
                    },
                    {
                        role: "user",
                        content: prompt,
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

        const effectiveDisplayName = displayName || serviceType;
        const intent = detectIntent(serviceType, effectiveDisplayName);

        const result = {
            aliases: sanitizeAliases(parsed.aliases, {
                serviceType,
                displayName: effectiveDisplayName,
                intent,
            }),
            aiKeywords: sanitizeKeywords(parsed.aiKeywords, {
                intent,
            }),
            aiScopeTemplate: sanitizeScopeTemplate(parsed.aiScopeTemplate, {
                unit,
                intent,
            }),
            aiNotesTemplate: sanitizeNotesTemplate(parsed.aiNotesTemplate),
            aiLaborTitle: sanitizeShortTitle(
                parsed.aiLaborTitle,
                `${toTitleCase(effectiveDisplayName)} Labor`,
            ),
            aiLaborDescription: normalizeText(parsed.aiLaborDescription),
            aiMaterialsTitle: sanitizeShortTitle(
                parsed.aiMaterialsTitle,
                `${toTitleCase(serviceType)} Materials`,
            ),
            aiMaterialsDescription: normalizeText(parsed.aiMaterialsDescription),
            aiPrepTitle: sanitizeShortTitle(
                parsed.aiPrepTitle,
                "Site Preparation",
            ),
            aiPrepDescription: normalizeText(parsed.aiPrepDescription),
            aiRushTitle: sanitizeShortTitle(
                parsed.aiRushTitle,
                `Rush ${toTitleCase(serviceType)} Service`,
            ),
            aiRushDescription: normalizeText(parsed.aiRushDescription),
            aiFollowupQuestions: sanitizeFollowupQuestions(parsed.aiFollowupQuestions, {
                unit,
                intent,
            }),
            normalizedServiceType: sanitizeNormalizedServiceType(
                parsed.normalizedServiceType,
                serviceType,
            ),
            suggestedDisplayName: sanitizeSuggestedDisplayName(
                parsed.suggestedDisplayName,
                effectiveDisplayName,
            ),
        };

        return json(result, 200);
    } catch (e) {
        return json(
            { error: e instanceof Error ? e.message : String(e) },
            400,
        );
    }
});