"""Recommendation service skeleton.

THIS IS NOT A MODEL. `/v1/recommend` is served only by a clearly labelled test
mock (ENABLE_MOCK_MODEL=true) that keeps the caller's order and invents no
score. Without that flag the endpoint answers 503, so a deployment cannot
pretend to have a trained model. Replace `mock_rank` with the real inference
when the model and its contract are available.
"""
import logging
import time

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from .config import allowed_origins, mock_enabled
from .schemas import HealthResponse, ModelInfo, RankedPlace, RecommendRequest, RecommendResponse

log = logging.getLogger("recommendation-api")
logging.basicConfig(level=logging.INFO, format='{"ts":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}')

MOCK_MODEL = ModelInfo(version="mock-0", is_mock=True)

app = FastAPI(title="Meogeobojo recommendation API", version="1")
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins(),
    allow_methods=["GET", "POST"],
    allow_headers=["authorization", "content-type"],
)


def mock_rank(req: RecommendRequest) -> list[RankedPlace]:
    """Keeps the caller's candidate order. No scores are made up."""
    return [RankedPlace(place_id=p, rank=i + 1) for i, p in enumerate(req.candidate_place_ids[: req.max_results])]


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(status="ok", model=MOCK_MODEL)


@app.post("/v1/recommend", response_model=RecommendResponse)
def recommend(req: RecommendRequest) -> RecommendResponse:
    if not mock_enabled():
        # No real model is connected: say so instead of returning anything.
        raise HTTPException(status_code=503, detail="no recommendation model is configured")
    started = time.perf_counter()
    results = mock_rank(req)
    log.info("mock recommend university=%s n=%d latency_ms=%d", req.university_id, len(results), (time.perf_counter() - started) * 1000)
    return RecommendResponse(model=MOCK_MODEL, results=results)
