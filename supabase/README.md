# Oracy — Supabase Backend Setup

This is what the iOS app needs when `BACKEND_MODE` is `supabase`.

## What you need

| Piece | Why |
|-------|-----|
| Supabase project | Auth, Postgres, Storage, Edge Functions |
| OpenAI API key | Whisper transcription + GPT feedback |
| `Oracy/Config/Secrets.plist` | Points the app at your project |

Optional later: Apple / Google Sign-In.

---

## 1. Create the Supabase project

1. Go to [supabase.com](https://supabase.com) → New project
2. Copy from **Project Settings → API**:
   - **Project URL** → `SUPABASE_URL`
   - **anon public** key → `SUPABASE_ANON_KEY`
3. Note your **Project Ref** (Dashboard URL: `https://supabase.com/dashboard/project/<ref>`)

---

## 2. Install CLI & link

```bash
brew install supabase/tap/supabase   # if needed
cd /path/to/this/repo
supabase login
supabase link --project-ref YOUR_PROJECT_REF
```

---

## 3. Database + seed data

```bash
# Apply schema (profiles, challenges, sessions, RLS, etc.)
supabase db push

# Load challenge bank (run in SQL Editor, or:)
psql "$DATABASE_URL" -f supabase/seed/challenges.sql
```

Or open **SQL Editor** in the dashboard → paste contents of `supabase/migrations/001_initial_schema.sql`, run it → then paste/run `supabase/seed/challenges.sql`.

---

## 4. Storage bucket for audio

In Dashboard → **Storage** → New bucket:

- Name: `session-audio` (must match what the app / edge function expect — check migration / SessionService if unsure)
- Public: **off** (private)
- Allow authenticated uploads via the RLS policies from the migration

If the migration already creates the bucket, skip this step.

---

## 5. Auth

Dashboard → **Authentication → Providers**:

1. **Anonymous** — turn **ON** (required for guest flow)
2. **Phone** — handled by **Firebase Auth** (not Supabase SMS / Twilio). See [Firebase Phone](#firebase-phone) below. Apply migration `014_profile_phone.sql` so verified numbers store on `profiles.phone`.
3. Apple / Google — only when you’re ready (see below)

**URL config** (Authentication → URL Configuration):

- Site URL: `com.heyayush.oracy://`
- Redirect URLs: `com.heyayush.oracy://auth/callback`

### Firebase Phone

Phone OTP uses **Firebase Auth** only. Supabase keeps the app session (anon / Apple / Google); the verified E.164 is saved on `profiles.phone`.

1. Firebase Console → add iOS app `com.heyayush.oracy` → download **GoogleService-Info.plist** into `Oracy/` (gitignored; see `Oracy/Config/GoogleService-Info.example.plist`)
2. Authentication → Sign-in method → **Phone** → Enable
3. Project settings → Cloud Messaging → upload an **APNs** auth key (Push capability is in `Oracy.entitlements`)
4. Add `REVERSED_CLIENT_ID` from the plist as a URL scheme in `Info.plist` (reCAPTCHA fallback on Simulator)
5. Apply `014_profile_phone.sql` (`supabase db push` or SQL editor)

Mock backend still accepts any 6-digit code without Firebase.

---

## 6. Edge function (`analyze-session`)

The app calls this after upload: Whisper → GPT → writes transcript/feedback/streak.

```bash
# Set OpenAI key on the linked project
supabase secrets set OPENAI_API_KEY=sk-your-key-here

# Deploy
supabase functions deploy analyze-session

# Debug System Status probe (free models list + optional ~$0.00001 token)
supabase functions deploy system-status

# Phone OTP → existing Apple/Google account session (see migration 030)
supabase functions deploy resolve-phone-session
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically in hosted functions.

### Local function testing (optional)

```bash
supabase start
supabase db reset
echo 'OPENAI_API_KEY=sk-...' > supabase/.env.local
supabase functions serve analyze-session --env-file supabase/.env.local
```

Local API URL is usually `http://127.0.0.1:54321` — put that in Secrets for a simulator pointing at local Supabase.

---

## Remote config

Table `public.remote_config` holds feature flags (authenticated read).

| Key | Default | Meaning |
|-----|---------|---------|
| `membership_plan_enabled` | `false` | Enables Oracy Pro (RevenueCat) paywall, weekly quota, and membership UI |
| `invite_only_enabled` | `false` | Requires an invite / referral code before the app unlocks |
| `use_revenuecat_paywall` | `false` | `true` = RevenueCat dashboard PaywallView; `false` = Oracy branded UI using `Purchases.offerings()` |

### RevenueCat (Oracy Pro)

Client setup (already in app):

- SPM: `https://github.com/RevenueCat/purchases-ios-spm.git` → products **RevenueCat** + **RevenueCatUI**
- API key in `Oracy/Config/Secrets.plist` → `REVENUECAT_API_KEY`
- Entitlement id: **`oracy_pro`**
- Default paywall: **Oracy branded** (`OracyBrandedPaywallView`) — loads Monthly/Annual from current offering ([displaying products](https://www.revenuecat.com/docs/getting-started/displaying-products))
- Optional: set `use_revenuecat_paywall=true` to use dashboard `PaywallView` instead
- Manage: RevenueCat `CustomerCenterView` (`OracyCustomerCenterView`)
- App user id: Supabase / mock user UUID via `Purchases.logIn`

You do **not** need a dashboard Paywall if you keep `use_revenuecat_paywall=false`. You still need:

1. Entitlement **`oracy_pro`**
2. App Store products (monthly + yearly) attached to it
3. A **current** Offering with **Monthly** + **Annual** packages
4. `membership_plan_enabled=true` when ready to sell

Enable in SQL editor:

```sql
update public.remote_config
set value = 'true'::jsonb
where key = 'membership_plan_enabled';

update public.remote_config
set value = 'true'::jsonb
where key = 'invite_only_enabled';
```


```bash
cp Oracy/Config/Secrets.example.plist Oracy/Config/Secrets.plist
```

Edit `Oracy/Config/Secrets.plist`:

```xml
<key>BACKEND_MODE</key>
<string>supabase</string>

<key>SUPABASE_URL</key>
<string>https://YOUR_PROJECT_REF.supabase.co</string>

<key>SUPABASE_ANON_KEY</key>
<string>eyJhbGciOi...</string>

<key>GOOGLE_CLIENT_ID</key>
<string></string>   <!-- leave empty until Google is set up -->
```

`Secrets.plist` is gitignored. Do not commit real keys.

Confirm the file is in the app target (file-system synced `Oracy/` folder — it should pick it up automatically).

---

## 8. Run the app

1. Open `Oracy.xcodeproj`
2. Clean build folder if you just switched modes
3. Run on simulator/device
4. Complete onboarding → record a session → you should hit the edge function (not mock feedback)

If something fails, check:

- Xcode console for Supabase / network errors
- Supabase → **Edge Functions → analyze-session → Logs**
- Storage objects appearing under the user’s path
- `sessions` rows updating to `completed`

---

## Google Sign-In (optional)

1. Google Cloud Console → create **iOS** OAuth client (`com.heyayush.oracy`) and ideally a **Web** client
2. Secrets.plist:
   - `GOOGLE_CLIENT_ID` = iOS client ID (`….apps.googleusercontent.com`)
   - `GOOGLE_SERVER_CLIENT_ID` = Web client ID (optional but recommended)
3. Add the **reversed** iOS client ID as a URL scheme in `Oracy/Info.plist`  
   Example: `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`
4. Supabase Dashboard → Authentication → Providers → **Google**:
   - Enable
   - Client IDs: `WEB_CLIENT_ID,IOS_CLIENT_ID` (web first when both exist)
   - Turn **Skip nonce check** ON for native iOS

Do **not** leave placeholder schemes like `YOUR_REVERSED_CLIENT_ID` in Info.plist (App Store rejects them).

---

## Apple Sign-In (native iOS)

Required for production / real-device testing (Simulator often works for the sheet, but use a device with an Apple ID for best results).

### 1. Apple Developer

1. Certificates, Identifiers & Profiles → Identifiers → App ID `com.heyayush.oracy`
2. Enable **Sign in with Apple** → Save
3. If Xcode asks, enable the **Sign in with Apple** capability on the Oracy target (entitlements file is already in-repo: `Oracy/Oracy.entitlements`)

### 2. Supabase Dashboard

1. Authentication → Providers → **Apple** → Enable
2. **Client IDs**: `com.heyayush.oracy` (the iOS Bundle ID — required for native `id_token` flow)
3. Secret Key / Services ID / `.p8` are only needed for **web/Android** OAuth — skip for iOS-only

### 3. App behavior

- Guests (anonymous) **link** Apple onto the same user so onboarding progress is kept
- If that Apple ID is already tied to another account, the app signs into that account instead
- Apple’s name is applied only when the profile has no display name yet (onboarding name wins)
- On launch, revoked Apple credentials clear the session and return to a guest

### 4. Local Supabase

`supabase/config.toml` has `[auth.external.apple] enabled = true` with `client_id = "com.heyayush.oracy"`.

---

## Mode switch cheatsheet

| `BACKEND_MODE` | Behavior |
|----------------|----------|
| `mock` | No network; local UserDefaults + fake AI |
| `supabase` | Real auth, DB, storage, Whisper + GPT |

---

## Common issues

| Symptom | Fix |
|---------|-----|
| Still getting fake feedback | `BACKEND_MODE` still `mock`, or Secrets not in the bundle |
| Auth fails immediately | Enable Anonymous provider |
| Apple Sign-In fails | Enable Sign in with Apple on App ID; enable Apple provider in Supabase with Client ID = `com.heyayush.oracy`; rebuild so entitlements are signed |
| Delete account fails | Apply migration `009_delete_own_account.sql` (`supabase db push` or SQL editor) |
| Profile photo upload fails | Apply migration `010_profile_avatar.sql` (avatars bucket + `avatar_url`) |
| Analyze fails 401 | Redeploy function; JWT / anon key mismatch |
| Analyze fails 500 | Missing `OPENAI_API_KEY` secret; check function logs |
| Upload fails | Storage bucket / RLS policies |
| Google sign-in no return | Missing reversed client ID URL scheme |
