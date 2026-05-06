#!/usr/bin/env python3
"""Fixed evaluator for the UK Crime Holdout example.

The mutable candidate sees only the discovery months. This evaluator then
checks the selected claim on a held-out month.
"""

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


DISCOVERY_DATES = ["2024-01", "2024-02"]
HOLDOUT_DATES = ["2024-03"]
ALL_DATES = DISCOVERY_DATES + HOLDOUT_DATES
LOCATIONS = {
    "york": (53.9590, -1.0815),
    "harrogate": (53.9915, -1.5412),
    "scarborough": (54.2797, -0.4044),
    "northallerton": (54.3390, -1.4324),
}

EXAMPLE_DIR = Path(__file__).resolve().parent
REPO_DIR = EXAMPLE_DIR.parent.parent
CACHE_DIR = REPO_DIR / ".build" / "05-uk-crime-holdout"
CANDIDATE_PATH = EXAMPLE_DIR / "candidate.py"


@dataclass(frozen=True)
class Aggregate:
    count: int
    total: int

    @property
    def share(self) -> float:
        return self.count / self.total if self.total else 0.0


@dataclass(frozen=True)
class PairScore:
    name: str
    category: str
    a_label: str
    b_label: str
    a: Aggregate
    b: Aggregate
    lift: float
    z_score: float
    p_value: float
    effect_size: float
    score: float


def main() -> int:
    records = load_records()
    context = build_discovery_context(records)
    candidate = load_candidate()
    claim = candidate.claim(context)

    if not isinstance(claim, dict):
        print("candidate.py claim(context) must return a dictionary", file=sys.stderr)
        return 2

    try:
        discovery = score_claim(claim, records, DISCOVERY_DATES)
        holdout = score_claim(claim, records, HOLDOUT_DATES)
    except Exception as error:
        print(f"Could not score claim: {error}", file=sys.stderr)
        return 2

    score = holdout.score if discovery.score > 0 and holdout.score > 0 else 0.0
    baseline = random_claim_baseline(records, context, score)

    print("---")
    print(f"score: {score:.6f}")
    print("validation: candidate saw Jan-Feb only; evaluator scored March only")
    print(f"claim: {discovery.name}")
    if claim.get("rationale"):
        print(f"rationale: {claim['rationale']}")
    print(f"category: {discovery.category}")
    print(f"a: {discovery.a_label}")
    print(f"b: {discovery.b_label}")
    print(f"discovery_months: {','.join(DISCOVERY_DATES)}")
    print(f"discovery_a_count: {discovery.a.count}")
    print(f"discovery_a_total: {discovery.a.total}")
    print(f"discovery_a_share: {discovery.a.share:.6f}")
    print(f"discovery_b_count: {discovery.b.count}")
    print(f"discovery_b_total: {discovery.b.total}")
    print(f"discovery_b_share: {discovery.b.share:.6f}")
    print(f"discovery_effect_size: {discovery.effect_size:.6f}")
    print(f"discovery_lift: {discovery.lift:.6f}")
    print(f"discovery_z_score: {discovery.z_score:.6f}")
    print(f"discovery_p_value: {discovery.p_value:.6g}")
    print(f"discovery_score: {discovery.score:.6f}")
    print(f"holdout_months: {','.join(HOLDOUT_DATES)}")
    print(f"holdout_a_count: {holdout.a.count}")
    print(f"holdout_a_total: {holdout.a.total}")
    print(f"holdout_a_share: {holdout.a.share:.6f}")
    print(f"holdout_b_count: {holdout.b.count}")
    print(f"holdout_b_total: {holdout.b.total}")
    print(f"holdout_b_share: {holdout.b.share:.6f}")
    print(f"holdout_effect_size: {holdout.effect_size:.6f}")
    print(f"holdout_lift: {holdout.lift:.6f}")
    print(f"holdout_z_score: {holdout.z_score:.6f}")
    print(f"holdout_p_value: {holdout.p_value:.6g}")
    print(f"holdout_score: {holdout.score:.6f}")
    print(f"random_claims: {baseline['count']}")
    print(f"random_claim_mean_score: {baseline['mean']:.6f}")
    print(f"random_claim_median_score: {baseline['median']:.6f}")
    print(f"random_claim_p90_score: {baseline['p90']:.6f}")
    print(f"candidate_random_percentile: {baseline['percentile']:.2f}")
    print(f"records_discovery_months: {len(DISCOVERY_DATES)}")
    print(f"records_holdout_months: {len(HOLDOUT_DATES)}")
    print(f"records_places: {len(LOCATIONS)}")
    return 0


