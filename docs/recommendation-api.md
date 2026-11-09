# Recommendation API contract (v1, draft)

**Status: no recommendation model is connected.** The model is being built
separately. This document is the integration contract the app, the database and
the optional FastAPI service are prepared for; the real contract may differ, and
the transport must then be adapted (DTOs: `lib/features/recommendation/api/`,
schemas: `recommendation-api/app/schemas.py`).

Nothing in the product presents a mock result as a model prediction: every response
carries `model.is_mock`, the app maps it to `RecommendationSource.mock`, and the
admin page labels it.

## `POST /v1/recommend`
Request (JSON):
| Field | Type | Notes |
|---|---|---|
| `university_id` | string | required |
| `candidate_place_ids` | string[1..200] | Kakao place ids the caller has; the model ranks them |
| `location` | `{latitude, longitude}` | optional |
| `dining_purpose` | `solo\|friends\|group\|senior\|junior\|professor` | optional |
| `budget_min_krw`, `budget_max_krw` | int ≥ 0 | optional |
| `preferred_categories` | string[≤20] | optional |
| `max_results` | int 1..50 (default 10) | |

Response 200:
```json
{ "model": { "version": "v1", "is_mock": false },
  "results": [ { "place_id": "123", "rank": 1, "score": 0.83 } ] }
```
`score` is optional; a model that has none omits it. `422` invalid request, `503` no
model available. The caller validates before sending, applies a timeout (default 4 s)
and, on any failure, falls back to its own order and reports `fallback`
(`ResilientRecommender`). Unknown place ids in a response are dropped.

## `GET /health`
`{"status":"ok","model":{"version":"…","is_mock":…}}`

## Telemetry
The server (never the client) records one row per request in
`public.recommendation_requests`: model version, `is_mock`, status
(`ok|error|timeout|fallback`), latency, error code, university. No user ids, no
preferences, no place lists. Admins see aggregates in the dashboard (추천 page) via
`admin_recommendation_stats()`.

## The FastAPI service (`recommendation-api/`)
A skeleton with `/health` and a **mock** `/v1/recommend` that only answers when
`ENABLE_MOCK_MODEL=true`, keeps the caller's order and returns no scores; otherwise 503.
It is **not** in `render.yaml` and must not be deployed as if it were a model. Deploy
only when real inference replaces `mock_rank`: Docker (`Dockerfile`), start command
`uvicorn app.main:app --host 0.0.0.0 --port $PORT`, health check `/health`, env
`ALLOWED_ORIGINS` (CORS allow-list), pinned `requirements.txt`. Render free web
services spin down when idle, so a cold start can exceed the app's 4 s timeout; use a
paid always-on instance for production and check Render's current plan limits.

```bash
cd recommendation-api && python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt && python -m pytest
```
