#!/usr/bin/env bash
set -euo pipefail

example_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$example_dir/../.." && pwd)"

cd "$repo_dir"

work_dir=".build/00-cli-lifecycle"
cache_dir="$work_dir/cache"
tokenizer_file="$work_dir/tokenizer.json"

mkdir -p "$work_dir"

echo "--- prepare checked-in corpus ---"
swift run autoresearch prepare \
  --input Examples/00-cli-lifecycle/corpus.txt \
  --cache-dir "$cache_dir" \
  --validation-fraction 0.25

echo
echo "--- prepared files ---"
wc -c "$cache_dir/data/train.txt" "$cache_dir/data/val.txt"

echo
echo "--- train native BPE tokenizer artifact ---"
swift run autoresearch train-tokenizer \
  --input Examples/00-cli-lifecycle/corpus.txt \
  --output "$tokenizer_file" \
  --vocab-size 288 \
  --min-pair-frequency 2 \
  --max-training-bytes 10000

echo
echo "--- train default backend from prepared cache ---"
swift run autoresearch train \
  --cache-dir "$cache_dir" \
  --time-budget 1 \
  --max-seq-len 32 \
  --device-batch-size 2 \
  --total-batch-size 64 \
  --eval-tokens 512

echo
echo "Tokenizer artifact: $tokenizer_file"
echo "Prepared cache: $cache_dir"
