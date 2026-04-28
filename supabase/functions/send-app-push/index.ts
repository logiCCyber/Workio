import { createClient } from 'npm:@supabase/supabase-js@2'
import * as jose from 'jsr:@panva/jose@6'

const jsonHeaders = { 'Content-Type': 'application/json' }

async function getGoogleAccessToken() {
    const projectId = Deno.env.get('FCM_PROJECT_ID')
    const clientEmail = Deno.env.get('FCM_CLIENT_EMAIL')
    const privateKeyRaw = Deno.env.get('FCM_PRIVATE_KEY')

    if (!projectId || !clientEmail || !privateKeyRaw) {
        throw new Error('Missing FCM secrets')
    }

    const privateKey = privateKeyRaw.replace(/\\n/g, '\n')
    const now = Math.floor(Date.now() / 1000)

    const key = await jose.importPKCS8(privateKey, 'RS256')

    const jwt = await new jose.SignJWT({
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
    })
        .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
        .setIssuer(clientEmail)
        .setSubject(clientEmail)
        .setAudience('https://oauth2.googleapis.com/token')
        .setIssuedAt(now)
        .setExpirationTime(now + 3600)
        .sign(key)

    const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
            grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            assertion: jwt,
        }),
    })

    const tokenJson = await tokenRes.json()

    if (!tokenRes.ok) {
        throw new Error(`Google OAuth error: ${JSON.stringify(tokenJson)}`)
    }

    return {
        accessToken: tokenJson.access_token as string,
        projectId,
    }
}

Deno.serve(async (req) => {
    try {
        const {
            to_user_id,
            role,
            title,
            body,
            data,
        } = await req.json()

        if (!to_user_id || !title || !body) {
            return new Response(
                JSON.stringify({
                    ok: false,
                    error: 'to_user_id, title, body are required',
                }),
                { status: 400, headers: jsonHeaders },
            )
        }

        const cleanRole =
            typeof role === 'string' && role.trim().length > 0
                ? role.trim().toLowerCase()
                : null

        const supabase = createClient(
            Deno.env.get('SUPABASE_URL')!,
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
        )

        let query = supabase
            .from('app_push_tokens')
            .select('token, platform, role')
            .eq('user_auth_id', to_user_id)

        if (cleanRole) {
            query = query.eq('role', cleanRole)
        }

        const { data: rows, error } = await query

        if (error) throw error

        if (!rows || rows.length === 0) {
            return new Response(
                JSON.stringify({
                    ok: true,
                    sent: 0,
                    reason: 'no_tokens',
                    to_user_id,
                    role: cleanRole,
                }),
                { headers: jsonHeaders },
            )
        }

        const { accessToken, projectId } = await getGoogleAccessToken()

        const dataPayload =
            data && typeof data === 'object'
                ? Object.fromEntries(
                    Object.entries(data).map(([k, v]) => [k, String(v)]),
                )
                : {}

        const results = []

        for (const row of rows) {
            const message: Record<string, unknown> = {
                token: row.token,
                notification: {
                    title,
                    body,
                },
                android: {
                    priority: 'high',
                    notification: {
                        sound: 'default',
                    },
                },
                apns: {
                    headers: {
                        'apns-priority': '10',
                    },
                    payload: {
                        aps: {
                            sound: 'default',
                        },
                    },
                },
            }

            if (Object.keys(dataPayload).length > 0) {
                message.data = dataPayload
            }

            const fcmRes = await fetch(
                `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
                {
                    method: 'POST',
                    headers: {
                        Authorization: `Bearer ${accessToken}`,
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ message }),
                },
            )

            const fcmJson = await fcmRes.json().catch(() => null)

            results.push({
                token_preview: row.token.slice(0, 12) + '...',
                platform: row.platform,
                role: row.role,
                ok: fcmRes.ok,
                status: fcmRes.status,
                response: fcmJson,
            })
        }

        return new Response(
            JSON.stringify({
                ok: true,
                total: results.length,
                sent: results.filter((x) => x.ok).length,
                failed: results.filter((x) => !x.ok).length,
                results,
            }),
            { headers: jsonHeaders },
        )
    } catch (e) {
        return new Response(
            JSON.stringify({
                ok: false,
                error: e instanceof Error ? e.message : String(e),
            }),
            { status: 500, headers: jsonHeaders },
        )
    }
})