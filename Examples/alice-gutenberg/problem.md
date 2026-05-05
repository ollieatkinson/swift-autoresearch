---
name: alice-gutenberg
metric: val_bpb
direction: minimize
evaluator: bash evaluate.sh
timeout_seconds: 180
results: results.tsv
mutable:
  - Sources/Autoresearch
  - Sources/autoresearch-cli
---

# Alice Gutenberg

This is a deliberately silly text-modeling problem using the public-domain
Project Gutenberg text of Lewis Carroll's `Alice's Adventures in Wonderland`.

The objective is to lower validation bits per byte on a small English corpus
under a fixed wall-clock budget. The problem document and evaluator are the
fixed contract. The agent may edit only the mutable paths listed in the front
matter, commit each candidate, run the evaluator, and keep or discard by
`val_bpb`.

The evaluator downloads the UTF-8 plain-text eBook from Project Gutenberg on
first run and caches it under `.build/alice-gutenberg/`.

## Run One Evaluation

```bash
swift run autoresearch evaluate \
  --problem Examples/alice-gutenberg/problem.md \
  --description baseline
```

## Manual Data Prep

```bash
mkdir -p .build/alice-gutenberg
curl -fsSL https://www.gutenberg.org/ebooks/11.txt.utf-8 \
  -o .build/alice-gutenberg/alice.txt
swift run autoresearch prepare \
  --input .build/alice-gutenberg/alice.txt \
  --cache-dir .build/alice-gutenberg/cache
```

## Manual MLX Training Run

```bash
swift run autoresearch train \
  --backend mlx \
  --mlx-device gpu \
  --cache-dir .build/alice-gutenberg/cache \
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
