import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

export const supabaseConfigured = Boolean(url && key)

/**
 * The browser client uses ONLY the publishable key. What an admin may do is
 * decided by Row Level Security in the database (public.has_role), never by
 * this app. Without configuration a placeholder client is created so the app
 * can still render its "not configured" screen.
 */
export const supabase = createClient(url ?? 'http://localhost:54321', key ?? 'missing-key', {
  auth: { persistSession: true, autoRefreshToken: true },
})
