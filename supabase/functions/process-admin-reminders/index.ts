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

async function sendFcmMessage(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
) {
  const message: Record<string, unknown> = {
    token,
    notification: { title, body },
    android: {
      priority: 'high',
      notification: { sound: 'default' },
    },
    apns: {
      headers: { 'apns-priority': '10' },
      payload: {
        aps: {
          sound: 'default',
        },
      },
    },
  }

  if (Object.keys(data).length > 0) {
    message.data = data
  }

  const res = await fetch(
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

  const json = await res.json().catch(() => null)

  return {
    ok: res.ok,
    status: res.status,
    response: json,
  }
}

Deno.serve(async () => {
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const nowIso = new Date().toISOString()

    const { data: reminders, error: remindersError } = await supabase
      .from('admin_calendar_items')
      .select('id, admin_id, title, note_text, reminder_at')
      .eq('kind', 'reminder')
      .eq('is_done', false)
      .eq('is_sent', false)
      .eq('is_cancelled', false)
      .lte('reminder_at', nowIso)
      .order('reminder_at', { ascending: true })
      .limit(100)

    if (remindersError) throw remindersError

    if (!reminders || reminders.length === 0) {
      return new Response(
        JSON.stringify({
          ok: true,
          processed: 0,
          sent: 0,
          reason: 'no_due_reminders',
        }),
        { headers: jsonHeaders },
      )
    }

    const { accessToken, projectId } = await getGoogleAccessToken()

    let processed = 0
    let sent = 0
    const details = []

    for (const item of reminders) {
      const title = (item.title || 'Reminder').trim()
      const body = (item.note_text || 'Reminder is due now').trim()

      const { data: tokens, error: tokensError } = await supabase
        .from('admin_push_tokens')
        .select('token, platform')
        .eq('admin_id', item.admin_id)

      if (tokensError) throw tokensError

      let sentForThisItem = 0

      for (const row of tokens || []) {
        const res = await sendFcmMessage(
          accessToken,
          projectId,
          row.token,
          title,
          body,
          {
            type: 'calendar_reminder',
            calendar_item_id: String(item.id),
            admin_id: String(item.admin_id),
          },
        )

        if (res.ok) sentForThisItem++

        details.push({
          item_id: item.id,
          admin_id: item.admin_id,
          platform: row.platform,
          ok: res.ok,
          status: res.status,
          response: res.response,
        })
      }

      await supabase.from('admin_in_app_notifications').insert({
        admin_id: item.admin_id,
        calendar_item_id: item.id,
        title,
        body,
        is_read: false,
      })

      await supabase
        .from('admin_calendar_items')
        .update({ is_sent: true })
        .eq('id', item.id)

      processed++
      sent += sentForThisItem
    }

    return new Response(
      JSON.stringify({
        ok: true,
        processed,
        sent,
        details,
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