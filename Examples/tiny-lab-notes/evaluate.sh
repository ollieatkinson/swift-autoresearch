set -euo pipefail

cd "$(dirname "$0")/../.."

cache_dir=".build/tiny-lab-notes-cache"

swift run autoresearch prepare \
  --input Examples/tiny-lab-notes/corpus.txt \
  --cache-dir "$cache_dir" >/dev/null

swift run autoresearch train \
  --backend mlx \
  --mlx-device gpu \
  --cache-dir "$cache_dir" \
  --time-budget 1 \
  --max-seq-len 128 \
  --device-batch-size 4 \
  --total-batch-size 512 \
  --eval-tokens 4096 \
  --mlx-layers 1 \
  --mlx-dim 32 \
  --mlx-heads 4 \
  --mlx-mlp-dim 64
