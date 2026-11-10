/* A tiny chainable stand-in for the Supabase client, recording what the app asks for. */
type Resp = { data?: unknown; error?: unknown; count?: number | null }
type Call = { table: string; op: string; payload?: unknown; filters: [string, ...unknown[]][]; single: boolean }

export function createFake() {
  const calls: Call[] = []
  const responses = new Map<string, Resp | ((c: Call) => Resp)>()
  const rpcs: { name: string; args: unknown }[] = []
  const uploads: { bucket: string; path: string; body: unknown }[] = []
  const removed: string[] = []
  const invokes: { name: string; body: unknown }[] = []
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
    for (const m of ['select', 'insert', 'update', 'delete', 'upsert', 'eq', 'in', 'is', 'or', 'ilike', 'gte', 'lte', 'not', 'neq', 'order', 'range', 'limit', 'single', 'maybeSingle']) b[m] = chain(m)
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
    functions: { invoke: (name: string, opts: { body: unknown }) => { invokes.push({ name, body: opts.body }); const r = responses.get(`fn:${name}`) as Resp | ((b: unknown) => Resp) | undefined; const out = (typeof r === 'function' ? r(opts.body) : r) ?? { data: null, error: null }; return Promise.resolve({ data: out.data ?? null, error: out.error ?? null }) } },
    rpc: (name: string, args: unknown) => { rpcs.push({ name, args }); const r = responses.get(`rpc:${name}`) as Resp | undefined; return Promise.resolve({ data: r?.data ?? null, error: r?.error ?? null }) },
    storage: { from: (bucket: string) => ({ upload: async (path: string, body: unknown) => { uploads.push({ bucket, path, body }); return { error: null } }, remove: async (paths: string[]) => { removed.push(...paths); return { error: null } }, createSignedUrl: async (path: string) => ({ data: { signedUrl: `https://signed.example/${bucket}/${path}` }, error: null }), getPublicUrl: (path: string) => ({ data: { publicUrl: `https://x.supabase.co/storage/v1/object/public/${bucket}/${path}` } }) }) },
    auth: {
      getSession: async () => ({ data: { session } }),
      onAuthStateChange: (cb: (e: string, s: typeof session) => void) => { listeners.push(cb); return { data: { subscription: { unsubscribe: () => undefined } } } },
      signInWithPassword: async () => ({ error: null }),
      signOut: async () => { session = null },
    },
  }

  return {
    client, calls, rpcs, uploads, removed, invokes,
    respond: (key: string, r: Resp | ((c: Call & { [k: string]: unknown }) => Resp) | ((b: unknown) => Resp)) => responses.set(key, r),
    signInAs: (role: string | null) => {
      session = { user: { id: '00000000-0000-4000-8000-000000000001', email: 'admin@example.org' } }
      responses.set('admin_roles:select', { data: role ? [{ role }] : [] })
    },
    reset: () => { calls.length = 0; rpcs.length = 0; uploads.length = 0; removed.length = 0; invokes.length = 0; responses.clear(); session = null },
    last: (table: string, op: string) => [...calls].reverse().find((c) => c.table === table && c.op === op),
  }
}

export const fake = createFake()
