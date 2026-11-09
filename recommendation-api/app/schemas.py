"""Request/response contract, version 1. See docs/recommendation-api.md."""
from typing import Literal

from pydantic import BaseModel, Field, field_validator

DiningPurpose = Literal["solo", "friends", "group", "senior", "junior", "professor"]


class Location(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class RecommendRequest(BaseModel):
    university_id: str = Field(min_length=1, max_length=64)
    # Candidate Kakao place ids the caller already has (the model ranks them).
    candidate_place_ids: list[str] = Field(min_length=1, max_length=200)
    location: Location | None = None
    dining_purpose: DiningPurpose | None = None
    budget_max_krw: int | None = Field(default=None, ge=0)
    budget_min_krw: int | None = Field(default=None, ge=0)
    preferred_categories: list[str] = Field(default_factory=list, max_length=20)
    max_results: int = Field(default=10, ge=1, le=50)

    @field_validator("candidate_place_ids")
    @classmethod
    def _unique_non_blank(cls, v: list[str]) -> list[str]:
        if any(not p.strip() for p in v):
            raise ValueError("place ids must not be blank")
        return list(dict.fromkeys(v))


class ModelInfo(BaseModel):
    version: str
    # True for the test mock. A client must NOT present is_mock=true results as
    # real model predictions.
    is_mock: bool


class RankedPlace(BaseModel):
    place_id: str
    rank: int = Field(ge=1)
    # Optional: real models may omit it. The mock never invents scores.
    score: float | None = None


class RecommendResponse(BaseModel):
    model: ModelInfo
    results: list[RankedPlace]


class HealthResponse(BaseModel):
    status: Literal["ok"]
    model: ModelInfo
