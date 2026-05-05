set -euo pipefail

cd "$(dirname "$0")/../.."

work_dir=".build/alice-gutenberg"
corpus="$work_dir/alice.txt"
cache_dir="$work_dir/cache"

mkdir -p "$work_dir"

if [ ! -s "$corpus" ]; then
  curl -fsSL https://www.gutenberg.org/ebooks/11.txt.utf-8 -o "$corpus"
fi

swift run autoresearch prepare \
  --input "$corpus" \
  --cache-dir "$cache_dir" >/dev/null

swift run autoresearch train \
  --backend mlx \
  --mlx-device gpu \
  --cache-dir "$cache_dir" \
  --time-budget 5 \
  --max-seq-len 128 \
  --device-batch-size 4 \
  --total-batch-size 512 \
  --eval-tokens 4096 \
  --mlx-layers 1 \
  --mlx-dim 32 \
  --mlx-heads 4 \
  --mlx-mlp-dim 64
