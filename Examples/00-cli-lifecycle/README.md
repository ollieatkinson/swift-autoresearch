# 00 CLI Lifecycle

Direct CLI example. This is the place to see the individual commands before
they are wrapped by an evaluator loop.

The checked-in corpus is small and repetitive on purpose. That makes each
stage visible:

- `prepare` turns raw UTF-8 text into cached `train.txt` and `val.txt` files.
- `train-tokenizer` learns repeated byte sequences and writes `tokenizer.json`.
- `train` consumes the prepared cache and reports validation bits per byte.
  The default `auto` backend prefers MLX and falls back to bigram if MLX setup
  is unavailable.
- `evaluate` is what later examples use to make those steps repeatable and
  comparable.

This example is not trying to produce a good language model. It is a concrete
tour of the lifecycle: raw text becomes a fixed train/validation split, repeated
byte sequences become a tokenizer artifact, and a trainer turns the prepared
split into a held-out score.

## Run It

```bash
bash Examples/00-cli-lifecycle/run.sh
```

The script writes everything under `.build/00-cli-lifecycle/`, so it can be
rerun without touching your default cache.

The output has three sections:

```text
--- prepare checked-in corpus ---
--- train native BPE tokenizer artifact ---
--- train default backend from prepared cache ---
```

Read them as a pipeline. The tokenizer section is intentionally separate from
the default training section: `train-tokenizer` produces an artifact, but
`train` uses the byte tokenizer unless you pass BPE flags:
`--tokenizer bpe --tokenizer-file ...`.

## Step 1: Prepare Data

```bash
swift run autoresearch prepare \
  --input Examples/00-cli-lifecycle/corpus.txt \
  --cache-dir .build/00-cli-lifecycle/cache \
  --validation-fraction 0.25
```

The useful output is the split:

```text
train_documents: ...
validation_documents: ...
train_bytes: ...
validation_bytes: ...
```

The command writes:

```text
.build/00-cli-lifecycle/cache/data/train.txt
.build/00-cli-lifecycle/cache/data/val.txt
```

That is the handoff to model training. The trainer does not read the original
corpus path; it reads the prepared cache so multiple runs can compare against
the same train/validation split.

How to interpret the fields:

- `train_documents` and `validation_documents` show how many document chunks
  went into each side of the split. For a single long file, `prepare` can split
  by bytes; for paragraph-style text like this example, it splits document
  chunks.
- `train_bytes` is the text the model is allowed to learn from.
- `validation_bytes` is held-out text used for the final score. It is not a
  private benchmark, but it is enough to show the train/validation contract.
- The `wc -c` lines in `run.sh` confirm the cache files exist and contain the
  same byte counts reported by `prepare`.

## Step 2: Train A Tokenizer

```bash
swift run autoresearch train-tokenizer \
  --input Examples/00-cli-lifecycle/corpus.txt \
  --output .build/00-cli-lifecycle/tokenizer.json \
  --vocab-size 288 \
  --min-pair-frequency 2 \
  --max-training-bytes 10000
```

Look at:

```text
initial_tokens: ...
final_tokens: ...
compression_ratio: ...
merges: ...
```

The useful moment is concrete: repeated phrases like `dispatch note` and
`held-out surprise` become cheaper in token space before any model trains. The
artifact at `.build/00-cli-lifecycle/tokenizer.json` is the file MLX can load
with `--tokenizer bpe --tokenizer-file ...`.

How to interpret the fields:

- `initial_tokens` is the byte-token baseline. Before BPE, each UTF-8 byte is
  one token, plus special tokens where needed.
- `final_tokens` is the number of tokens after learned byte-pair merges are
  applied to the same text.
- `compression_ratio = final_tokens / initial_tokens`. Lower means the
  tokenizer represents this corpus with fewer tokens.
- `vocab_size` is the actual artifact vocabulary size, including byte tokens
  and special tokens.
- `merges` is how many byte-pair merges were learned before hitting the
  requested vocabulary size or `min-pair-frequency`.

This is useful even before model training because language-model cost is often
paid in tokens. A tokenizer that turns repeated phrases into fewer tokens can
fit more text into the same sequence length. That does not guarantee better
model quality, especially on a tiny corpus, but it makes the artifact's effect
visible.

## Step 3: Train The Default Backend

```bash
swift run autoresearch train \
  --cache-dir .build/00-cli-lifecycle/cache \
  --time-budget 1 \
  --max-seq-len 32 \
  --device-batch-size 2 \
  --total-batch-size 64 \
  --eval-tokens 512
```

The final block includes:

