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

## Demonstrated Local Run

A local run produced:

```text
initial_tokens: 1110
final_tokens: 366
compression_ratio: 0.3297
token_reduction: 0.670300
vocab_size: 320
merges: 63
```

This is useful because it separates tokenizer quality from model quality. The
model has not trained yet; the only thing being measured is whether the BPE
trainer found repeated byte sequences worth merging.

The example is not claiming that maximum compression always gives the best
model. A tokenizer can overfit a tiny corpus or produce tokens that are less
useful on different text. What it shows is the artifact-level behavior that a
later MLX run can consume.

## Autoresearch Loop

This table shows a local autoresearch-style loop. The operator ran the
evaluator with numbered descriptions. Between rows, the model edited
`candidate.sh`; the evaluator appended each score to `results.tsv`; after the
loop, the checked-in candidate was restored.

```text
commit   token_reduction  memory_gb  status   description
f654be6  0.670300         0.0        keep     00 baseline vocab 320
f654be6  0.364000         0.0        discard  01 smaller vocab 280
f654be6  0.852300         0.0        keep     02 larger vocab 384
f654be6  0.602700         0.0        discard  03 stricter merge frequency
```

The loop shows a real tokenizer tradeoff. A smaller vocabulary leaves useful
merges on the table. A larger vocabulary compresses this tiny repetitive corpus
more aggressively. A stricter merge-frequency threshold stops too early, even
with the larger requested vocabulary.

## Try Next

Change `VOCAB_SIZE` or `MIN_PAIR_FREQUENCY` in `candidate.sh`, rerun the
evaluator, and compare `token_reduction`.
