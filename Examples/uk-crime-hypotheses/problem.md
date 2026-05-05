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

This example uses UK open data to test candidate hypotheses over a fixed,
locally cached North Yorkshire slice of street-level crime records.

The data source is the Police.uk street-level crime API, which is catalogued by
data.gov.uk. The evaluator fetches crimes near York, Harrogate, Scarborough,
and Northallerton for January through March 2024, caches the JSON under
`.build/uk-crime-hypotheses/`, aggregates category counts, and scores candidate
hypotheses.

The problem document and evaluator are the immutable contract. The agent may
edit only `candidate.py`, which generates hypotheses such as:

- "bicycle theft is a larger share of recorded crime around York than the other
  sampled North Yorkshire towns"
- "anti-social behaviour is a larger share around Scarborough than the other
  sampled North Yorkshire towns"
- "shoplifting rose in the most recent sampled month around Harrogate"

The evaluator reports the best hypothesis by a combined score using statistical
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

Edit `Examples/uk-crime-hypotheses/candidate.py` to generate different
hypotheses. For example:

- compare another crime category
- compare a named place against `all_other`
- add a recent-vs-earlier shift hypothesis
- loop over `context["top_categories"]` and `context["places"]`

Then rerun:

```bash
swift run autoresearch evaluate \
  --problem Examples/uk-crime-hypotheses/problem.md \
  --description "expand hypothesis search"
```

The metric is `score`, and higher is better.
