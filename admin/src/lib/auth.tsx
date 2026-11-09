import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'
import { isRole, roleAtLeast, type Role } from '@/lib/roles'

type AuthState =
  | { status: 'loading' }
  | { status: 'signedOut' }
  /** Signed in, but the database says this account has no admin role. */
  | { status: 'denied'; email: string | undefined }
  | { status: 'ready'; role: Role; userId: string; email: string | undefined }

type AuthContextValue = {
  state: AuthState
  signIn: (email: string, password: string) => Promise<string | null>
  signOut: () => Promise<void>
  can: (min: Role) => boolean
}

const AuthContext = createContext<AuthContextValue | null>(null)

/** The role is read from public.admin_roles (RLS: a user can read only their own row). */
async function loadState(session: Session | null): Promise<AuthState> {
  if (!session) return { status: 'signedOut' }
  const { data, error } = await supabase
    .from('admin_roles')
    .select('role')
    .eq('user_id', session.user.id)
    .maybeSingle()
  if (error || !data || !isRole(data.role)) return { status: 'denied', email: session.user.email }
  return { status: 'ready', role: data.role, userId: session.user.id, email: session.user.email }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthState>({ status: 'loading' })

  useEffect(() => {
    let cancelled = false
    const apply = (session: Session | null) => {
      void loadState(session).then((s) => !cancelled && setState(s))
    }
    void supabase.auth.getSession().then(({ data }) => apply(data.session))
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => apply(session))
    return () => {
      cancelled = true
      sub.subscription.unsubscribe()
    }
  }, [])

  const signIn = useCallback(async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    return error ? error.message : null
  }, [])
  const signOut = useCallback(async () => {
    await supabase.auth.signOut()
    setState({ status: 'signedOut' })
  }, [])

  const value = useMemo<AuthContextValue>(
    () => ({
      state,
      signIn,
      signOut,
      can: (min) => state.status === 'ready' && roleAtLeast(state.role, min),
    }),
    [state, signIn, signOut],
  )
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider')
  return ctx
}
