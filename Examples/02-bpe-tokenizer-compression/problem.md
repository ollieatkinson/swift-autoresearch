---
name: bpe-tokenizer-compression
metric: token_reduction
direction: maximize
evaluator: bash evaluate.sh
timeout_seconds: 60
results: results.tsv
mutable:
  - candidate.sh
---

# BPE Tokenizer Compression

This example isolates native BPE training from model training. The evaluator
trains a byte-level BPE tokenizer artifact from a small repetitive corpus and
scores how many tokens the learned merges remove.

The useful behavior is visible before MLX enters the picture: repeated byte
sequences such as common words and phrases become single tokens. Higher
`token_reduction` means the same text fits into fewer model tokens.

That matters for language-model runs because sequence length and batch size are
measured in tokens. A better tokenizer can fit more text into the same context
window and reduce the number of prediction steps needed for common text.

## Evaluate

```bash
swift run autoresearch evaluate \
  --problem Examples/02-bpe-tokenizer-compression/problem.md \
  --description baseline
```

For a local smoke run that does not update `results.tsv`, add `--no-results`:

```bash
swift run autoresearch evaluate \
  --problem Examples/02-bpe-tokenizer-compression/problem.md \
  --description local-smoke \
  --no-results \
  --log-file .build/example-logs/02-bpe-tokenizer-compression.log
```

## Use The Output

The final block is the part to act on:

```text
token_reduction: ...
compression_ratio: ...
initial_tokens: ...
final_tokens: ...
vocab_size: ...
merges: ...
tokenizer_artifact: ...
```

Use `token_reduction` as the score. Higher is better because it means the BPE
trainer represented the same UTF-8 bytes with fewer model tokens.

On the checked-in corpus, a local run compressed `1110` byte tokens to `366`
BPE tokens. That is the aha moment: before training any model, the tokenizer has
already made repeated language cheaper for the model to process.

The `tokenizer_artifact` path is the output you would feed into MLX training
with `--tokenizer bpe --tokenizer-file ...`.

## Try Changing

Edit `candidate.sh` and change `VOCAB_SIZE` or `MIN_PAIR_FREQUENCY`. The
evaluator will train a fresh tokenizer artifact and score its compression.
