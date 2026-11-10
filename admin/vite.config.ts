/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { execSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

/** Which CODE this Admin build contains. Render sets RENDER_GIT_COMMIT; locally we ask git. This is
 *  about code deployment only: published CONTENT lives in Supabase and never needs a rebuild. */
function gitCommit(): string {
  if (process.env.RENDER_GIT_COMMIT) return process.env.RENDER_GIT_COMMIT
  try { return execSync('git rev-parse HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim() } catch { return 'unknown' }
}

export default defineConfig({
  plugins: [react(), tailwindcss()],
  define: { __BUILD_INFO__: JSON.stringify({ commit: gitCommit(), builtAt: new Date().toISOString() }) },
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    globals: true,
    css: false,
  },
})
