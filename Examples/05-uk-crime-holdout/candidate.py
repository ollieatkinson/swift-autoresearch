"""Mutable discovery strategy for the North Yorkshire crime example.

The fixed evaluator passes only Jan-Feb aggregate summaries into claim(context).
This file must select one claim that should survive a March hold-out check.
"""

import math


MIN_PRIMARY_COUNT = 10
MIN_REFERENCE_COUNT = 3


def claim(context):
    """Return one local-vs-pooled-baseline claim from discovery evidence only."""

    best = None
    for category in context["categories"]:
        for place in context["places"]:
            a = context["discovery"][category][place]
            if a["count"] < MIN_PRIMARY_COUNT:
                continue

            b = pooled_other_places(context, category, place)
            if b["count"] < MIN_REFERENCE_COUNT:
                continue

            score = discovery_score(a, b)
            if score <= 0:
                continue

            candidate = {
                "name": f"{place} {category} share is higher than the pooled other-place baseline",
                "kind": "pair_share",
                "category": category,
                "place": place,
                "reference": "all_other",
                "direction": "higher",
                "rationale": (
                    "Discovery months show "
                    f"{a['count']}/{a['total']} local records vs "
                    f"{b['count']}/{b['total']} pooled other-place records, "
                    f"a {safe_lift(a, b):.1f}x lift."
                ),
                "_discovery_score": score,
            }
            if best is None or score > best["_discovery_score"]:
                best = candidate

    if best is None:
        raise RuntimeError("No claim met the candidate strategy thresholds.")

    return {key: value for key, value in best.items() if not key.startswith("_")}


def discovery_score(a, b):
    """Rank local-vs-pooled-baseline share gaps using significance and lift."""

    if a["total"] <= 0 or b["total"] <= 0:
        return 0.0

    effect_size = a["share"] - b["share"]
    if effect_size <= 0:
        return 0.0

    pooled = (a["count"] + b["count"]) / (a["total"] + b["total"])
    standard_error = math.sqrt(pooled * (1 - pooled) * (1 / a["total"] + 1 / b["total"]))
    z_score = effect_size / standard_error if standard_error else 0.0
    lift = safe_lift(a, b)
    return abs(z_score) * math.log1p(abs(math.log(lift)))


def pooled_other_places(context, category, place):
    count = 0
    total = 0
    for reference in context["places"]:
        if reference == place:
            continue
        stats = context["discovery"][category][reference]
        count += stats["count"]
        total += stats["total"]
    return {
        "count": count,
        "total": total,
        "share": count / total if total else 0.0,
    }


def safe_lift(a, b):
    return (a["share"] + 1e-12) / (b["share"] + 1e-12)
