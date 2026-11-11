// Supabase Edge Function entry point. All logic lives in core.ts (tested with `deno test`).
import { handle } from './core.ts'

Deno.serve((req) =>
  handle(req, {
    env: {
      supabaseUrl: Deno.env.get('SUPABASE_URL') ?? '',
      anonKey: Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      kakaoKey: Deno.env.get('KAKAO_REST_API_KEY') ?? '',
    },
    fetch,
  })
)
