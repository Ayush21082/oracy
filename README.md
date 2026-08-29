# Oracy — 1-Minute Speaking Coach

iOS + Mac (Catalyst) app that helps you become a more confident English speaker through a one-minute daily speaking exercise with AI feedback.

## Architecture

- **App**: SwiftUI (`Oracy/`) — iPhone, iPad, and **Mac Catalyst** (same parchment / Fraunces aesthetic)
- **Backend**: Supabase (Auth, Postgres, Storage, Edge Functions)
- **AI**: OpenAI Whisper (speech-to-text) + GPT (structured feedback)

## Getting Started

### Quick start (no keys) — mock mode

The app defaults to **mock** backend. Open `Oracy.xcodeproj` and Run.

**Mac:** in the scheme destination menu choose **My Mac (Mac Catalyst)**. First run may ask Xcode to register the Mac for development signing.

Mock mode:
- Guest auth + onboarding locally
- Seeded challenges
- Local microphone recording
- Simulated AI feedback (no OpenAI)
- History + streak stored in UserDefaults

### Live mode (Supabase + OpenAI)

See **[supabase/README.md](supabase/README.md)** for the full checklist.

Short version:

1. Create a Supabase project
2. Copy `Oracy/Config/Secrets.example.plist` → `Oracy/Config/Secrets.plist`
3. Set `BACKEND_MODE` to `supabase` and fill `SUPABASE_URL` + `SUPABASE_ANON_KEY`
4. Push migrations + seed, create storage bucket, deploy `analyze-session` with `OPENAI_API_KEY`
5. Enable **Anonymous** auth in the dashboard
6. Run the app

```xml
<!-- Oracy/Config/Secrets.plist -->
<key>BACKEND_MODE</key>
<string>supabase</string>
```

## Core Loop

```
Open → Today's challenge → Record 60s → Upload → Whisper STT
→ GPT feedback → Scores + improvements → Streak → Return tomorrow
```

## Project Layout

```
Oracy/                   # SwiftUI app
  Config/                # Secrets + AppConfig
  Core/Design|Models/    # Theme + Codable models
  Services/              # Auth, Session, Challenge, Audio
  Features/              # Screens
  Navigation/            # Router + tabs
supabase/
  migrations/            # Schema + RLS
  seed/                  # Challenge bank
  functions/analyze-session/
```
