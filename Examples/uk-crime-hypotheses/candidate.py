"""Mutable candidate hypothesis generator.

The fixed evaluator imports this file and calls hypotheses(context). Edit this
file only; do not edit problem.md or evaluate.py while running the loop.
"""


def hypotheses(context):
    """Return candidate hypotheses to score.

    Available context keys:
    - places: sampled place names
    - dates: sampled YYYY-MM months
    - categories: crime categories present in the cached data
    - top_categories: most frequent crime categories in the cached data
    """

    hypotheses = []

    places = context["places"]
    categories = context["top_categories"]

    for place in places:
        other_places = [other for other in places if other != place]

        for category in categories:
            hypotheses.append(
                {
                    "name": f"{place} {category} share vs other sampled north yorkshire towns",
                    "kind": "category_share",
                    "category": category,
                    "place": place,
                    "reference": "all_other",
                    "direction": "higher",
                }
            )

            for reference in other_places:
                hypotheses.append(
                    {
                        "name": f"{place} {category} share vs {reference}",
                        "kind": "category_share",
                        "category": category,
                        "place": place,
                        "reference": reference,
                        "direction": "higher",
                    }
                )

            for month in context["dates"]:
                hypotheses.append(
                    {
                        "name": f"{place} {category} share during {month} vs other sampled towns",
                        "kind": "category_share",
                        "category": category,
                        "place": place,
                        "reference": "all_other",
                        "months": [month],
                        "direction": "higher",
                    }
                )

            hypotheses.append(
                {
                    "name": f"{place} {category} recent one-month shift",
                    "kind": "recent_shift",
                    "category": category,
                    "place": place,
                    "recent_months": 1,
                    "direction": "higher",
                }
            )

    return hypotheses
