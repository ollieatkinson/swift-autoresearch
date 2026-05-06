---
name: mlx-bpe-smoke
metric: val_bpb
direction: minimize
evaluator: bash evaluate.sh
timeout_seconds: 120
results: results.tsv
mutable:
  - candidate.sh
---

# MLX BPE Smoke

This example connects the pieces used for a real Swift language-model run:
prepare text, train a native BPE tokenizer artifact, load that artifact, and
train the MLX GPT-style backend.

The useful behavior is the full path rather than a large score improvement. The
tokenizer summary shows whether the corpus compresses into fewer tokens, and
the final `val_bpb` shows that the MLX backend can train and evaluate through
the BPE runtime.

The default candidate uses CPU and a tiny model so it is portable. On Apple
Silicon, changing `MLX_DEVICE=gpu` is the first useful experiment.

## Evaluate

```bash
swift run autoresearch evaluate \
  --problem Examples/03-mlx-bpe-smoke/problem.md \
  --description baseline
```

For a local smoke run that does not update `results.tsv`, add `--no-results`:

```bash
swift run autoresearch evaluate \
  --problem Examples/03-mlx-bpe-smoke/problem.md \
  --description local-smoke \
  --no-results \
  --log-file .build/example-logs/03-mlx-bpe-smoke.log
```

## Use The Output

The final block is the part to act on:

```text
val_bpb: ...
tokenizer_compression_ratio: ...
tokenizer_vocab_size: ...
tokenizer_merges: ...
tokenizer: bpe
training_backend: mlx
mlx_device: ...
```

Use `val_bpb` as the model score. Lower is better. Use
`tokenizer_compression_ratio` as context for the score: it tells you how much
the tokenizer shortened the text before the model saw it.

On the checked-in corpus, a local CPU smoke run compressed the text to about
`0.28` of the original byte-token count, then produced a real MLX validation
score through the BPE runtime. That is the aha moment: the native Swift BPE
artifact is not just a standalone file; it is loaded by the training backend
and changes the token stream the model trains on.

If you run without `--no-results`, the evaluator appends the score to
`results.tsv`. Use that when comparing changes to `candidate.sh`; use
`--no-results` when checking that the example still works.

## Try Changing

Edit `candidate.sh` and change tokenizer settings, model size, or
`MLX_WINDOW_PATTERN`. The evaluator regenerates the tokenizer artifact and
then trains the model against the same held-out text.