```text
val_bpb: ...
training_seconds: ...
total_seconds: ...
peak_vram_mb: ...
total_tokens_M: ...
num_steps: ...
num_params_M: ...
depth: ...
```

`val_bpb` is validation bits per byte. Lower is better because the model needed
fewer bits, on average, to predict each held-out byte.

The first line tells you which backend was selected:

```text
backend: mlx (auto)
```

If MLX setup is unavailable, auto mode prints a fallback line and trains the
byte bigram backend instead. Use `--backend mlx` when you want MLX failures to
stop the run, or `--backend bigram` when you specifically want the lightweight
harness.

How to interpret the training output:

- `Model config` tells you whether the run used the MLX transformer or the
  byte-level bigram model. MLX is the preferred default because it is the real
  neural backend; bigram is a dependency-light fallback and harness check.
- `Parameter counts` tells you the rough model size. More parameters can help,
  but they also cost time and memory.
- Progress lines show training loss, learning-rate multiplier, step time, and
  token throughput. They are diagnostics, not the score.
- `training_seconds` is the timed training loop budget. `total_seconds` also
  includes setup and final validation.
- `peak_vram_mb` is process peak resident memory as reported by the OS. The
  name is historical; treat it as a coarse memory indicator.
- `total_tokens_M` is the nominal number of training tokens processed.
- `num_steps` is optimizer steps completed inside the budget.
- `num_params_M` and `depth` summarize model size. For bigram, depth is `1`.

The result to compare between training runs is `val_bpb`, with the same cache,
same sequence length, and same evaluation token count. On this toy corpus, a
small change can move the score a lot, so read it as a lifecycle smoke result,
not as a robust benchmark.

## Use The Output

After the script finishes, use the output in this order:

1. Confirm `prepare` created a real split. `train_bytes` and
   `validation_bytes` should both be non-zero, and the `wc -c` lines should
   point at `.build/00-cli-lifecycle/cache/data/train.txt` and `val.txt`.
2. Check whether tokenizer training found structure. `compression_ratio` below
   `1.0` means the BPE artifact represents the same text with fewer tokens. For
   example, `0.60` means the text uses about 60 percent as many tokens as the
   byte-token baseline.
3. Check which backend trained. `backend: mlx (auto)` means the default path
   used MLX. A `backend: bigram (auto fallback; ...)` line means MLX setup was
   unavailable and the command used the lightweight fallback.
4. Use `val_bpb` as the model score. Lower is better, but only compare it
   between runs that use the same prepared cache, sequence length, evaluation
   token count, backend, and tokenizer.
5. Use the printed paths for follow-up runs. The prepared cache is the input to
   later `train` commands; `tokenizer.json` is only used when you pass
   `--tokenizer bpe --tokenizer-file .build/00-cli-lifecycle/tokenizer.json`.

The concrete next actions are:

- If MLX fell back unexpectedly, rerun with `--backend mlx` so the setup error
  stops the run and tells you what to fix.
- If tokenizer compression looks useful, run the optional BPE command below and
  compare its `val_bpb` against another BPE run with the same settings.
- If you want a repeatable keep/discard loop, move to the evaluator-backed
  examples. They wrap this lifecycle in a problem document and append
  comparable result rows.

## Optional: Train MLX With The BPE Artifact

On Apple Silicon, switch to the MLX backend and load the tokenizer artifact:

```bash
swift run autoresearch train \
  --backend mlx \
  --tokenizer bpe \
  --tokenizer-file .build/00-cli-lifecycle/tokenizer.json \
  --mlx-device gpu \
  --cache-dir .build/00-cli-lifecycle/cache \
  --time-budget 5 \
  --max-seq-len 32 \
  --device-batch-size 1 \
  --total-batch-size 32 \
  --eval-tokens 512 \
  --learning-rate 0.001 \
  --mlx-layers 1 \
  --mlx-dim 32 \
  --mlx-heads 4 \
  --mlx-mlp-dim 64
```

That is the same prepared split, plus the tokenizer artifact, plus a different
model backend. The later evaluator examples package this pattern into one
scored command so candidate changes can be kept or discarded consistently.

The output now has two extra things to check:

- `Tokenizer: bpe` confirms the artifact is actually loaded.
- `Vocab size` should match the tokenizer artifact, not the byte tokenizer's
  `257` token vocabulary.

If BPE lowers token count but `val_bpb` gets worse, that is not necessarily a
bug. Tokenizer compression, model size, learning rate, and time budget interact.
The point of `evaluate` in the later examples is to hold the problem contract
fixed while you try those changes one at a time.
