#!/usr/bin/env python3
"""Fixed evaluator for the North Yorkshire Crime Hypotheses example."""

from __future__ import annotations

import importlib.util
import json
import math
import subprocess
import sys
import urllib.parse
import urllib.request
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


DATES = ["2024-01", "2024-02", "2024-03"]
LOCATIONS = {
    "york": (53.9590, -1.0815),
    "harrogate": (53.9915, -1.5412),
    "scarborough": (54.2797, -0.4044),
    "northallerton": (54.3390, -1.4324),
}

EXAMPLE_DIR = Path(__file__).resolve().parent
REPO_DIR = EXAMPLE_DIR.parent.parent
CACHE_DIR = REPO_DIR / ".build" / "uk-crime-hypotheses"
CANDIDATE_PATH = EXAMPLE_DIR / "candidate.py"


@dataclass(frozen=True)
class Aggregate:
    count: int
    total: int

    @property
    def share(self) -> float:
        return self.count / self.total if self.total else 0.0


@dataclass(frozen=True)
class ScoredHypothesis:
    name: str
    score: float
    category: str
    a_label: str
    b_label: str
    a: Aggregate
    b: Aggregate
    lift: float
    z_score: float
    p_value: float
    effect_size: float


def main() -> int:
    records = load_records()
    context = build_context(records)
    candidate = load_candidate()
    hypotheses = list(candidate.hypotheses(context))

    if not hypotheses:
        print("No hypotheses returned by candidate.py", file=sys.stderr)
        return 2

    scored = []
    for hypothesis in hypotheses:
        try:
            scored.append(score_hypothesis(hypothesis, records))
        except Exception as error:
            print(f"skipped_hypothesis: {hypothesis.get('name', '<unnamed>')} ({error})", file=sys.stderr)

    if not scored:
        print("No hypotheses could be scored.", file=sys.stderr)
        return 2

    best = max(scored, key=lambda item: item.score)
    print("---")
    print(f"score: {best.score:.6f}")
    print(f"best_hypothesis: {best.name}")
    print(f"category: {best.category}")
    print(f"a: {best.a_label}")
    print(f"b: {best.b_label}")
    print(f"a_count: {best.a.count}")
    print(f"a_total: {best.a.total}")
    print(f"a_share: {best.a.share:.6f}")
    print(f"b_count: {best.b.count}")
    print(f"b_total: {best.b.total}")
    print(f"b_share: {best.b.share:.6f}")
    print(f"effect_size: {best.effect_size:.6f}")
    print(f"lift: {best.lift:.6f}")
    print(f"z_score: {best.z_score:.6f}")
    print(f"p_value: {best.p_value:.6g}")
    print(f"hypotheses_scored: {len(scored)}")
    print(f"records_months: {len(DATES)}")
    print(f"records_places: {len(LOCATIONS)}")
    return 0


