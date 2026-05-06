# 04 Alice Gutenberg

Real text-corpus example. This downloads the public-domain Project Gutenberg
text of `Alice's Adventures in Wonderland`, trains a fixed weak MLX baseline,
then trains the mutable candidate on the same prepared data.

This example is intentionally heavier than the first three: it exercises a real
downloaded corpus and a candidate-versus-baseline optimization loop.

## Run It

```bash
swift run autoresearch evaluate \
  --problem Examples/04-alice-gutenberg/problem.md \
  --description local-smoke \
  --no-results \
  --log-file .build/example-logs/04-alice-gutenberg.log
```

Remove `--no-results` when you want to append a scored row to `results.tsv`.

## Use The Output

Look at the final block:

```text
improvement_bpb: ...
improvement_percent: ...
estimated_eval_bits_saved: ...
baseline_val_bpb: ...
candidate_val_bpb: ...
candidate_learning_rate: ...
candidate_mlx_dim: ...
```

`improvement_bpb` is the score. Higher is better because it is
`baseline_val_bpb - candidate_val_bpb`.

Positive `improvement_bpb` is the useful moment: the mutable candidate has
beaten the fixed baseline on held-out bytes from the same corpus. Negative or
near-zero values mean the candidate knobs made the run slower, noisier, or no
better under the fixed time budget.

## Demonstrated Local Run

This example compares one fixed baseline with the checked-in candidate. The
claim is not changing; the question is whether the candidate training settings
predict the same held-out corpus bytes better under the same five-second budget.

A local Apple GPU run produced:

```text
baseline_val_bpb: 6.505696
candidate_val_bpb: 3.982069
improvement_bpb: 2.523627
improvement_percent: 38.79
estimated_eval_bits_saved: 10336.8
```

That is the payoff: the candidate spent the same time on the same corpus and
reduced validation bits per byte by about 39 percent. Over the 4096-byte eval
window, that is roughly 10.4k fewer bits of surprise assigned to the held-out
text.

This is still a tiny run, so the exact number can move with hardware and MLX
runtime behavior. The useful comparison is the direction and size of
`improvement_bpb` against the fixed baseline.

This example does not test claim selection like the UK crime example. The task
is fixed: model the Alice corpus better than a weak baseline under the same
budget. That makes it useful for tuning training knobs while keeping the data,
metric, and evaluator stable.

## Autoresearch Loop

I ran this as a local loop by letting the evaluator append to its ignored
`results.tsv`, editing `candidate.sh` between runs, and restoring the checked-in
candidate afterward:

```text
commit   improvement_bpb  memory_gb  status   description
f654be6  2.501198         0.0        keep     00 baseline candidate
f654be6  0.035139         0.0        discard  01 candidate matches weak baseline lr
f654be6  3.046323         0.0        keep     02 higher learning rate
f654be6  3.234933         0.0        keep     03 too high learning rate
f654be6  3.524005         0.0        keep     04 unstable learning rate
f654be6 -0.732135         0.0        discard  05 extreme learning rate
```

The useful behavior is that the loop challenged the first intuition. Matching
the weak baseline learning rate was discarded, but increasingly aggressive
learning rates kept improving this tiny five-second run until the extreme value
finally broke the candidate. This is exactly why the evaluator records keep and
discard rows instead of relying on guesses about which knobs should help.

## Try Next

Change `LEARNING_RATE`, `MLX_DIM`, or `MLX_MLP_DIM` in `candidate.sh`, rerun the
evaluator, and compare `improvement_bpb`.
