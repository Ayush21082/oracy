import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

/**
 * Lightweight health probe for debug System Status.
 * Cost: models list is free; optional 1-token chat is ~$0.00001.
 */

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

type CheckStatus = "ok" | "fail" | "skip";

interface CheckResult {
  id: string;
  name: string;
  status: CheckStatus;
  detail?: string;
  costUsd?: number;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  const checks: CheckResult[] = [];
  let totalCostUsd = 0;

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing Authorization" }, 401);
    }

    const bearer = authHeader.replace(/^Bearer\s+/i, "").trim();
    const isServiceRole = Boolean(
      bearer &&
        SUPABASE_SERVICE_ROLE_KEY &&
        bearer.length === SUPABASE_SERVICE_ROLE_KEY.length &&
        bearer === SUPABASE_SERVICE_ROLE_KEY,
    );

    if (!isServiceRole) {
      const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        global: { headers: { Authorization: authHeader } },
      });
      const { data: { user }, error: authError } = await userClient.auth.getUser();
      if (authError || !user) {
        return json({ error: "Unauthorized" }, 401);
      }
      checks.push({
        id: "edge_auth",
        name: "Edge auth",
        status: "ok",
        detail: "Caller authenticated",
      });
    } else {
      checks.push({
        id: "edge_auth",
        name: "Edge auth",
        status: "ok",
        detail: "Admin service role",
      });
    }

    // Service-role DB ping (challenges are public-readable; count is enough)
    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { count, error: dbError } = await admin
      .from("challenges")
      .select("id", { count: "exact", head: true })
      .eq("active", true);

    if (dbError) {
      checks.push({
        id: "edge_db",
        name: "Edge → database",
        status: "fail",
        detail: dbError.message,
      });
    } else {
      checks.push({
        id: "edge_db",
        name: "Edge → database",
        status: "ok",
        detail: `${count ?? 0} active challenges`,
      });
    }

    // OpenAI key present
    if (!OPENAI_API_KEY) {
      checks.push({
        id: "openai_key",
        name: "OpenAI API key",
        status: "fail",
        detail: "OPENAI_API_KEY not set in Supabase secrets",
      });
      checks.push({
        id: "openai_models",
        name: "OpenAI API reachability",
        status: "skip",
        detail: "Skipped — no API key",
      });
      checks.push({
        id: "openai_quota",
        name: "OpenAI quota (1-token)",
        status: "skip",
        detail: "Skipped — no API key",
      });
    } else {
      checks.push({
        id: "openai_key",
        name: "OpenAI API key",
        status: "ok",
        detail: "Secret is configured",
      });

      // Free: list models (validates key; no token spend)
      const modelsRes = await fetch("https://api.openai.com/v1/models", {
        headers: { Authorization: `Bearer ${OPENAI_API_KEY}` },
      });
      if (!modelsRes.ok) {
        const errText = await modelsRes.text();
        const quota = /insufficient_quota|exceeded your current quota/i.test(errText);
        checks.push({
          id: "openai_models",
          name: "OpenAI API reachability",
          status: "fail",
          detail: quota ? "Quota / billing issue" : truncate(errText, 160),
          costUsd: 0,
        });
        checks.push({
          id: "openai_quota",
          name: "OpenAI quota (1-token)",
          status: "skip",
          detail: "Skipped — models list failed",
        });
      } else {
        checks.push({
          id: "openai_models",
          name: "OpenAI API reachability",
          status: "ok",
          detail: "Models endpoint OK (free)",
          costUsd: 0,
        });

        // Tiny spend: 1 completion token via cheapest chat model
        const chatRes = await fetch("https://api.openai.com/v1/chat/completions", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${OPENAI_API_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            model: "gpt-4o-mini",
            max_tokens: 1,
            messages: [{ role: "user", content: "ok" }],
          }),
        });

        const chatCost = 0.00001;
        if (!chatRes.ok) {
          const errText = await chatRes.text();
          const quota = /insufficient_quota|exceeded your current quota/i.test(errText);
          checks.push({
            id: "openai_quota",
            name: "OpenAI quota (1-token)",
            status: "fail",
            detail: quota
              ? "Quota exceeded — add billing credits"
              : truncate(errText, 160),
            costUsd: 0,
          });
        } else {
          totalCostUsd += chatCost;
          checks.push({
            id: "openai_quota",
            name: "OpenAI quota (1-token)",
            status: "ok",
            detail: "Completion succeeded",
            costUsd: chatCost,
          });
        }
      }
    }

    const ok = checks.every((c) => c.status !== "fail");
    return json({
      ok,
      checks,
      estimatedCostUsd: totalCostUsd,
      checkedAt: new Date().toISOString(),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return json({ error: message, checks }, 500);
  }
});

function truncate(text: string, max: number): string {
  const t = text.replace(/\s+/g, " ").trim();
  return t.length <= max ? t : `${t.slice(0, max - 1)}…`;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
