import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { Button, Card } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import MissionFields from './MissionFields'
import type { Campaign, University } from './model'
import { MissionPreview } from './previews'
import { emptyMissionForm, missionPayload, validateMission, type MissionForm as Form } from './schema'

/** Create a mission. It is created as a hidden DRAFT (students never see it); it is then
 *  edited, previewed, published or scheduled from the publishing toolbar. */
export default function MissionForm({ campaigns, universities, onDone }: { campaigns: Campaign[]; universities: University[]; onDone: (msg: string, createdId?: string) => void }) {
  const qc = useQueryClient()
  const [f, setF] = useState<Form>(() => emptyMissionForm())
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [err, setErr] = useState<string | null>(null)
  const set = (patch: Partial<Form>) => setF((p) => ({ ...p, ...patch }))

  const save = useMutation({
    mutationFn: async () => {
      const e = validateMission(f, true); setErrors(e)
      if (Object.keys(e).length) throw new Error('입력값을 확인해 주세요')
      const { data, error } = await supabase.rpc('admin_save_mission', { p: { ...missionPayload(f), status: 'draft' } })
      if (error) throw error
      return data as string
    },
    onSuccess: async (id) => {
      await qc.invalidateQueries({ queryKey: ['missions-admin'] })
      onDone('초안으로 만들었어요. 앱에는 아직 보이지 않아요. 게시 도구로 게시하거나 예약해 주세요.', id)
    },
    onError: (e) => setErr(errorMessage(e)),
  })

  return (
    <div className="grid gap-4 xl:grid-cols-[1fr_20rem]">
      <Card className="space-y-4">
        <h2 className="text-lg font-bold">미션 만들기</h2>
        <MissionFields f={f} set={set} errors={errors} isNew campaigns={campaigns} universities={universities} />
        {err && <p role="alert" className="text-sm text-red-600">{err}</p>}
        <div className="flex gap-2"><Button disabled={save.isPending} onClick={() => save.mutate()}>초안으로 만들기</Button><Button variant="outline" onClick={() => onDone('')}>닫기</Button></div>
      </Card>
      <div className="space-y-3 self-start">
        <p className="text-sm font-semibold">앱 미리보기</p>
        <MissionPreview title={f.title} description={f.description} points={Number(f.reward_points) || 0} target={Number(f.target_count) || 1} badge={f.rule_type === 'missions_completed'} badgeMascot={f.badge_mascot} />
        <p className="text-xs text-muted">진행도는 0에서 시작하는 모습이에요. 만들기만 해서는 앱에 보이지 않아요.</p>
      </div>
    </div>
  )
}
