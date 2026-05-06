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

cd "$repo_dir"

work_dir=".build/02-bpe-tokenizer-compression"
tokenizer_file="$work_dir/tokenizer.json"
tokenizer_log="$work_dir/tokenizer.log"

mkdir -p "$work_dir"

extract_field() {
  local key="$1"
  local file="$2"
  awk -F': *' -v key="$key" '$1 == key { value = $2 } END { if (value != "") print value }' "$file"
}

echo "--- bpe tokenizer training ---"
swift run autoresearch train-tokenizer \
  --input Examples/02-bpe-tokenizer-compression/corpus.txt \
  --output "$tokenizer_file" \
  --vocab-size "$VOCAB_SIZE" \
  --min-pair-frequency "$MIN_PAIR_FREQUENCY" \
  --max-training-bytes "$MAX_TRAINING_BYTES" | tee "$tokenizer_log"

compression_ratio="$(extract_field compression_ratio "$tokenizer_log")"
initial_tokens="$(extract_field initial_tokens "$tokenizer_log")"
final_tokens="$(extract_field final_tokens "$tokenizer_log")"
actual_vocab_size="$(extract_field vocab_size "$tokenizer_log")"
merges="$(extract_field merges "$tokenizer_log")"

if [[ -z "$compression_ratio" || -z "$initial_tokens" || -z "$final_tokens" ]]; then
  echo "Could not parse tokenizer summary" >&2
  exit 2
fi

token_reduction="$(awk -v ratio="$compression_ratio" 'BEGIN { printf "%.6f", 1.0 - ratio }')"

echo "---"
echo "token_reduction: $token_reduction"
echo "compression_ratio: $compression_ratio"
echo "initial_tokens: $initial_tokens"
echo "final_tokens: $final_tokens"
echo "vocab_size: $actual_vocab_size"
echo "merges: $merges"
echo "requested_vocab_size: $VOCAB_SIZE"
echo "min_pair_frequency: $MIN_PAIR_FREQUENCY"
echo "max_training_bytes: $MAX_TRAINING_BYTES"
echo "tokenizer_artifact: $tokenizer_file"
