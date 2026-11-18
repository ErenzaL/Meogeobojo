-- =============================================================================
-- AI restaurant chat: request counters for the `ai-restaurant-chat` Edge Function (free-tier protection).
--
-- The function counts requests per user (or per hashed IP for anonymous visitors) and globally per day, so one
-- visitor cannot burn the Gemini free quota. The counters hold NO message text and NO raw IP: only a bucket name such
-- as "day:anon:3fa9..." (a truncated SHA-256) or "global", a window start and a hit count.
--
--   * Only the service role (the Edge Function) can read or call anything here; anon / authenticated can do nothing.
--   * Old windows are removed opportunistically; nothing grows without bound.
--   * Without this migration the function still works: it then limits per minute inside one running instance only.
--
-- Additive and idempotent. To remove: drop function public.ai_chat_hit(text, int, int); drop table public.ai_chat_usage;
-- =============================================================================
create table if not exists public.ai_chat_usage (
  bucket       text        not null check (char_length(bucket) <= 80),
  window_start timestamptz not null,
  hits         integer     not null default 0,
  primary key (bucket, window_start)
);
comment on table public.ai_chat_usage is 'Rate-limit counters of the ai-restaurant-chat Edge Function. No message text, no raw IP.';

alter table public.ai_chat_usage enable row level security;
revoke all on public.ai_chat_usage from anon, authenticated;

create or replace function public.ai_chat_hit(p_bucket text, p_window_seconds integer, p_limit integer)
returns table (allowed boolean, used integer, retry_after integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  ws timestamptz;
  h  integer;
begin
  if p_window_seconds < 1 or p_window_seconds > 172800 or p_limit < 1 or char_length(p_bucket) > 80 then
    raise exception 'invalid arguments' using errcode = '22023';
  end if;
  ws := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  insert into public.ai_chat_usage as u (bucket, window_start, hits) values (p_bucket, ws, 1)
    on conflict (bucket, window_start) do update set hits = u.hits + 1
    returning u.hits into h;
  if random() < 0.01 then
    delete from public.ai_chat_usage where window_start < now() - interval '3 days';
  end if;
  return query select h <= p_limit, h,
    greatest(1, ceil(extract(epoch from (ws + make_interval(secs => p_window_seconds) - now())))::integer);
end;
$$;

revoke all on function public.ai_chat_hit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.ai_chat_hit(text, integer, integer) to service_role;
