import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function mustEnv(name: string) {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}

const SUPABASE_URL = mustEnv("SUPABASE_URL");
const SUPABASE_ANON_KEY = mustEnv("SUPABASE_ANON_KEY");
const SUPABASE_SERVICE_ROLE_KEY = mustEnv("SUPABASE_SERVICE_ROLE_KEY");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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

async function tryDeleteAvatar(adminClient: any, avatarUrl?: string | null) {
  if (!avatarUrl) return;

  const marker = "/storage/v1/object/public/";
  const idx = avatarUrl.indexOf(marker);
  if (idx === -1) return;

  const rest = avatarUrl.slice(idx + marker.length); // bucket/path
  const slash = rest.indexOf("/");
  if (slash === -1) return;

  const bucket = rest.slice(0, slash);
  const path = decodeURIComponent(rest.slice(slash + 1));

  try {
    await adminClient.storage.from(bucket).remove([path]);
  } catch {
    // молча игнорируем, чтобы удаление worker не падало из-за картинки
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing Authorization header" }, 401);
    }

    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const adminClient = createClient(
        SUPABASE_URL,
        SUPABASE_SERVICE_ROLE_KEY,
    );

    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser();

    if (authError || !user) {
      return json({ error: "Unauthorized" }, 401);
    }

    const body = await req.json();
    const workerId = body?.worker_id?.toString()?.trim();

    if (!workerId) {
      return json({ error: "worker_id is required" }, 400);
    }

    const { data: worker, error: workerError } = await adminClient
        .from("workers")
        .select("id, auth_user_id, created_by_auth_id, owner_admin_id, avatar_url, on_shift")
        .eq("id", workerId)
        .maybeSingle();

    if (workerError) {
      return json({ error: workerError.message }, 500);
    }

    if (!worker) {
      return json({ error: "Worker not found" }, 404);
    }

    const creatorId = worker.created_by_auth_id ?? worker.owner_admin_id;

    if (!creatorId) {
      return json(
          { error: "This worker has no creator assigned. Delete is blocked." },
          403,
      );
    }

    if (creatorId !== user.id) {
      return json(
          { error: "You can delete only workers created by you." },
          403,
      );
    }

    if (worker.on_shift === true) {
      return json(
          { error: "Worker is currently on shift and cannot be deleted." },
          400,
      );
    }

    const { count: workLogsCount, error: workLogsError } = await adminClient
        .from("work_logs")
        .select("id", { count: "exact", head: true })
        .eq("user_id", worker.auth_user_id);

    if (workLogsError) {
      return json({ error: workLogsError.message }, 500);
    }

    const { count: paymentsCount, error: paymentsError } = await adminClient
        .from("payments")
        .select("id", { count: "exact", head: true })
        .eq("worker_auth_id", worker.auth_user_id);

    if (paymentsError) {
      return json({ error: paymentsError.message }, 500);
    }

    if ((workLogsCount ?? 0) > 0 || (paymentsCount ?? 0) > 0) {
      return json(
          { error: "Worker cannot be deleted because history or payments exist." },
          400,
      );
    }

    await tryDeleteAvatar(adminClient, worker.avatar_url);

    // Сначала удаляем auth user, чтобы email точно освободился
    if (worker.auth_user_id) {
      const { error: deleteAuthError } =
          await adminClient.auth.admin.deleteUser(worker.auth_user_id);

      if (deleteAuthError) {
        return json({ error: deleteAuthError.message }, 500);
      }
    }

    const { error: deleteWorkerError } = await adminClient
        .from("workers")
        .delete()
        .eq("id", worker.id);

    if (deleteWorkerError) {
      return json({ error: deleteWorkerError.message }, 500);
    }

    return json({
      ok: true,
      message: "Worker deleted successfully",
    });
  } catch (e) {
    return json(
        { error: e instanceof Error ? e.message : String(e) },
        500,
    );
  }
});
