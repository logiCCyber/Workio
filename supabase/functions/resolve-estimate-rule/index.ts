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

function toStringArray(value: unknown): string[] {
    if (!Array.isArray(value)) return [];
    const seen = new Set<string>();
    const result: string[] = [];

    for (const item of value) {
        const text = normalizeText(item).toLowerCase();
        if (!text) continue;
        if (seen.has(text)) continue;
        seen.add(text);
        result.push(text);
    }

    return result;
}

function clampConfidence(value: unknown): number {
    const num = Number(value);
    if (!Number.isFinite(num)) return 0;
    if (num < 0) return 0;
    if (num > 1) return 1;
    return Number(num.toFixed(2));
}

function sanitizeSuppressQuestionKeys(
    value: unknown,
    candidates: Array<Record<string, unknown>> = [],
): string[] {
    const allowed = new Set([
        "issue_description",
        "requested_work",
        "project_size",
        "materials",
        "materials_detail",
        "quantity_value",
        "work_type",
    ]);

    for (const candidate of candidates) {
        const questions = Array.isArray(candidate.followupQuestions)
            ? candidate.followupQuestions
            : [];

        for (const question of questions) {
            if (!question || typeof question !== "object") continue;

            const key = cleanString((question as Record<string, unknown>).key)
                .toLowerCase();

            if (key) {
                allowed.add(key);
            }
        }
    }

    return toStringArray(value).filter((key) => allowed.has(key));
}

function sanitizeClarifyingQuestion(value: unknown): string {
    return normalizeText(value);
}

function sanitizeNormalizedRequestedWork(value: unknown): string {
    return normalizeText(value);
}

function sanitizeReasoningSummary(value: unknown): string {
    return normalizeText(value);
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

        const prompt = normalizeText(body?.prompt);
        const guidedAnswers =
            body?.guidedAnswers && typeof body.guidedAnswers === "object"
                ? body.guidedAnswers
                : {};

        const candidates = Array.isArray(body?.candidates) ? body.candidates : [];

        if (!prompt) {
            throw new Error("prompt is required");
        }

        if (!candidates.length) {
            return json({
                selectedRuleId: null,
                confidence: 0,
                normalizedRequestedWork: prompt,
                shouldAskClarifyingQuestion: true,
                clarifyingQuestion: "What kind of service do you need?",
                suppressQuestionKeys: [],
                reasoningSummary: "No candidates were provided.",
            });
        }

        const compactCandidates = candidates.slice(0, 6).map((raw: any) => ({
            ruleId: cleanString(raw?.ruleId),
            serviceType: cleanString(raw?.serviceType).toLowerCase(),
            displayName: cleanString(raw?.displayName),
            unit: cleanString(raw?.unit).toLowerCase(),
            category: cleanString(raw?.category).toLowerCase(),
            aliases: toStringArray(raw?.aliases),
            aiKeywords: toStringArray(raw?.aiKeywords),
            negativeKeywords: toStringArray(raw?.negativeKeywords),
            followupQuestions: Array.isArray(raw?.followupQuestions)
                ? raw.followupQuestions.map((q: any) => ({
                    key: cleanString(q?.key).toLowerCase(),
                    question: cleanString(q?.question),
                }))
                : [],
        }));

        const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
        if (!OPENAI_API_KEY) {
            throw new Error("OPENAI_API_KEY is missing");
        }

        const schema = {
            name: "rule_resolution",
            schema: {
                type: "object",
                additionalProperties: false,
                properties: {
                    selectedRuleId: {
                        type: ["string", "null"],
                    },
                    confidence: {
                        type: "number",
                    },
                    normalizedRequestedWork: {
                        type: "string",
                    },
                    shouldAskClarifyingQuestion: {
                        type: "boolean",
                    },
                    clarifyingQuestion: {
                        type: "string",
                    },
                    suppressQuestionKeys: {
                        type: "array",
                        items: { type: "string" },
                    },
                    reasoningSummary: {
                        type: "string",
                    },
                },
                required: [
                    "selectedRuleId",
                    "confidence",
                    "normalizedRequestedWork",
                    "shouldAskClarifyingQuestion",
                    "clarifyingQuestion",
                    "suppressQuestionKeys",
                    "reasoningSummary",
                ],
            },
            strict: true,
        };

        const developerPrompt = `
You resolve which service pricing rule best matches an admin request.

Return ONLY valid JSON.

GOAL:
Choose the best candidate rule for the current request, normalize the requested work,
and decide whether the app should ask a clarifying question.

IMPORTANT:
- The app is universal. Do NOT force any specific trade unless the candidate rule clearly matches the request.
- Respect the actual request text more than generic candidate names.
- Negative keywords matter strongly. 
- Avoid false positives.
- If confidence is not high enough, return selectedRuleId = null and ask a short clarifying question.
- If one candidate clearly contradicts the prompt, do not choose it.
- If the prompt clearly describes one service type, do not choose an unrelated service type.
- If the prompt describes a specific task, choose only a candidate that matches that task.

RULES:
- normalizedRequestedWork should be short, clean, and practical.
- shouldAskClarifyingQuestion = true when the request is ambiguous or top candidates are too close.
- suppressQuestionKeys should include issue_description or requested_work when normalizedRequestedWork already captures that clearly.
- Confidence:
  - 0.85 to 1.00 => clear match
  - 0.60 to 0.84 => plausible but not fully certain
  - below 0.60 => ask a clarifying question
- Prefer one sharp clarifying question, not many.

OUTPUT BEHAVIOR:
- If selectedRuleId is not null and normalizedRequestedWork is clear, suppressQuestionKeys may include "issue_description" or "requested_work".
- If candidate unit is fixed/item/hour, do not ask for project size unless the prompt explicitly requires it.
`.trim();

        const userPrompt = `
Prompt:
${prompt}

Guided answers:
${JSON.stringify(guidedAnswers, null, 2)}

Candidates:
${JSON.stringify(compactCandidates, null, 2)}
`.trim();

        const response = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${OPENAI_API_KEY}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                model: "gpt-5.4-mini",
                messages: [
                    {
                        role: "developer",
                        content: developerPrompt,
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

        const candidateIds = new Set(compactCandidates.map((c) => c.ruleId).filter(Boolean));
        const confidence = clampConfidence(parsed.confidence);

        const selectedRuleId =
            confidence >= 0.60 && parsed.selectedRuleId && candidateIds.has(parsed.selectedRuleId)
                ? parsed.selectedRuleId
                : null;

        const result = {
            selectedRuleId,
            confidence,
            normalizedRequestedWork: sanitizeNormalizedRequestedWork(
                parsed.normalizedRequestedWork || prompt,
            ),
            shouldAskClarifyingQuestion: parsed.shouldAskClarifyingQuestion === true,
            clarifyingQuestion: sanitizeClarifyingQuestion(parsed.clarifyingQuestion),
            suppressQuestionKeys: sanitizeSuppressQuestionKeys(
                parsed.suppressQuestionKeys,
                compactCandidates,
            ),
            reasoningSummary: sanitizeReasoningSummary(parsed.reasoningSummary),
        };

        if (!result.selectedRuleId && !result.clarifyingQuestion) {
            result.shouldAskClarifyingQuestion = true;
            result.clarifyingQuestion = "What kind of service do you need?";
        }

        return json(result, 200);
    } catch (e) {
        return json(
            { error: e instanceof Error ? e.message : String(e) },
            400,
        );
    }
});