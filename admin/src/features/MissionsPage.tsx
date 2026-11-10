import { useState } from 'react'
import { Button, PageHeader } from '@/components/ui'
import { useAuth } from '@/lib/auth'
import CampaignList from './missions/CampaignList'
import Contributions from './missions/Contributions'
import MissionAnalytics from './missions/MissionAnalytics'
import MissionList from './missions/MissionList'
import UserProgress from './missions/UserProgress'
import type { Role } from '@/lib/roles'

const TABS: { id: string; label: string; min: Role }[] = [
  { id: 'missions', label: '미션', min: 'admin' },
  { id: 'campaigns', label: '캠페인', min: 'admin' },
  { id: 'analytics', label: '분석', min: 'admin' },
  { id: 'users', label: '사용자 진행', min: 'admin' },
  { id: 'contributions', label: '기여 검토', min: 'moderator' },
]

/** 미션 관리: one sidebar entry, five tabs. Every write is a database function
 *  that re-checks the caller's role and writes the audit log; this page only
 *  hides what the role cannot use. */
export default function MissionsPage() {
  const { can } = useAuth()
  const tabs = TABS.filter((t) => can(t.min))
  const [tab, setTab] = useState(tabs[0]?.id ?? 'contributions')
  return (
    <>
      <PageHeader title="미션 관리" description="월간 캠페인과 미션, 보상, 분석, 사용자 진행을 관리해요. 게시한 내용은 Supabase를 통해 앱에 바로 반영돼요." />
      <div role="tablist" className="mb-5 flex flex-wrap gap-2">
        {tabs.map((t) => <Button key={t.id} role="tab" aria-selected={tab === t.id} variant={tab === t.id ? 'soft' : 'outline'} onClick={() => setTab(t.id)}>{t.label}</Button>)}
      </div>
      {tab === 'missions' && <MissionList />}
      {tab === 'campaigns' && <CampaignList />}
      {tab === 'analytics' && <MissionAnalytics />}
      {tab === 'users' && <UserProgress />}
      {tab === 'contributions' && <Contributions />}
    </>
  )
}
