// Supabase Edge Function entry point. All logic lives in core.ts (tested with `deno test`).
import { defaultOrigins, handle } from './core.ts'

const num = (name: string, fallback: number) => {
  const n = Number(Deno.env.get(name))
  return Number.isFinite(n) && n > 0 ? n : fallback
}

Deno.serve((req) =>
  handle(req, {
    env: {
      supabaseUrl: Deno.env.get('SUPABASE_URL') ?? '',
      anonKey: Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      serviceKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      geminiKey: Deno.env.get('GEMINI_API_KEY') ?? '',
      geminiModel: Deno.env.get('GEMINI_MODEL') ?? '',
      allowedOrigins: (Deno.env.get('AI_CHAT_ALLOWED_ORIGINS') ?? '').split(',').map((s) => s.trim()).filter(Boolean).concat(defaultOrigins()),
      perMinute: num('AI_CHAT_PER_MINUTE', 12),
      perDay: num('AI_CHAT_PER_DAY', 200),
      globalPerDay: num('AI_CHAT_GLOBAL_PER_DAY', 1200),
    },
    fetch,
  })
)
