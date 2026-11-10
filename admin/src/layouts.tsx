import { BarChart3, Images, BookOpen, Sparkles, Building2, ClipboardList, Flag, LayoutDashboard, LogOut, Megaphone, Settings, Store, Trophy, Users, UtensilsCrossed } from 'lucide-react'
import { NavLink, Navigate, Outlet } from 'react-router-dom'
import { Spinner } from '@/components/ui'
import { useAuth } from '@/lib/auth'
import { ROLE_LABEL, type Role } from '@/lib/roles'
import { cn } from '@/lib/utils'

const NAV: { to: string; label: string; icon: typeof Store; min: Role }[] = [
  { to: '/', label: '개요', icon: LayoutDashboard, min: 'moderator' },
  { to: '/restaurants', label: '식당', icon: Store, min: 'admin' },
  { to: '/menus', label: '메뉴·가격', icon: UtensilsCrossed, min: 'admin' },
  { to: '/photos', label: '사진 관리', icon: Images, min: 'admin' },
  { to: '/universities', label: '대학교', icon: Building2, min: 'admin' },
  { to: '/cafeteria', label: '학식', icon: BookOpen, min: 'admin' },
  { to: '/users', label: '사용자', icon: Users, min: 'admin' },
  { to: '/moderation', label: '리뷰·신고', icon: Flag, min: 'moderator' },
  { to: '/missions', label: '미션 관리', icon: Trophy, min: 'moderator' },
  { to: '/content', label: '앱 콘텐츠', icon: Megaphone, min: 'admin' },
  { to: '/audit', label: '활동 기록', icon: ClipboardList, min: 'admin' },
  { to: '/recommendations', label: '추천', icon: Sparkles, min: 'admin' },
  { to: '/analytics', label: '분석', icon: BarChart3, min: 'moderator' },
  { to: '/settings', label: '설정', icon: Settings, min: 'moderator' },
]

/** Redirects unless signed in AND the database granted an admin role. */
export function RequireAdmin() {
  const { state, signOut } = useAuth()
  if (state.status === 'loading') return <div className="grid min-h-screen place-items-center"><Spinner /></div>
  if (state.status === 'signedOut') return <Navigate to="/login" replace />
  if (state.status === 'denied') {
    return (
      <div className="grid min-h-screen place-items-center p-6">
        <div className="max-w-sm space-y-4 text-center">
          <h1 className="text-xl font-bold">접근 권한이 없어요</h1>
          <p className="text-sm text-muted">{state.email} 계정에는 관리자 역할이 없어요. 관리자에게 역할 부여를 요청해 주세요.</p>
          <button className="text-sm font-semibold text-brand-strong underline" onClick={() => void signOut()}>로그아웃</button>
        </div>
      </div>
    )
  }
  return <Shell />
}

function Shell() {
  const { state, signOut, can } = useAuth()
  if (state.status !== 'ready') return null
  return (
    <div className="min-h-screen md:grid md:grid-cols-[15rem_1fr]">
      <aside className="border-b border-line bg-white md:sticky md:top-0 md:h-screen md:border-b-0 md:border-r">
        <div className="flex items-center gap-2 px-5 py-4">
          <span className="size-3 rounded-full bg-brand-strong" />
          <span className="text-lg font-extrabold">먹어보조 <span className="font-medium text-muted">관리자</span></span>
        </div>
        <nav className="flex gap-1 overflow-x-auto px-3 pb-3 md:flex-col md:overflow-visible">
          {NAV.filter((n) => can(n.min)).map(({ to, label, icon: Icon }) => (
            <NavLink key={to} to={to} end={to === '/'}
              className={({ isActive }) => cn('flex shrink-0 items-center gap-2.5 rounded-xl px-3 py-2 text-sm font-medium', isActive ? 'bg-brand text-brand-ink' : 'text-ink/80 hover:bg-page')}>
              <Icon className="size-4" />{label}
            </NavLink>
          ))}
        </nav>
        <div className="hidden border-t border-line p-4 text-xs text-muted md:absolute md:bottom-0 md:block md:w-full">
          <div className="truncate font-medium text-ink">{state.email}</div>
          <div className="mb-2">{ROLE_LABEL[state.role]}</div>
          <button className="inline-flex items-center gap-1.5 font-semibold text-brand-strong" onClick={() => void signOut()}><LogOut className="size-3.5" />로그아웃</button>
        </div>
      </aside>
      <main className="min-w-0 p-5 md:p-8"><Outlet /></main>
    </div>
  )
}

/** Role gate inside a page tree (UI only; RLS is the real check). */
export function RequireRole({ min }: { min: Role }) {
  const { can } = useAuth()
  if (!can(min)) {
    return <div role="alert" className="rounded-2xl border border-line bg-white p-8 text-center text-sm text-muted">이 페이지를 볼 권한이 없어요.</div>
  }
  return <Outlet />
}
