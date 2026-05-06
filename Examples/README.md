# Examples

These examples are ordered by how much of the package they exercise.

Run with `--no-results` when you want a one-off local smoke check that does not
append to `results.tsv`:

```bash
swift run autoresearch evaluate \
  --problem Examples/01-quick-bigram/problem.md \
  --description local-smoke \
  --no-results \
  --log-file .build/example-logs/01-quick-bigram.log
```

Run without `--no-results` when you want the evaluator to record the score and
mark it as `keep`, `discard`, or `crash`.

## 01 Quick Bigram

Beginner example. It prepares a tiny text corpus and trains the dependency-light
bigram backend.

```bash
swift run autoresearch evaluate \
  --problem Examples/01-quick-bigram/problem.md \
  --description baseline
```

This is useful for checking the evaluator contract, cache preparation, training
summary parsing, and `val_bpb` scoring without MLX.

The output to use is `val_bpb`. Lower is better. The aha moment is that editing
only `candidate.sh` gives you a comparable held-out language-model score in a
few seconds.

## 02 BPE Tokenizer Compression

Intermediate example. It trains a native Swift byte-level BPE tokenizer and
scores how much it reduces token count on a repetitive text corpus.

```bash
swift run autoresearch evaluate \
  --problem Examples/02-bpe-tokenizer-compression/problem.md \
  --description baseline
```

This is useful for seeing why a BPE artifact matters before introducing model
training.

The output to use is `token_reduction`, plus `initial_tokens` and
`final_tokens`. On the checked-in corpus, a local run compressed 1110 byte tokens
to 366 BPE tokens. The aha moment is that a tokenizer artifact can make the same
text much shorter in model-token space.

## 03 MLX BPE Smoke

Advanced example. It prepares text, trains a native BPE tokenizer artifact, and
uses that artifact in a small MLX GPT-style training run.

```bash
swift run autoresearch evaluate \
  --problem Examples/03-mlx-bpe-smoke/problem.md \
  --description baseline
```

This demonstrates the full Swift tokenizer-to-MLX path. It defaults to CPU for
portability; edit `candidate.sh` to use the Apple GPU or larger model settings.

The output to use is `val_bpb`, while `tokenizer_compression_ratio` tells you
what happened before training started. A local CPU smoke run compressed the text
to about 28% of the original byte-token count and then produced a real MLX
validation score through the BPE runtime.

## Larger Examples

- `tiny-lab-notes`: small MLX candidate-versus-baseline optimization example.
- `alice-gutenberg`: public-domain text optimization example.
- `uk-crime-hypotheses`: non-language-model example using the generic
  evaluator loop.
