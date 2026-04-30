import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

    // ⚠️ Для preview тоже лучше проверять админа
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return new Response("Missing Authorization", { status: 401 });

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 1) проверка пользователя
    const token = authHeader.replace("Bearer ", "");
    const { data: userData, error: userErr } = await supabase.auth.getUser(token);
    if (userErr || !userData?.user) return new Response("Unauthorized", { status: 401 });

    const adminEmail = userData.user.email;

    // 2) проверка админа (как у тебя в pay-period было)
    const { data: w, error: wErr } = await supabase
        .from("workers")
        .select("role")
        .eq("email", adminEmail)
        .maybeSingle();

    if (wErr || !w || w.role !== "admin") {
      return new Response("Forbidden: not admin", { status: 403 });
    }

    // 3) тело
    const body = await req.json();

    const {
      user_id,
      from,
      to,
      payment_method = "cash",
      payment_note = null,
    } = body;

    if (!user_id || !from || !to) {
      return new Response(JSON.stringify({ error: "user_id, from, to required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const normalizedMethod = String(payment_method ?? "cash")
        .toLowerCase()
        .trim();

    const allowedMethods = ["cash", "card", "transfer", "check", "other"];

    if (!allowedMethods.includes(normalizedMethod)) {
      return new Response(JSON.stringify({ error: "Invalid payment_method" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const cleanPaymentNote =
        typeof payment_note === "string" && payment_note.trim() !== ""
            ? payment_note.trim()
            : null;

    // ✅ Берём смены (закончены, но не оплачены) за период
    const { data: rows, error } = await supabase
      .from("work_logs")
      .select("id, start_time, end_time, total_hours, total_payment")
      .eq("user_id", user_id)
      .not("end_time", "is", null)
      .is("paid_at", null)
      .gte("start_time", from)
      .lte("start_time", to)
      .order("start_time", { ascending: true });

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    const total_hours = (rows ?? []).reduce((s, r) => s + Number(r.total_hours ?? 0), 0);
    const total_amount = (rows ?? []).reduce((s, r) => s + Number(r.total_payment ?? 0), 0);

    return new Response(
        JSON.stringify({
          user_id,
          from,
          to,
          shifts: rows?.length ?? 0,
          total_hours,
          total_amount,
          rows: rows ?? [],
          payment_method: normalizedMethod,
          payment_note: cleanPaymentNote,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
