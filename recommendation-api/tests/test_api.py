import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)
BODY = {"university_id": "u1", "candidate_place_ids": ["a", "b", "c", "b"], "max_results": 2}


def test_health_reports_a_mock_model():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok", "model": {"version": "mock-0", "is_mock": True}}


def test_recommend_refuses_without_an_explicit_mock_flag(monkeypatch):
    monkeypatch.delenv("ENABLE_MOCK_MODEL", raising=False)
    r = client.post("/v1/recommend", json=BODY)
    assert r.status_code == 503


def test_mock_keeps_order_dedupes_and_invents_no_scores(monkeypatch):
    monkeypatch.setenv("ENABLE_MOCK_MODEL", "true")
    r = client.post("/v1/recommend", json=BODY)
    assert r.status_code == 200
    data = r.json()
    assert data["model"] == {"version": "mock-0", "is_mock": True}
    assert [x["place_id"] for x in data["results"]] == ["a", "b"]
    assert [x["rank"] for x in data["results"]] == [1, 2]
    assert all(x["score"] is None for x in data["results"])


@pytest.mark.parametrize(
    "patch",
    [
        {"candidate_place_ids": []},
        {"candidate_place_ids": [" "]},
        {"university_id": ""},
        {"max_results": 0},
        {"budget_max_krw": -1},
        {"location": {"latitude": 91, "longitude": 0}},
        {"dining_purpose": "nobody"},
    ],
)
def test_invalid_requests_are_rejected(patch, monkeypatch):
    monkeypatch.setenv("ENABLE_MOCK_MODEL", "true")
    assert client.post("/v1/recommend", json={**BODY, **patch}).status_code == 422


def test_cors_allows_only_configured_origins():
    r = client.get("/health", headers={"origin": "https://evil.example"})
    assert "access-control-allow-origin" not in r.headers
