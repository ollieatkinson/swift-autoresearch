---
name: quick-bigram
metric: val_bpb
direction: minimize
evaluator: bash evaluate.sh
timeout_seconds: 60
results: results.tsv
mutable:
  - candidate.sh
---

# Quick Bigram

This is the smallest useful language-model example in the repo. It prepares a
tiny checked-in text corpus, trains the byte bigram backend, and reports
validation bits per byte.

The behavior to look for is simple: the evaluator can turn a mutable candidate
file into a repeatable score. Lower `val_bpb` means the model assigned better
probability to the held-out text bytes.

The bigram backend is intentionally limited. It is useful because it exercises
the autoresearch harness quickly without requiring MLX, a tokenizer artifact,
or a large model.

## Evaluate

```bash
swift run autoresearch evaluate \
  --problem Examples/01-quick-bigram/problem.md \
  --description baseline
```

For a local smoke run that does not update `results.tsv`, add `--no-results`:

```bash
swift run autoresearch evaluate \
  --problem Examples/01-quick-bigram/problem.md \
  --description local-smoke \
  --no-results \
  --log-file .build/example-logs/01-quick-bigram.log
```

## Use The Output

The final block is the part to act on:

```text
val_bpb: ...
training_backend: bigram
tokenizer: byte
time_budget: ...
learning_rate: ...
```

Use `val_bpb` as the score. Lower is better because it means the model needed
fewer bits, on average, to predict each held-out byte. The progress lines are
diagnostic; the final `val_bpb` is the comparison point.

The aha moment is the evaluator contract: `candidate.sh` is the only mutable
file, but the command prepares data, trains, parses the model summary, and
turns the run into a score. Once this works, the same harness can test larger
backends without changing the scoring loop.

## Try Changing

Edit `candidate.sh` and change `LEARNING_RATE`, `TIME_BUDGET`, or the batch
settings. The evaluator keeps the corpus and scoring contract fixed, so changes
are compared through the same `val_bpb` metric.
