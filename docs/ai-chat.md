# 먹어보조 AI chat (restaurant assistant)

A floating mascot opens a chat that understands Korean, English and Chinese, recommends **real** restaurants from the
database (three by default), and shows each one's **real** menu.

## How it fits together

```
user message
  → Edge Function `ai-restaurant-chat` (action "interpret"): Gemini → validated JSON
        hard constraints (price, walking minutes, cuisine, named dish, avoid spicy, open now)
        soft preferences (mood dishes, cheap, closer, group size), count, intent, which earlier result is meant
  → the app's ONE recommendation engine (`rankRestaurants`, conditions, V3 score, hours, budget on real menu prices)
        + `lib/features/chat/logic/chat_engine.dart` for what only a conversation asks (exact price range, minutes, a dish)
  → Edge Function (action "explain"): reads the shortlisted restaurants + menus from Supabase BY ID (published only),
        Gemini words the reply; a sentence with a number that is not a fact is dropped
  → Flutter cards (photo, name, category, campus, walk, real price, reason) → tap → the real menu → details / directions
```

Why the ranking is not in the Edge Function: the recommendation engine is Dart code in the app. Re-implementing it in
TypeScript would create a second engine that drifts from Home. The function therefore does language (interpret / explain),
verification and protection; the app ranks.

Hard constraints are never relaxed silently. If nothing matches, the chat says so and **offers** one adjustment (a higher
budget, a wider distance, other food types, other dishes); it is applied only when the user agrees.

## Files

| | |
|---|---|
| `supabase/functions/ai-restaurant-chat/{index,core,core_test}.ts` | the function (`deno task test`) |
| `supabase/migrations/20261127000100_ai_chat_rate_limit.sql` | optional daily counters (service role only) |
| `lib/features/chat/` | models, API client, search adapter, controller, widgets |
| `test/features/chat/` | adapter, controller and UI tests (13 screen sizes) |

## Secrets and limits

* `GEMINI_API_KEY` and `GEMINI_MODEL` are **Edge Function secrets only**. The model is read from the secret, never
  hardcoded, and nothing falls back to another model. They must **not** be in the app's `.env` (it is bundled into every
  build); `bash scripts/check_bundled_env.sh` checks that.
* Gemini 429 → code `quota`; the app answers with its own engine and the user's filters and says the AI is busy.
* Protection: the function is deployed with `verify_jwt = false` (the project uses publishable keys), so it checks the
  publishable key or a user session itself. Limits: 12 requests/minute per user or hashed IP (per instance), 200/day per
  user or IP and 1,200/day overall (database counters; tune with `AI_CHAT_PER_MINUTE`, `AI_CHAT_PER_DAY`,
  `AI_CHAT_GLOBAL_PER_DAY`). Messages are cut to 400 characters, history to 6 turns, output to 2,048 tokens, requests time out
  after 12 s, and the same question within two minutes is answered from memory.
* Conversation state lives in the app session only. Nothing is stored server-side except the counters (no text, no IP).

## What is NOT in the data (so the chat never claims it)

* **Spice level, allergens, vegetarian/halal**: no such field. "Not spicy" only leaves out dishes whose name says spicy, and
  the card says spice level is not on record.
* **Group suitability, solo-friendliness, dining purposes**: no usable data (`dining_purposes` is no longer managed). A group
  size is kept as a soft preference but cannot be checked.
* **Opening status** is shown only when a last order is on record and is not from the simulated demo dataset.

## Deploy

```bash
supabase link --project-ref jnnofemlolwdyonfhzje        # already linked
supabase functions deploy ai-restaurant-chat --no-verify-jwt   # confirm the production prompt
# optional, in the SQL editor: supabase/migrations/20261127000100_ai_chat_rate_limit.sql
```
