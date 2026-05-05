---
name: tiny-lab-notes
metric: improvement_bpb
direction: maximize
evaluator: bash evaluate.sh
timeout_seconds: 120
results: results.tsv
mutable:
  - candidate.sh
---

# Tiny Lab Notes

This example is a small text-modeling problem for exercising the Swift
autoresearch loop without downloading data.

The task is to train on repeated lab-note records and lower validation bits per
byte relative to a fixed MLX baseline. It is intentionally small, so the MLX
backend can be tested with short commands and no network access.

The problem document is the immutable contract. The evaluator command above is
fixed and emits the metric named in the front matter. The agent may edit only
`candidate.sh`, commit each candidate, run the evaluator, and keep or discard
the commit based on `improvement_bpb`.

The evaluator trains an immutable weak baseline, then trains the mutable
candidate on the same data and reports:

```text
baseline_val_bpb: ...
candidate_val_bpb: ...
improvement_bpb: ...
```

Positive `improvement_bpb` is the smoking gun: the candidate predicts held-out
bytes better than the fixed baseline.

## Evaluate

```bash
swift run autoresearch evaluate \
  --problem Examples/tiny-lab-notes/problem.md \
  --description baseline
```

## Prepare

```bash
swift run autoresearch prepare \
  --input Examples/tiny-lab-notes/corpus.txt \
  --cache-dir .build/tiny-lab-notes/cache
```

## Manual Candidate Training Run

```bash
source Examples/tiny-lab-notes/candidate.sh
swift run autoresearch train \
  --backend mlx \
  --mlx-device gpu \
  --cache-dir .build/tiny-lab-notes/cache \
  --time-budget 1 \
  --max-seq-len "$MAX_SEQ_LEN" \
  --device-batch-size "$DEVICE_BATCH_SIZE" \
  --total-batch-size "$TOTAL_BATCH_SIZE" \
  --eval-tokens 4096 \
  --learning-rate "$LEARNING_RATE" \
  --weight-decay "$WEIGHT_DECAY" \
  --mlx-layers "$MLX_LAYERS" \
  --mlx-dim "$MLX_DIM" \
  --mlx-heads "$MLX_HEADS" \
  --mlx-mlp-dim "$MLX_MLP_DIM"
```
