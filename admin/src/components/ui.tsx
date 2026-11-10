import { cva, type VariantProps } from 'class-variance-authority'
import { AlertTriangle, Loader2, X } from 'lucide-react'
import { forwardRef, useEffect, useRef, type ButtonHTMLAttributes, type InputHTMLAttributes, type ReactNode, type SelectHTMLAttributes, type TextareaHTMLAttributes } from 'react'
import { cn } from '@/lib/utils'

const buttonVariants = cva(
  'inline-flex items-center justify-center gap-2 rounded-xl text-sm font-semibold transition-colors disabled:pointer-events-none disabled:opacity-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-strong',
  {
    variants: {
      variant: {
        primary: 'bg-brand-strong text-white hover:bg-[#d95a14]',
        soft: 'bg-brand text-brand-ink hover:bg-[#ffbd5c]',
        outline: 'border border-line bg-white text-ink hover:bg-page',
        ghost: 'text-ink hover:bg-black/5',
        danger: 'bg-red-600 text-white hover:bg-red-700',
      },
      size: { sm: 'h-8 px-3', md: 'h-10 px-4', icon: 'h-9 w-9' },
    },
    defaultVariants: { variant: 'primary', size: 'md' },
  },
)

export type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & VariantProps<typeof buttonVariants>
export const Button = forwardRef<HTMLButtonElement, ButtonProps>(({ className, variant, size, type = 'button', ...p }, ref) => (
  <button ref={ref} type={type} className={cn(buttonVariants({ variant, size }), className)} {...p} />
))
Button.displayName = 'Button'

const field = 'w-full rounded-xl border border-line bg-white px-3 text-sm placeholder:text-muted/70 focus-visible:outline-2 focus-visible:outline-brand-strong disabled:bg-page'
export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(({ className, ...p }, ref) => (
  <input ref={ref} className={cn(field, 'h-10', className)} {...p} />
))
Input.displayName = 'Input'
export const Textarea = forwardRef<HTMLTextAreaElement, TextareaHTMLAttributes<HTMLTextAreaElement>>(({ className, ...p }, ref) => (
  <textarea ref={ref} className={cn(field, 'min-h-24 py-2', className)} {...p} />
))
Textarea.displayName = 'Textarea'
export const Select = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement>>(({ className, ...p }, ref) => (
  <select ref={ref} className={cn(field, 'h-10', className)} {...p} />
))
Select.displayName = 'Select'

export function Field({ label, error, hint, children, htmlFor }: { label: string; error?: string; hint?: string; children: ReactNode; htmlFor?: string }) {
  return (
    <div className="space-y-1.5">
      <label htmlFor={htmlFor} className="text-sm font-medium">{label}</label>
      {children}
      {hint && !error && <p className="text-xs text-muted">{hint}</p>}
      {error && <p role="alert" className="text-xs text-red-600">{error}</p>}
    </div>
  )
}

export const Card = ({ className, ...p }: React.HTMLAttributes<HTMLDivElement>) => (
  <div className={cn('rounded-2xl border border-line bg-white p-5', className)} {...p} />
)

const tones = {
  neutral: 'bg-page text-muted',
  green: 'bg-green-100 text-green-800',
  amber: 'bg-amber-100 text-amber-800',
  red: 'bg-red-100 text-red-800',
  brand: 'bg-brand/40 text-brand-ink',
} as const
export const Badge = ({ tone = 'neutral', children }: { tone?: keyof typeof tones; children: ReactNode }) => (
  <span className={cn('inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium', tones[tone])}>{children}</span>
)

export const Spinner = () => <Loader2 className="size-5 animate-spin text-muted" aria-label="불러오는 중" />
export const Skeleton = ({ className }: { className?: string }) => <div className={cn('animate-pulse rounded-lg bg-black/5', className)} />

export function PageHeader({ title, description, actions }: { title: string; description?: string; actions?: ReactNode }) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{title}</h1>
        {description && <p className="mt-1 text-sm text-muted">{description}</p>}
      </div>
      {actions && <div className="flex gap-2">{actions}</div>}
    </div>
  )
}

export const EmptyState = ({ children }: { children: ReactNode }) => (
  <div className="rounded-2xl border border-dashed border-line p-10 text-center text-sm text-muted">{children}</div>
)

export function ErrorState({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const msg = error instanceof Error ? error.message : typeof error === 'object' && error && 'message' in error ? String((error as { message: unknown }).message) : '문제가 생겼어요'
  return (
    <div role="alert" className="flex items-center gap-3 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-800">
      <AlertTriangle className="size-5 shrink-0" />
      <span className="flex-1">{msg}</span>
      {onRetry && <Button size="sm" variant="outline" onClick={onRetry}>다시 시도</Button>}
    </div>
  )
}

/** A form dialog (native <dialog>: focus trap, Esc to close). */
export function Modal({ open, title, onClose, children }: { open: boolean; title: string; onClose: () => void; children: ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => {
    const d = ref.current
    if (!d) return
    if (open && !d.open) d.showModal?.()
    if (!open && d.open) d.close?.()
  }, [open])
  if (!open) return null
  return (
    <dialog ref={ref} onCancel={onClose} aria-label={title} className="m-auto max-h-[90vh] w-[min(36rem,94vw)] overflow-auto rounded-2xl border border-line p-6 backdrop:bg-black/40">
      <div className="mb-4 flex items-start justify-between gap-3">
        <h2 className="text-lg font-bold">{title}</h2>
        <button type="button" aria-label="닫기" onClick={onClose} className="rounded-lg p-1 text-muted hover:bg-black/5"><X className="size-5" /></button>
      </div>
      {children}
    </dialog>
  )
}

/** Confirmation for important changes. [reason] adds a required reason field. */
export function ConfirmDialog({ open, title, description, confirmLabel = '확인', danger, askReason, onConfirm, onCancel, busy }: {
  open: boolean; title: string; description?: string; confirmLabel?: string; danger?: boolean
  askReason?: boolean; busy?: boolean; onConfirm: (reason: string) => void; onCancel: () => void
}) {
  const ref = useRef<HTMLDialogElement>(null)
  const reason = useRef<HTMLTextAreaElement>(null)
  useEffect(() => {
    const d = ref.current
    if (!d) return
    if (open && !d.open) d.showModal?.()
    if (!open && d.open) d.close?.()
  }, [open])
  if (!open) return null
  return (
    <dialog ref={ref} onCancel={onCancel} className="m-auto w-[min(28rem,92vw)] rounded-2xl border border-line p-6 backdrop:bg-black/40">
      <h2 className="text-lg font-bold">{title}</h2>
      {description && <p className="mt-2 text-sm text-muted">{description}</p>}
      {askReason && (
        <div className="mt-4">
          <Field label="사유 (필수)" htmlFor="reason"><Textarea id="reason" ref={reason} /></Field>
        </div>
      )}
      <div className="mt-6 flex justify-end gap-2">
        <Button variant="outline" onClick={onCancel} disabled={busy}>취소</Button>
        <Button variant={danger ? 'danger' : 'primary'} disabled={busy}
          onClick={() => {
            const r = reason.current?.value.trim() ?? ''
            if (askReason && !r) { reason.current?.focus(); return }
            onConfirm(r)
          }}>
          {busy && <Loader2 className="size-4 animate-spin" />}{confirmLabel}
        </Button>
      </div>
    </dialog>
  )
}
