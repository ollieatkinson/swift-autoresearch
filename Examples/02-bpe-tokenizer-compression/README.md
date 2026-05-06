# 02 BPE Tokenizer Compression

Intermediate example. This isolates native Swift BPE training from model
training so the tokenizer artifact has a visible payoff on its own.

## Run It

```bash
swift run autoresearch evaluate \
  --problem Examples/02-bpe-tokenizer-compression/problem.md \
  --description local-smoke \
  --no-results \
  --log-file .build/example-logs/02-bpe-tokenizer-compression.log
```

Remove `--no-results` when you want to append a scored row to `results.tsv`.

## Use The Output

Look at the final block:

```text
token_reduction: ...
compression_ratio: ...
initial_tokens: ...
final_tokens: ...
tokenizer_artifact: ...
```

`token_reduction` is the score. Higher is better because the tokenizer
represented the same UTF-8 bytes with fewer model tokens.

On the checked-in corpus, a local run compressed `1110` byte tokens to `366`
BPE tokens. That is the useful moment: before training any model, repeated text
has become cheaper for the model to process.

The `tokenizer_artifact` path is what an MLX run consumes with
`--tokenizer bpe --tokenizer-file ...`.

## Try Next

Change `VOCAB_SIZE` or `MIN_PAIR_FREQUENCY` in `candidate.sh`, rerun the
evaluator, and compare `token_reduction`.
