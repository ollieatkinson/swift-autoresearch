#!/usr/bin/env bash
set -euo pipefail

example_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$example_dir/../.." && pwd)"
candidate="$example_dir/candidate.sh"

# shellcheck source=/dev/null
source "$candidate"

: "${TIME_BUDGET:?candidate.sh must set TIME_BUDGET}"
: "${LEARNING_RATE:?candidate.sh must set LEARNING_RATE}"
: "${WEIGHT_DECAY:?candidate.sh must set WEIGHT_DECAY}"
: "${MAX_SEQ_LEN:?candidate.sh must set MAX_SEQ_LEN}"
: "${DEVICE_BATCH_SIZE:?candidate.sh must set DEVICE_BATCH_SIZE}"
: "${TOTAL_BATCH_SIZE:?candidate.sh must set TOTAL_BATCH_SIZE}"
: "${EVAL_TOKENS:?candidate.sh must set EVAL_TOKENS}"

cd "$repo_dir"

work_dir=".build/01-quick-bigram"
cache_dir="$work_dir/cache"
train_log="$work_dir/training.log"

mkdir -p "$work_dir"

swift run autoresearch prepare \
  --input Examples/01-quick-bigram/corpus.txt \
  --cache-dir "$cache_dir" >/dev/null

extract_val_bpb() {
  awk '/^val_bpb:/ { value = $2 } END { if (value != "") print value }' "$1"
}

echo "--- bigram training ---"
swift run autoresearch train \
  --backend bigram \
  --cache-dir "$cache_dir" \
  --time-budget "$TIME_BUDGET" \
  --max-seq-len "$MAX_SEQ_LEN" \
  --device-batch-size "$DEVICE_BATCH_SIZE" \
  --total-batch-size "$TOTAL_BATCH_SIZE" \
  --eval-tokens "$EVAL_TOKENS" \
  --learning-rate "$LEARNING_RATE" \
  --weight-decay "$WEIGHT_DECAY" | tee "$train_log"

val_bpb="$(extract_val_bpb "$train_log")"
if [[ -z "$val_bpb" ]]; then
  echo "Could not parse val_bpb" >&2
  exit 2
fi

echo "---"
echo "val_bpb: $val_bpb"
echo "training_backend: bigram"
echo "tokenizer: byte"
echo "time_budget: $TIME_BUDGET"
echo "learning_rate: $LEARNING_RATE"
echo "max_seq_len: $MAX_SEQ_LEN"
echo "device_batch_size: $DEVICE_BATCH_SIZE"
echo "total_batch_size: $TOTAL_BATCH_SIZE"
echo "eval_tokens: $EVAL_TOKENS"
