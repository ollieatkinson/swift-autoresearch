---
name: alice-gutenberg
metric: improvement_bpb
direction: maximize
evaluator: bash evaluate.sh
timeout_seconds: 180
results: results.tsv
mutable:
  - candidate.sh
---

# Alice Gutenberg

This is a deliberately silly text-modeling problem using the public-domain
Project Gutenberg text of Lewis Carroll's `Alice's Adventures in Wonderland`.

The objective is to lower validation bits per byte on a small English corpus
relative to a fixed MLX baseline. The problem document and evaluator are the
fixed contract. The agent may edit only `candidate.sh`, commit each candidate,
run the evaluator, and keep or discard by `improvement_bpb`.

The evaluator downloads the UTF-8 plain-text eBook from Project Gutenberg on
first run and caches it under `.build/04-alice-gutenberg/`.

`candidate.sh` is the mutable research surface. It controls MLX model size,
batching, optimizer knobs, and sequence length. The evaluator first trains an
immutable weak baseline, then trains the candidate on the same data and reports:

```text
baseline_val_bpb: ...
candidate_val_bpb: ...
improvement_bpb: ...
```

Positive `improvement_bpb` means the candidate predicts held-out bytes better
than the fixed baseline.

## Run One Evaluation

```bash
swift run autoresearch evaluate \
  --problem Examples/04-alice-gutenberg/problem.md \
  --description baseline
```

## Try A Candidate Edit

Edit `Examples/04-alice-gutenberg/candidate.sh`, for example by increasing
`LEARNING_RATE` or changing `MLX_DIM` and `MLX_MLP_DIM`, then run:

```bash
swift run autoresearch evaluate \
  --problem Examples/04-alice-gutenberg/problem.md \
  --description "tune candidate knobs"
```

## Manual Data Prep

```bash
mkdir -p .build/04-alice-gutenberg
curl -fsSL https://www.gutenberg.org/ebooks/11.txt.utf-8 \
  -o .build/04-alice-gutenberg/alice.txt
swift run autoresearch prepare \
  --input .build/04-alice-gutenberg/alice.txt \
  --cache-dir .build/04-alice-gutenberg/cache
```

## Manual MLX Training Run

```bash
source Examples/04-alice-gutenberg/candidate.sh
swift run autoresearch train \
  --backend mlx \
  --mlx-device gpu \
  --cache-dir .build/04-alice-gutenberg/cache \
  --time-budget 5 \
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
