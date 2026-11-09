export type Role = 'moderator' | 'admin' | 'super_admin'

const RANK: Record<Role, number> = { moderator: 1, admin: 2, super_admin: 3 }

export const isRole = (v: unknown): v is Role => typeof v === 'string' && v in RANK

/** UI convenience only. The database enforces the same rule with RLS (has_role). */
export const roleAtLeast = (role: Role | null | undefined, min: Role) =>
  role != null && RANK[role] >= RANK[min]

export const ROLE_LABEL: Record<Role, string> = {
  moderator: '모더레이터',
  admin: '관리자',
  super_admin: '최고 관리자',
}
