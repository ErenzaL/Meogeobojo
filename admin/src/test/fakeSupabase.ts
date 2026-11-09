/* A tiny chainable stand-in for the Supabase client, recording what the app asks for. */
type Resp = { data?: unknown; error?: unknown; count?: number | null }
type Call = { table: string; op: string; payload?: unknown; filters: [string, ...unknown[]][]; single: boolean }

export function createFake() {
  const calls: Call[] = []
  const responses = new Map<string, Resp | ((c: Call) => Resp)>()
  const rpcs: { name: string; args: unknown }[] = []
  let session: { user: { id: string; email: string } } | null = null
  const listeners: ((e: string, s: typeof session) => void)[] = []

  const from = (table: string) => {
    const state: Call = { table, op: 'select', filters: [], single: false }
    const b: Record<string, unknown> = {}
    const chain = (name: string) => (...args: unknown[]) => {
      if (['insert', 'update', 'delete', 'upsert'].includes(name)) { state.op = name; state.payload = args[0] }
      else if (name === 'single' || name === 'maybeSingle') state.single = true
      else state.filters.push([name, ...args])
      return b
    }
    for (const m of ['select', 'insert', 'update', 'delete', 'upsert', 'eq', 'in', 'is', 'or', 'ilike', 'gte', 'order', 'range', 'limit', 'single', 'maybeSingle']) b[m] = chain(m)
    b.then = (res: (v: unknown) => unknown, rej: (e: unknown) => unknown) => {
      calls.push({ ...state, filters: [...state.filters] })
      const r = responses.get(`${table}:${state.op}`)
      const out = (typeof r === 'function' ? r(state) : r) ?? { data: [], error: null, count: 0 }
      const data = state.single && Array.isArray(out.data) ? out.data[0] ?? null : out.data
      return Promise.resolve({ data, error: out.error ?? null, count: out.count ?? null }).then(res, rej)
    }
    return b
  }

  const client = {
    from,
    rpc: (name: string, args: unknown) => { rpcs.push({ name, args }); const r = responses.get(`rpc:${name}`) as Resp | undefined; return Promise.resolve({ data: r?.data ?? null, error: r?.error ?? null }) },
    storage: { from: () => ({ upload: async () => ({ error: null }), getPublicUrl: () => ({ data: { publicUrl: 'https://x/y.png' } }) }) },
    auth: {
      getSession: async () => ({ data: { session } }),
      onAuthStateChange: (cb: (e: string, s: typeof session) => void) => { listeners.push(cb); return { data: { subscription: { unsubscribe: () => undefined } } } },
      signInWithPassword: async () => ({ error: null }),
      signOut: async () => { session = null },
    },
  }

  return {
    client, calls, rpcs,
    respond: (key: string, r: Resp | ((c: Call) => Resp)) => responses.set(key, r),
    signInAs: (role: string | null) => {
      session = { user: { id: '00000000-0000-4000-8000-000000000001', email: 'admin@example.org' } }
      responses.set('admin_roles:select', { data: role ? [{ role }] : [] })
    },
    reset: () => { calls.length = 0; rpcs.length = 0; responses.clear(); session = null },
    last: (table: string, op: string) => [...calls].reverse().find((c) => c.table === table && c.op === op),
  }
}

export const fake = createFake()
