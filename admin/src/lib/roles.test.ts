import { describe, expect, it } from 'vitest'
import { isRole, roleAtLeast } from './roles'

describe('roles', () => {
  it('orders moderator < admin < super_admin', () => {
    expect(roleAtLeast('super_admin', 'admin')).toBe(true)
    expect(roleAtLeast('admin', 'admin')).toBe(true)
    expect(roleAtLeast('moderator', 'admin')).toBe(false)
    expect(roleAtLeast('admin', 'super_admin')).toBe(false)
  })
  it('no role means no access', () => {
    expect(roleAtLeast(null, 'moderator')).toBe(false)
    expect(roleAtLeast(undefined, 'moderator')).toBe(false)
  })
  it('recognises only known roles', () => {
    expect(isRole('admin')).toBe(true)
    expect(isRole('owner')).toBe(false)
    expect(isRole(undefined)).toBe(false)
  })
})
