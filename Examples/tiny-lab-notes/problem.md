---
name: tiny-lab-notes
metric: val_bpb
direction: minimize
evaluator: bash evaluate.sh
timeout_seconds: 120
results: results.tsv
mutable:
  - Sources/Autoresearch
  - Sources/autoresearch-cli
---

# Tiny Lab Notes

This example is a small text-modeling problem for exercising the Swift
autoresearch loop without downloading data.

The task is to train on repeated lab-note records and lower validation bits per
byte under a fixed wall-clock budget. It is intentionally small, so the MLX
backend can be tested with short commands and no network access.

The problem document is the immutable contract. The evaluator command above is
fixed and emits the metric named in the front matter. The agent may edit only
the mutable paths listed in the front matter, commit each candidate, run the
evaluator, and keep or discard the commit based on validation bits per byte.

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
  --cache-dir .build/tiny-lab-notes-cache
```

## Train The MLX Baseline

```bash
swift run autoresearch train \
  --backend mlx \
  --mlx-device gpu \
  --cache-dir .build/tiny-lab-notes-cache \
  --time-budget 5 \
  --max-seq-len 128 \
  --device-batch-size 4 \
  --total-batch-size 512 \
  --eval-tokens 4096 \
  --mlx-layers 1 \
  --mlx-dim 32 \
  --mlx-heads 4 \
  --mlx-mlp-dim 64
```
