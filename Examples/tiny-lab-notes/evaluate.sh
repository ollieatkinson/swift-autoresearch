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

cache_dir=".build/tiny-lab-notes-cache"

swift run autoresearch prepare \
  --input Examples/tiny-lab-notes/corpus.txt \
  --cache-dir "$cache_dir" >/dev/null

swift run autoresearch train \
  --backend mlx \
  --mlx-device gpu \
  --cache-dir "$cache_dir" \
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
