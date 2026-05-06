# 05 UK Crime Holdout

Non-language-model example. This uses the generic evaluator loop to test
whether a mutable research strategy can find an operationally useful crime
pattern that survives a held-out month of UK open crime data.

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

The selected crime claim is not just trivia about two towns. The candidate now
searches for a local crime category whose share is elevated against the pooled
baseline from the other sampled places. That makes the output closer to an
analyst triage signal: a category and area that may deserve coordinated focus
because the pattern appears in discovery data and remains visible in the
held-out month.

For the checked-in strategy, a local run selected:

```text
claim: york bicycle-theft share is higher than the pooled other-place baseline
discovery: 69/1391 York records vs 8/1594 pooled other-place records
holdout:   28/768 York records vs 8/1059 pooled other-place records
holdout_lift: 4.826172
score: 4.148686
candidate_random_percentile: 97.77
```

An analyst could use that as a prompt to coordinate bicycle-theft prevention
and investigation around York: check local hotspots and time windows, compare
with cycle-parking infrastructure, share the signal with council or transport
partners, and verify whether reporting or sampling effects explain the lift.
It is not causal inference and it is not a resourcing decision by itself.

## Demonstrated Improvement

The rows below are not the same statement getting better. They are different
claim-selection strategies. That distinction matters: this example tests
whether a strategy can choose a claim from discovery data that scores well on
held-out data and is still useful to interpret.

These rows came from clearing the ignored `results.tsv`, editing
`candidate.py` between runs, and restoring the checked-in final strategy after
the loop. The generated `results.tsv` is not committed; the scored outcomes are
copied here so the example has a stable walkthrough. The decision column is the
example-design decision, not just the CLI's score comparison.

| cycle | decision | strategy | held-out score | selected claim |
| --- | --- | --- | ---: | --- |
| 0 | baseline | naive named-place comparison | `0.000000` | Harrogate violent-crime share higher than Northallerton |
| 1 | rejected | largest named-place raw gap | `1.203788` | Scarborough violent-crime share higher than York |
| 2 | rejected | metric-only named-place significance plus lift | `6.027808` | York bicycle-theft share higher than Scarborough |
| 3 | rejected | pooled baseline ranked by raw share gap | `0.557634` | Scarborough violent-crime share higher than pooled other places |
| 4 | rejected | pooled baseline with over-strict reference support | `0.004368` | Northallerton burglary share higher than pooled other places |
| 5 | rejected | pooled lower-than-baseline anomaly | `4.947198` | Scarborough bicycle-theft share lower than pooled other places |
| 6 | kept | pooled higher-than-baseline operational signal | `4.148686` | York bicycle-theft share higher than pooled other places |

The progression is the point. Cycles 1-2 increase score but still answer a weak
question: which named town makes the contrast look largest? Cycle 3 pivots to a
pooled baseline but raw share gap favors broad violent-crime patterns that are
less specific. Cycle 4 shows a threshold mistake: a too-strict reference-count
floor excludes the useful bicycle-theft signal. Cycle 5 scores well, but it
finds a lower-than-baseline category, which is less useful for deciding what to
focus on locally. Cycle 6 keeps the better operational question: which local
crime category is elevated against the rest of the sampled area and remains
elevated in March?

What this gains over randomly choosing claims is a baseline. The evaluator also
scores every discovery-positive comparison claim as if one were chosen uniformly
at random. A local run produced:

```text
random_claims: 224
random_claim_mean_score: 0.765315
random_claim_median_score: 0.145096
random_claim_p90_score: 2.336463
candidate_random_percentile: 97.77
```

The final strategy's `4.148686` score is above the random-claim 90th percentile
on this fixed split. That is the useful comparison: not that one statement was
tuned, but that the selection rule found a better held-out claim than a random
discovery-positive claim while avoiding the weakest-comparator problem.

This is not causal inference. It is a compact demonstration of the repo's
research loop: generate a claim from discovery data, then score it on data the
candidate did not see. Repeatedly tuning against the same March holdout would
eventually overfit; a production version would reserve another private final
holdout.

## Try Next

Change `candidate.py` to search lower shares, adjust count thresholds, or use
`context["top_categories"]`. Rerun the evaluator and compare the March holdout
`score`.