def load_candidate():
    spec = importlib.util.spec_from_file_location("candidate", CANDIDATE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {CANDIDATE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not hasattr(module, "hypotheses"):
        raise RuntimeError("candidate.py must define hypotheses(context)")
    return module


def load_records() -> list[dict]:
    records = []
    for date in DATES:
        for place, (lat, lng) in LOCATIONS.items():
            crimes = fetch_crimes(place=place, date=date, lat=lat, lng=lng)
            counts = Counter(crime.get("category", "unknown") for crime in crimes)
            records.append(
                {
                    "place": place,
                    "date": date,
                    "total": len(crimes),
                    "counts": counts,
                }
            )
    return records


def fetch_crimes(place: str, date: str, lat: float, lng: float) -> list[dict]:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_file = CACHE_DIR / f"{date}-{place}.json"
    if cache_file.exists():
        return json.loads(cache_file.read_text())

    params = urllib.parse.urlencode({"date": date, "lat": lat, "lng": lng})
    url = f"https://data.police.uk/api/crimes-street/all-crime?{params}"
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "swift-autoresearch-uk-crime-example/0.1"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = response.read().decode("utf-8")
    except Exception:
        payload = subprocess.check_output(
            ["curl", "-fsSL", "--retry", "2", "--max-time", "60", url],
            text=True,
            timeout=75,
        )
    data = json.loads(payload)
    cache_file.write_text(json.dumps(data, indent=2, sort_keys=True))
    return data


def build_context(records: list[dict]) -> dict:
    totals = Counter()
    for record in records:
        totals.update(record["counts"])
    categories = sorted(totals)
    top_categories = [category for category, _ in totals.most_common(12)]
    return {
        "places": sorted(LOCATIONS),
        "dates": DATES[:],
        "categories": categories,
        "top_categories": top_categories,
    }


def score_hypothesis(hypothesis: dict, records: list[dict]) -> ScoredHypothesis:
    kind = hypothesis.get("kind")
    if kind == "category_share":
        return score_category_share(hypothesis, records)
    if kind == "recent_shift":
        return score_recent_shift(hypothesis, records)
    raise ValueError(f"unsupported kind: {kind}")


def score_category_share(hypothesis: dict, records: list[dict]) -> ScoredHypothesis:
    name = required(hypothesis, "name")
    category = required(hypothesis, "category")
    place = required(hypothesis, "place")
    reference = hypothesis.get("reference", "all_other")
    months = hypothesis.get("months")

    a = aggregate(records, category=category, places=[place], months=months)
    if reference == "all_other":
        b = aggregate(records, category=category, exclude_places=[place], months=months)
        b_label = "all_other"
    else:
        b = aggregate(records, category=category, places=[reference], months=months)
        b_label = reference

    return score_two_proportions(
        name=name,
        category=category,
        a_label=place,
        b_label=b_label,
        a=a,
        b=b,
        direction=hypothesis.get("direction", "different"),
    )


def score_recent_shift(hypothesis: dict, records: list[dict]) -> ScoredHypothesis:
    name = required(hypothesis, "name")
    category = required(hypothesis, "category")
    place = required(hypothesis, "place")
    recent_count = int(hypothesis.get("recent_months", 2))
    if recent_count <= 0 or recent_count >= len(DATES):
        raise ValueError("recent_months must be between 1 and len(DATES) - 1")

    earlier_months = DATES[:-recent_count]
    recent_months = DATES[-recent_count:]
    a = aggregate(records, category=category, places=[place], months=recent_months)
    b = aggregate(records, category=category, places=[place], months=earlier_months)

    return score_two_proportions(
        name=name,
        category=category,
        a_label=f"{place}_recent",
        b_label=f"{place}_earlier",
        a=a,
        b=b,
        direction=hypothesis.get("direction", "different"),
    )


def aggregate(
    records: list[dict],
    *,
    category: str,
    places: list[str] | None = None,
    exclude_places: list[str] | None = None,
    months: list[str] | None = None,
) -> Aggregate:
    place_set = set(places) if places else None
    exclude_set = set(exclude_places) if exclude_places else set()
    month_set = set(months) if months else None

    count = 0
    total = 0
    for record in records:
        if place_set is not None and record["place"] not in place_set:
            continue
        if record["place"] in exclude_set:
            continue
        if month_set is not None and record["date"] not in month_set:
            continue
        count += record["counts"].get(category, 0)
        total += record["total"]
    return Aggregate(count=count, total=total)


def score_two_proportions(
    *,
    name: str,
    category: str,
    a_label: str,
    b_label: str,
    a: Aggregate,
    b: Aggregate,
    direction: str,
) -> ScoredHypothesis:
    if a.total <= 0 or b.total <= 0:
        raise ValueError("empty comparison group")

    pooled = (a.count + b.count) / (a.total + b.total)
    standard_error = math.sqrt(pooled * (1 - pooled) * (1 / a.total + 1 / b.total))
    z_score = (a.share - b.share) / standard_error if standard_error else 0.0
    p_value = math.erfc(abs(z_score) / math.sqrt(2))
    lift = (a.share + 1e-12) / (b.share + 1e-12)
    effect_size = a.share - b.share

    directional_match = (
        direction == "different"
        or (direction == "higher" and effect_size > 0)
        or (direction == "lower" and effect_size < 0)
    )
    if directional_match:
        score = abs(z_score) * math.log1p(abs(math.log(lift)))
    else:
        score = 0.0

    return ScoredHypothesis(
        name=name,
        score=score,
        category=category,
        a_label=a_label,
        b_label=b_label,
        a=a,
        b=b,
        lift=lift,
        z_score=z_score,
        p_value=p_value,
        effect_size=effect_size,
    )


def required(hypothesis: dict, key: str) -> str:
    value = hypothesis.get(key)
    if not value:
        raise ValueError(f"hypothesis missing {key}")
    return str(value)


if __name__ == "__main__":
    raise SystemExit(main())