def load_candidate():
    spec = importlib.util.spec_from_file_location("candidate", CANDIDATE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {CANDIDATE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not hasattr(module, "claim"):
        raise RuntimeError("candidate.py must define claim(context)")
    return module


def load_records() -> list[dict]:
    records = []
    for date in ALL_DATES:
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


def build_discovery_context(records: list[dict]) -> dict:
    discovery_records = [record for record in records if record["date"] in DISCOVERY_DATES]
    totals = Counter()
    for record in discovery_records:
        totals.update(record["counts"])

    categories = sorted(totals)
    top_categories = [category for category, _ in totals.most_common(12)]
    places = sorted(LOCATIONS)
    discovery = {}
    for category in categories:
        discovery[category] = {}
        for place in places:
            aggregate_value = aggregate(discovery_records, category=category, places=[place])
            discovery[category][place] = {
                "count": aggregate_value.count,
                "total": aggregate_value.total,
                "share": aggregate_value.share,
            }

    return {
        "places": places,
        "discovery_months": DISCOVERY_DATES[:],
        "categories": categories,
        "top_categories": top_categories,
        "discovery": discovery,
    }


def score_claim(claim: dict, records: list[dict], months: list[str]) -> PairScore:
    kind = claim.get("kind", "pair_share")
    if kind != "pair_share":
        raise ValueError(f"unsupported kind: {kind}")

    name = required(claim, "name")
    category = required(claim, "category")
    place = required(claim, "place")
    reference = required(claim, "reference")

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
        direction=claim.get("direction", "higher"),
    )


def random_claim_baseline(records: list[dict], context: dict, candidate_score: float) -> dict:
    """Score a uniform random choice among discovery-positive pair claims."""

    scores = []
    for claim in enumerate_pair_claims(context):
        discovery = score_claim(claim, records, DISCOVERY_DATES)
        if discovery.score <= 0:
            continue

        holdout = score_claim(claim, records, HOLDOUT_DATES)
        scores.append(holdout.score if holdout.score > 0 else 0.0)

    if not scores:
        return {
            "count": 0,
            "mean": 0.0,
            "median": 0.0,
            "p90": 0.0,
            "percentile": 0.0,
        }

    ordered = sorted(scores)
    count = len(ordered)
    mean = sum(ordered) / count
    median = percentile(ordered, 0.5)
    p90 = percentile(ordered, 0.9)
    rank = sum(1 for score in ordered if score <= candidate_score)

    return {
        "count": count,
        "mean": mean,
        "median": median,
        "p90": p90,
        "percentile": 100.0 * rank / count,
    }


def enumerate_pair_claims(context: dict) -> list[dict]:
    claims = []
    places = context["places"]
    for category in context["categories"]:
        for place in places:
            for reference in places:
                if reference == place:
                    continue
                for direction in ["higher", "lower"]:
                    claims.append(
                        {
                            "name": f"{place} {category} share is {direction} than {reference}",
                            "kind": "pair_share",
                            "category": category,
                            "place": place,
                            "reference": reference,
                            "direction": direction,
                        }
                    )
    return claims


def percentile(ordered: list[float], fraction: float) -> float:
    if not ordered:
        return 0.0
    index = min(len(ordered) - 1, max(0, int(round((len(ordered) - 1) * fraction))))
    return ordered[index]


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
) -> PairScore:
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

    return PairScore(
        name=name,
        category=category,
        a_label=a_label,
        b_label=b_label,
        a=a,
        b=b,
        lift=lift,
        z_score=z_score,
        p_value=p_value,
        effect_size=effect_size,
        score=score,
    )


def required(claim: dict, key: str) -> str:
    value = claim.get(key)
    if not value:
        raise ValueError(f"claim missing {key}")
    return str(value)


if __name__ == "__main__":
    raise SystemExit(main())
