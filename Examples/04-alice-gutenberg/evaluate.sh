set -euo pipefail

example_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$example_dir/../.." && pwd)"
candidate="$example_dir/candidate.sh"

# shellcheck source=/dev/null
source "$candidate"

: "${LEARNING_RATE:?candidate.sh must set LEARNING_RATE}"
: "${WEIGHT_DECAY:?candidate.sh must set WEIGHT_DECAY}"
: "${MAX_SEQ_LEN:?candidate.sh must set MAX_SEQ_LEN}"
: "${DEVICE_BATCH_SIZE:?candidate.sh must set DEVICE_BATCH_SIZE}"
: "${TOTAL_BATCH_SIZE:?candidate.sh must set TOTAL_BATCH_SIZE}"
: "${MLX_LAYERS:?candidate.sh must set MLX_LAYERS}"
: "${MLX_DIM:?candidate.sh must set MLX_DIM}"
: "${MLX_HEADS:?candidate.sh must set MLX_HEADS}"
: "${MLX_MLP_DIM:?candidate.sh must set MLX_MLP_DIM}"

cd "$repo_dir"

work_dir=".build/04-alice-gutenberg"
corpus="$work_dir/alice.txt"
cache_dir="$work_dir/cache"
baseline_log="$work_dir/baseline-training.log"
candidate_log="$work_dir/candidate-training.log"

mkdir -p "$work_dir"

if [ ! -s "$corpus" ]; then
  curl -fsSL https://www.gutenberg.org/ebooks/11.txt.utf-8 -o "$corpus"
fi

swift run autoresearch prepare \
  --input "$corpus" \
  --cache-dir "$cache_dir" >/dev/null

extract_val_bpb() {
  awk '/^val_bpb:/ { value = $2 } END { if (value != "") print value }' "$1"
}

echo "--- fixed baseline training ---"
swift run autoresearch train \
  --backend mlx \
  --mlx-device gpu \
  --cache-dir "$cache_dir" \
  --time-budget 5 \
  --max-seq-len 128 \
  --device-batch-size 4 \
  --total-batch-size 512 \
  --eval-tokens 4096 \
  --learning-rate 0.00005 \
  --weight-decay 0.0 \
  --mlx-layers 1 \
  --mlx-dim 32 \
  --mlx-heads 4 \
  --mlx-mlp-dim 64 | tee "$baseline_log"

baseline_val_bpb="$(extract_val_bpb "$baseline_log")"
if [[ -z "$baseline_val_bpb" ]]; then
  echo "Could not parse baseline val_bpb" >&2
  exit 2
fi

echo "--- mutable candidate training ---"
swift run autoresearch train \
  --backend mlx \
  --mlx-device gpu \
  --cache-dir "$cache_dir" \
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
  --mlx-mlp-dim "$MLX_MLP_DIM" | tee "$candidate_log"

candidate_val_bpb="$(extract_val_bpb "$candidate_log")"
if [[ -z "$candidate_val_bpb" ]]; then
  echo "Could not parse candidate val_bpb" >&2
  exit 2
fi

improvement_bpb="$(awk -v baseline="$baseline_val_bpb" -v candidate="$candidate_val_bpb" 'BEGIN { printf "%.6f", baseline - candidate }')"
improvement_percent="$(awk -v baseline="$baseline_val_bpb" -v candidate="$candidate_val_bpb" 'BEGIN { printf "%.2f", 100.0 * (baseline - candidate) / baseline }')"
estimated_eval_bits_saved="$(awk -v improvement="$improvement_bpb" 'BEGIN { printf "%.1f", improvement * 4096 }')"

echo "---"
echo "improvement_bpb: $improvement_bpb"
echo "improvement_percent: $improvement_percent"
echo "estimated_eval_bits_saved: $estimated_eval_bits_saved"
echo "baseline_val_bpb: $baseline_val_bpb"
echo "candidate_val_bpb: $candidate_val_bpb"
echo "smoking_gun: candidate lowers validation bits per byte versus the fixed MLX baseline"
echo "training_backend: mlx"
echo "tokenizer: byte"
echo "eval_tokens: 4096"
echo "time_budget: 5"
echo "baseline_learning_rate: 0.00005"
echo "candidate_learning_rate: $LEARNING_RATE"
echo "candidate_max_seq_len: $MAX_SEQ_LEN"
echo "candidate_device_batch_size: $DEVICE_BATCH_SIZE"
echo "candidate_total_batch_size: $TOTAL_BATCH_SIZE"
echo "candidate_mlx_layers: $MLX_LAYERS"
echo "candidate_mlx_dim: $MLX_DIM"
echo "candidate_mlx_heads: $MLX_HEADS"
echo "candidate_mlx_mlp_dim: $MLX_MLP_DIM"
