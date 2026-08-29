import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const FILLER_WORDS = [
  "um", "uh", "like", "basically", "actually", "you know", "so", "right", "well",
];

interface AnalyzeRequest {
  sessionId: string;
  audioPath: string;
  challengePrompt: string;
  userLevel: string;
  userGoals: string[];
  durationSeconds: number;
}

interface FeedbackJSON {
  overallScore: number;
  fluency: number;
  grammar: number;
  vocabulary: number;
  clarity: number;
  confidence: number;
  wordsPerMinute: number;
  fillerWords: number;
  strengths: string[];
  nextImprovement: string;
  grammarCorrections: Array<{
    original: string;
    corrected: string;
    explanation: string;
  }>;
  vocabularySuggestions: Array<{
    original: string;
    suggestions: string[];
    context: string;
  }>;
  structureScore: number;
  structureNote: string;
  paceNote: string;
  suggestedExpression: { instead: string; try: string };
}

function countFillerWords(transcript: string): number {
  const lower = transcript.toLowerCase();
  let count = 0;
  for (const filler of FILLER_WORDS) {
    const regex = new RegExp(`\\b${filler.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "gi");
    const matches = lower.match(regex);
    if (matches) count += matches.length;
  }
  return count;
}

function countWords(transcript: string): number {
  return transcript.trim().split(/\s+/).filter(Boolean).length;
}

async function transcribeAudio(audioBlob: Blob, filename: string): Promise<string> {
  const formData = new FormData();
  formData.append("file", audioBlob, filename);
  formData.append("model", "whisper-1");
  formData.append("language", "en");
  formData.append("response_format", "verbose_json");

  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${OPENAI_API_KEY}` },
    body: formData,
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Whisper API error: ${err}`);
  }

  const data = await response.json();
  return data.text as string;
}

async function analyzeWithGPT(
  transcript: string,
  challengePrompt: string,
  userLevel: string,
  userGoals: string[],
  metrics: { wordCount: number; wpm: number; fillerCount: number; durationSeconds: number },
): Promise<FeedbackJSON> {
  const systemPrompt = `You are a calm, encouraging English speaking coach. Analyze the user's 60-second spoken response and return structured JSON feedback. Be specific and actionable — never give vague advice like "improve your grammar." Limit grammar corrections and vocabulary suggestions to the 3 most important each. Scores are 0-100. Confidence score is an AI estimate of delivery confidence based on speech patterns — never imply it is a psychological or medical assessment.`;

  const userPrompt = `Challenge prompt: "${challengePrompt}"
User level: ${userLevel}
User goals: ${userGoals.join(", ") || "general improvement"}
Duration: ${metrics.durationSeconds}s
Word count: ${metrics.wordCount}
Words per minute: ${metrics.wpm}
Filler words detected: ${metrics.fillerCount}

Transcript:
"""
${transcript}
"""

Return JSON matching this exact schema:
{
  "overallScore": number,
  "fluency": number,
  "grammar": number,
  "vocabulary": number,
  "clarity": number,
  "confidence": number,
  "wordsPerMinute": number,
  "fillerWords": number,
  "strengths": ["string"],
  "nextImprovement": "string",
  "grammarCorrections": [{"original": "string", "corrected": "string", "explanation": "string"}],
  "vocabularySuggestions": [{"original": "string", "suggestions": ["string"], "context": "string"}],
  "structureScore": number,
  "structureNote": "string",
  "paceNote": "string",
  "suggestedExpression": {"instead": "string", "try": "string"}
}`;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o",
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      response_format: { type: "json_object" },
      temperature: 0.4,
    }),
  });

  if (!response.ok) {
    const err = await response.text();
    throw new Error(`GPT API error: ${err}`);
  }

  const data = await response.json();
  const content = data.choices[0].message.content;
  const feedback = JSON.parse(content) as FeedbackJSON;

  feedback.wordsPerMinute = metrics.wpm;
  feedback.fillerWords = metrics.fillerCount;

  return feedback;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  // Parse once up front so the catch block can mark the session failed.
  let sessionIdForCleanup: string | undefined;

  try {
    if (!OPENAI_API_KEY) {
      throw new Error("OPENAI_API_KEY not configured");
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), { status: 401 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
    }

    const body: AnalyzeRequest = await req.json();
    const { sessionId, audioPath, challengePrompt, userLevel, userGoals, durationSeconds } = body;
    sessionIdForCleanup = sessionId;

    await supabase
      .from("sessions")
      .update({ status: "processing" })
      .eq("id", sessionId)
      .eq("user_id", user.id);

    const { data: audioData, error: downloadError } = await supabase.storage
      .from("session-audio")
      .download(audioPath);

    if (downloadError || !audioData) {
      throw new Error(`Failed to download audio: ${downloadError?.message}`);
    }

    const transcript = await transcribeAudio(audioData, "recording.m4a");
    const wordCount = countWords(transcript);
    const duration = durationSeconds || 60;
    const wpm = duration > 0 ? Math.round((wordCount / duration) * 60) : 0;
    const fillerCount = countFillerWords(transcript);

    const feedback = await analyzeWithGPT(transcript, challengePrompt, userLevel, userGoals, {
      wordCount,
      wpm,
      fillerCount,
      durationSeconds: duration,
    });

    const { error: updateError } = await supabase
      .from("sessions")
      .update({
        transcript,
        duration_seconds: duration,
        word_count: wordCount,
        words_per_minute: wpm,
        filler_count: fillerCount,
        feedback_json: feedback,
        overall_score: feedback.overallScore,
        status: "completed",
      })
      .eq("id", sessionId)
      .eq("user_id", user.id);

    if (updateError) throw updateError;

    const { data: streakData } = await supabase.rpc("update_streak", { p_user_id: user.id });
    const { data: profile } = await supabase
      .from("profiles")
      .select("streak_count")
      .eq("id", user.id)
      .single();

    return new Response(
      JSON.stringify({
        sessionId,
        transcript,
        feedback,
        streakCount: profile?.streak_count ?? streakData ?? 1,
      }),
      {
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      },
    );
  } catch (error) {
    let message = error instanceof Error ? error.message : "Unknown error";
    if (
      message.includes("insufficient_quota") ||
      message.toLowerCase().includes("exceeded your current quota")
    ) {
      message =
        "OpenAI quota exceeded. Add billing credits at platform.openai.com or set a new OPENAI_API_KEY via `supabase secrets set`.";
    }

    if (sessionIdForCleanup) {
      try {
        const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
        await supabase
          .from("sessions")
          .update({ status: "failed" })
          .eq("id", sessionIdForCleanup);
      } catch {
        // ignore cleanup errors
      }
    }

    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  }
});
