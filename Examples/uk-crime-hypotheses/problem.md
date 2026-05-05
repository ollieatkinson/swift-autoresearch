---
name: north-yorkshire-crime-hypotheses
metric: score
direction: maximize
evaluator: bash evaluate.sh
timeout_seconds: 120
results: results.tsv
mutable:
  - candidate.py
---

# North Yorkshire Crime Hypotheses

This example uses UK open data to test whether a mutable research strategy can
find one claim that survives a held-out check.

The data source is the Police.uk street-level crime API, which is catalogued by
data.gov.uk. The evaluator fetches crimes near York, Harrogate, Scarborough,
and Northallerton for January through March 2024, caches the JSON under
`.build/uk-crime-hypotheses/`, and aggregates category counts.

The problem document and evaluator are the immutable contract. The agent may
edit only `candidate.py`. The evaluator gives `candidate.py` Jan-Feb aggregate
summaries only. The candidate must return one claim, and the evaluator scores
that claim on March records only.

The smoking-gun shape is:

```text
validation: candidate saw Jan-Feb only; evaluator scored March only
claim: york bicycle-theft share is higher than scarborough
discovery_lift: ...
holdout_lift: ...
score: ...
```

That is more useful than enumerating every possible comparison because the
mutable file is responsible for selecting a claim that generalizes.

Candidate claims can look like:

- "bicycle theft is a larger share of recorded crime around York than the other
  sampled North Yorkshire towns"
- "anti-social behaviour is a larger share around Scarborough than the other
  sampled North Yorkshire towns"
- "shoplifting rose in the most recent sampled month around Harrogate"

The evaluator scores the held-out claim by a combined score using statistical
significance and effect size. This is not causal inference, and the street-level
locations are approximate, but it is enough to demonstrate a local
autoresearch-style loop over open data.

## Run One Evaluation

```bash
swift run autoresearch evaluate \
  --problem Examples/uk-crime-hypotheses/problem.md \
  --description baseline
```

## Try A Candidate Edit

Edit `Examples/uk-crime-hypotheses/candidate.py` to change the discovery
strategy. For example:

- compare another crime category
- change minimum count thresholds
- penalize low reference counts
- search lower shares as well as higher shares
- use `context["top_categories"]` instead of all categories

Then rerun:

```bash
swift run autoresearch evaluate \
  --problem Examples/uk-crime-hypotheses/problem.md \
  --description "expand hypothesis search"
```

The metric is the March hold-out `score`, and higher is better.
