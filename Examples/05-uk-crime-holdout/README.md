# 05 UK Crime Holdout

Non-language-model example. This uses the generic evaluator loop to test
whether a mutable research strategy can find one claim that survives a held-out
month of UK open crime data.

The evaluator fetches Police.uk street-level crime records near York,
Harrogate, Scarborough, and Northallerton. `candidate.py` sees January and
February 2024 aggregates only. The evaluator scores the selected claim on March
2024 only.

## Run It

```bash
swift run autoresearch evaluate \
  --problem Examples/05-uk-crime-holdout/problem.md \
  --description local-smoke \
  --no-results \
  --log-file .build/example-logs/05-uk-crime-holdout.log
```

Remove `--no-results` when you want to append a scored row to `results.tsv`.

## Use The Output

Look at the final block:

```text
score: ...
validation: candidate saw Jan-Feb only; evaluator scored March only
claim: ...
discovery_lift: ...
holdout_lift: ...
holdout_score: ...
random_claim_median_score: ...
random_claim_p90_score: ...
candidate_random_percentile: ...
```

`score` is the March holdout score. Higher is better. A good discovery has
positive discovery evidence and still has positive holdout evidence in March.

The useful moment is the train/validation split applied to research claims:
the candidate can search Jan-Feb, but it does not get to inspect March before
choosing a claim.

The selected crime claim is not the product. It is an observable output that
shows whether a search strategy can find a pattern that still appears in unseen
data. In a real analysis workflow, that is useful for ranking which anomalies
deserve human attention, comparing competing discovery heuristics, and avoiding
claims that only looked good because they were selected from one slice of data.

## Demonstrated Improvement

The rows below are not the same statement getting better. They are different
claim-selection strategies. That distinction matters: this example tests
whether a strategy can choose a claim from discovery data that scores well on
held-out data.

These rows came from clearing the ignored `results.tsv`, editing
`candidate.py` between runs, and restoring the checked-in final strategy after
the loop. The generated `results.tsv` is not committed; the scored outcomes are
copied here so the example has a stable walkthrough.

| cycle | decision | strategy | held-out score | selected claim |
| --- | --- | --- | ---: | --- |
| 0 | baseline | naive top-category comparison | `0.000000` | Harrogate violent-crime share higher than Northallerton |
| 1 | kept | largest raw share gap | `1.203788` | Scarborough violent-crime share higher than York |
| 2 | kept | drop broad categories plus z-score | `1.347001` | York shoplifting share higher than Northallerton |
| 3 | discarded | pooled "all other" reference | `0.004368` | Northallerton burglary share higher than all other places |
| 4 | discarded | rare-category lift chase | `0.000000` | Harrogate robbery share higher than York |
| 5 | kept | pairwise significance plus lift | `6.027808` | York bicycle-theft share higher than Scarborough |
| 6 | discarded | over-restricted top categories | `0.072565` | Northallerton burglary share higher than Scarborough |

What this gains over randomly choosing claims is a baseline. The evaluator also
scores every discovery-positive pair claim as if one were chosen uniformly at
random. A local run produced:

```text
random_claims: 168
random_claim_mean_score: 0.776322
random_claim_median_score: 0.145096
random_claim_p90_score: 2.336463
candidate_random_percentile: 100.00
```

The discarded rows are useful because they show where attractive discovery
signals fail. The pooled "all other" strategy found a discovery lift of `2.35x`,
but March fell to `1.04x`. The rare-category lift strategy found a `7.20x`
robbery lift in discovery, but the direction did not survive March, so the
held-out score became zero.

The final strategy's `6.027808` score is above the random-claim 90th
percentile on this fixed split. That is the useful comparison: not that one
statement was tuned, but that the selection rule found a better held-out claim
than a random discovery-positive claim. In the final run, York's bicycle-theft
share remained much higher than Scarborough's in March, with a holdout lift of
about `20.85x`. That makes the output a good test fixture for the loop, not a
standalone operational conclusion about York or Scarborough.

This is not causal inference. It is a compact demonstration of the repo's
research loop: generate a claim from discovery data, then score it on data the
candidate did not see. Repeatedly tuning against the same March holdout would
eventually overfit; a production version would reserve another private final
holdout.

## Try Next

Change `candidate.py` to search lower shares, adjust count thresholds, or use
`context["top_categories"]`. Rerun the evaluator and compare the March holdout
`score`.
