# 03 MLX BPE Smoke

Advanced language-model smoke example. It prepares text, trains a native BPE
tokenizer artifact, loads that artifact, and trains the MLX GPT-style backend.

## Run It

```bash
swift run autoresearch evaluate \
  --problem Examples/03-mlx-bpe-smoke/problem.md \
  --description local-smoke \
  --no-results \
  --log-file .build/example-logs/03-mlx-bpe-smoke.log
```

Remove `--no-results` when you want to append a scored row to `results.tsv`.

## Use The Output

Look at the final block:

```text
val_bpb: ...
tokenizer_compression_ratio: ...
tokenizer_vocab_size: ...
tokenizer: bpe
training_backend: mlx
```

`val_bpb` is the model score. Lower is better. Use
`tokenizer_compression_ratio` to understand what happened before training: it
tells you how much the BPE artifact shortened the corpus in token space.

On the checked-in corpus, a local CPU smoke run compressed the text to about
`0.28` of the original byte-token count, then produced a real MLX validation
score through the BPE runtime. The useful moment is that the tokenizer is not a
dead artifact; it changes the token stream the model trains on.

## Try Next

On Apple Silicon, change `MLX_DEVICE=gpu` in `candidate.sh`. Then try changing
`MLX_DIM`, `MLX_MLP_DIM`, or `MLX_WINDOW_PATTERN` and compare `val_bpb`.
