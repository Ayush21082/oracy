import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

/**
 * After Firebase OTP, a fresh guest may need to become the account that
 * already owns that phone (including Apple/Google accounts).
 *
 * This never attaches the number to the caller. It only mints a session for
 * the existing owner when the caller is a transient guest.
 */

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function isTransientCaller(
  onboardingCompleted: boolean | null | undefined,
  providers: string[] | null | undefined,
): boolean {
  const oauth = (providers ?? []).filter((p) => p === "apple" || p === "google");
  return oauth.length === 0 && onboardingCompleted !== true;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing Authorization" }, 401);
  }

  let phone = "";
  try {
    const body = await req.json();
    phone = typeof body?.phone === "string" ? body.phone.trim() : "";
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }
  if (phone.length < 8) {
    return json({ error: "Invalid phone" }, 400);
  }

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return json({ error: "Unauthorized" }, 401);
  }

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: callerProfile, error: callerError } = await admin
    .from("profiles")
    .select("id, onboarding_completed, phone")
    .eq("id", user.id)
    .maybeSingle();
  if (callerError || !callerProfile) {
    return json({ error: "Profile not found" }, 404);
  }

  const { data: callerIdentities } = await admin.auth.admin.getUserById(user.id);
  const callerProviders = (callerIdentities.user?.identities ?? [])
    .map((identity) => identity.provider?.toLowerCase() ?? "")
    .filter(Boolean);

  if (!isTransientCaller(callerProfile.onboarding_completed, callerProviders)) {
    return json({ error: "PHONE_ALREADY_ASSOCIATED_WITH_ANOTHER_ACCOUNT" }, 409);
  }

  const { data: owners, error: ownerError } = await admin.rpc("lookup_phone_owner", {
    p_phone: phone,
  });
  if (ownerError) {
    return json({ error: "Lookup failed" }, 500);
  }

  const owner = Array.isArray(owners) ? owners[0] : owners;
  if (!owner?.owner_user_id) {
    return json({ error: "PHONE_NOT_OWNED" }, 404);
  }
  if (owner.owner_user_id === user.id) {
    return json({ already_owned: true, owner_user_id: owner.owner_user_id });
  }

  let email = typeof owner.owner_email === "string" ? owner.owner_email : "";
  if (!email) {
    const { data: ownerUser } = await admin.auth.admin.getUserById(owner.owner_user_id);
    email = ownerUser.user?.email?.trim() ?? "";
  }
  if (!email) {
    email = `phone-identity+${String(owner.owner_user_id).replace(/-/g, "")}@users.oracy.invalid`;
    const { error: emailError } = await admin.auth.admin.updateUserById(owner.owner_user_id, {
      email,
      email_confirm: true,
    });
    if (emailError) {
      return json({ error: "PHONE_LOGIN_SWITCH_FAILED" }, 500);
    }
  }

  const { data: link, error: linkError } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  const hashedToken = link?.properties?.hashed_token;
  if (linkError || !hashedToken) {
    return json({ error: "PHONE_LOGIN_SWITCH_FAILED" }, 500);
  }

  await admin.rpc("log_phone_identity_event", {
    p_phone: phone,
    p_action: "session_issued",
    p_actor: user.id,
    p_target: owner.owner_user_id,
    p_detail: { owner_providers: owner.owner_providers ?? [] },
  });

  return json({
    hashed_token: hashedToken,
    owner_user_id: owner.owner_user_id,
  });
});
