import { zodResolver } from '@hookform/resolvers/zod'
import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { Navigate } from 'react-router-dom'
import { z } from 'zod'
import { Button, Card, Field, Input } from '@/components/ui'
import { useAuth } from '@/lib/auth'
import { supabaseConfigured } from '@/lib/supabase'

const schema = z.object({
  email: z.string().min(1, '이메일을 입력해 주세요').email('올바른 이메일이 아니에요'),
  password: z.string().min(1, '비밀번호를 입력해 주세요'),
})
type Values = z.infer<typeof schema>

export default function LoginPage() {
  const { state, signIn } = useAuth()
  const [error, setError] = useState<string | null>(null)
  const { register, handleSubmit, formState } = useForm<Values>({ resolver: zodResolver(schema) })
  if (state.status === 'ready' || state.status === 'denied') return <Navigate to="/" replace />
  return (
    <div className="grid min-h-screen place-items-center p-6">
      <Card className="w-full max-w-sm space-y-5">
        <div>
          <div className="mb-2 flex items-center gap-2"><span className="size-3 rounded-full bg-brand-strong" /><span className="text-lg font-extrabold">먹어보조 관리자</span></div>
          <p className="text-sm text-muted">관리자 계정으로 로그인해 주세요.</p>
        </div>
        {!supabaseConfigured && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-xs text-amber-800">VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY가 설정되지 않았어요.</p>}
        <form className="space-y-4" onSubmit={handleSubmit(async (v) => setError(await signIn(v.email, v.password)))}>
          <Field label="이메일" htmlFor="email" error={formState.errors.email?.message}><Input id="email" type="email" autoComplete="username" {...register('email')} /></Field>
          <Field label="비밀번호" htmlFor="password" error={formState.errors.password?.message}><Input id="password" type="password" autoComplete="current-password" {...register('password')} /></Field>
          {error && <p role="alert" className="text-sm text-red-600">{error}</p>}
          <Button type="submit" className="w-full" disabled={formState.isSubmitting}>로그인</Button>
        </form>
      </Card>
    </div>
  )
}
