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
  --description alice-baseline \
  --no-results \
  --log-file .build/example-logs/04-alice-gutenberg.log
```

Remove `--no-results` when you want to append a scored row to `results.tsv`.

## Use The Output

Look at the final block:

```text
improvement_bpb: ...
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

## Try Next

Change `LEARNING_RATE`, `MLX_DIM`, or `MLX_MLP_DIM` in `candidate.sh`, rerun the
evaluator, and compare `improvement_bpb`.
