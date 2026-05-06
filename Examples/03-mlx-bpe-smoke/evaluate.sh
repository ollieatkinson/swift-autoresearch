#!/usr/bin/env bash
set -euo pipefail

example_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$example_dir/../.." && pwd)"
candidate="$example_dir/candidate.sh"

# shellcheck source=/dev/null
source "$candidate"

: "${VOCAB_SIZE:?candidate.sh must set VOCAB_SIZE}"
: "${MIN_PAIR_FREQUENCY:?candidate.sh must set MIN_PAIR_FREQUENCY}"
: "${MAX_TRAINING_BYTES:?candidate.sh must set MAX_TRAINING_BYTES}"
: "${MLX_DEVICE:?candidate.sh must set MLX_DEVICE}"
: "${TIME_BUDGET:?candidate.sh must set TIME_BUDGET}"
: "${LEARNING_RATE:?candidate.sh must set LEARNING_RATE}"
: "${WEIGHT_DECAY:?candidate.sh must set WEIGHT_DECAY}"
: "${MAX_SEQ_LEN:?candidate.sh must set MAX_SEQ_LEN}"
: "${DEVICE_BATCH_SIZE:?candidate.sh must set DEVICE_BATCH_SIZE}"
: "${TOTAL_BATCH_SIZE:?candidate.sh must set TOTAL_BATCH_SIZE}"
: "${EVAL_TOKENS:?candidate.sh must set EVAL_TOKENS}"
: "${MLX_LAYERS:?candidate.sh must set MLX_LAYERS}"
: "${MLX_DIM:?candidate.sh must set MLX_DIM}"
: "${MLX_HEADS:?candidate.sh must set MLX_HEADS}"
: "${MLX_MLP_DIM:?candidate.sh must set MLX_MLP_DIM}"
: "${MLX_WINDOW_PATTERN:?candidate.sh must set MLX_WINDOW_PATTERN}"

cd "$repo_dir"

work_dir=".build/03-mlx-bpe-smoke"
cache_dir="$work_dir/cache"
tokenizer_file="$work_dir/tokenizer.json"
tokenizer_log="$work_dir/tokenizer.log"
train_log="$work_dir/training.log"

mkdir -p "$work_dir"

extract_field() {
  local key="$1"
  local file="$2"
  awk -F': *' -v key="$key" '$1 == key { value = $2 } END { if (value != "") print value }' "$file"
}

extract_val_bpb() {
  awk '/^val_bpb:/ { value = $2 } END { if (value != "") print value }' "$1"
}

swift run autoresearch prepare \
  --input Examples/03-mlx-bpe-smoke/corpus.txt \
  --cache-dir "$cache_dir" >/dev/null

echo "--- bpe tokenizer training ---"
swift run autoresearch train-tokenizer \
  --input Examples/03-mlx-bpe-smoke/corpus.txt \
  --output "$tokenizer_file" \
  --vocab-size "$VOCAB_SIZE" \
  --min-pair-frequency "$MIN_PAIR_FREQUENCY" \
  --max-training-bytes "$MAX_TRAINING_BYTES" | tee "$tokenizer_log"

compression_ratio="$(extract_field compression_ratio "$tokenizer_log")"
actual_vocab_size="$(extract_field vocab_size "$tokenizer_log")"
merges="$(extract_field merges "$tokenizer_log")"
if [[ -z "$compression_ratio" ]]; then
  echo "Could not parse tokenizer compression_ratio" >&2
  exit 2
fi

echo "--- mlx training with bpe tokenizer ---"
swift run autoresearch train \
  --backend mlx \
  --tokenizer bpe \
  --tokenizer-file "$tokenizer_file" \
  --mlx-device "$MLX_DEVICE" \
  --cache-dir "$cache_dir" \
  --time-budget "$TIME_BUDGET" \
  --max-seq-len "$MAX_SEQ_LEN" \
  --device-batch-size "$DEVICE_BATCH_SIZE" \
  --total-batch-size "$TOTAL_BATCH_SIZE" \
  --eval-tokens "$EVAL_TOKENS" \
  --learning-rate "$LEARNING_RATE" \
  --weight-decay "$WEIGHT_DECAY" \
  --mlx-layers "$MLX_LAYERS" \
  --mlx-dim "$MLX_DIM" \
  --mlx-heads "$MLX_HEADS" \
  --mlx-mlp-dim "$MLX_MLP_DIM" \
  --mlx-window-pattern "$MLX_WINDOW_PATTERN" | tee "$train_log"

val_bpb="$(extract_val_bpb "$train_log")"
if [[ -z "$val_bpb" ]]; then
  echo "Could not parse val_bpb" >&2
  exit 2
fi

echo "---"
echo "val_bpb: $val_bpb"
echo "tokenizer_compression_ratio: $compression_ratio"
echo "tokenizer_vocab_size: $actual_vocab_size"
echo "tokenizer_merges: $merges"
echo "tokenizer: bpe"
echo "training_backend: mlx"
echo "mlx_device: $MLX_DEVICE"
echo "time_budget: $TIME_BUDGET"
echo "learning_rate: $LEARNING_RATE"
echo "max_seq_len: $MAX_SEQ_LEN"
echo "device_batch_size: $DEVICE_BATCH_SIZE"
echo "total_batch_size: $TOTAL_BATCH_SIZE"
echo "eval_tokens: $EVAL_TOKENS"
echo "mlx_layers: $MLX_LAYERS"
echo "mlx_dim: $MLX_DIM"
echo "mlx_heads: $MLX_HEADS"
echo "mlx_mlp_dim: $MLX_MLP_DIM"
echo "mlx_window_pattern: $MLX_WINDOW_PATTERN"
