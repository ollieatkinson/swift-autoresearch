# swift-autoresearch

`swift-autoresearch` is a Swift package for running fixed-budget research
experiments on Apple hardware. It includes:

- a generic evaluator loop for problem documents and TSV result logs
- a dependency-light byte bigram backend for fast harness checks
- an MLX-backed GPT-style language-model backend for native Swift tensor runs
- byte and loadable BPE tokenizer support

The upstream project this tracks conceptually is
<https://github.com/karpathy/autoresearch>. This repository is an Apple-native
Swift implementation of the same fixed-budget experimentation idea, not a
numerical parity port of the Python training script.

## Current Status

Implemented:

- text preparation from UTF-8 `.txt` files
- BOS-aligned packed batches with no padding
- fixed wall-clock training budget
- validation bits per byte (`val_bpb`)
- byte-tokenized bigram backend
- MLX GPT-style backend with RoPE, Q/K norm, fast causal attention, ReLU-squared
  MLP, RMSNorm, softcapped logits, AdamW, and optional attention window patterns
- optional BPE tokenizer loading from a Swift-readable JSON artifact
- generic problem evaluation and result logging

Not implemented:

- PyTorch or CUDA support
- CUDA FlashAttention
- Muon optimizer
- Parquet shard download/streaming
- native Swift BPE training
- exact numerical parity with upstream `train.py`

For Apple hardware, the important missing parity items are Parquet data support,
Muon, and native BPE training. CUDA-specific pieces are intentionally out of
scope.

## Requirements

- macOS 14 or newer
- Swift 6.3 toolchain
- Xcode command line tools
- Apple Silicon recommended for MLX GPU runs

SwiftPM command-line MLX runs need MLX Metal kernels next to the executable.
The CLI prepares `mlx.metallib` automatically before MLX training starts. If
the Metal Toolchain is missing, install it once:

```bash
xcodebuild -downloadComponent MetalToolchain
```

## Quick Start

Run the small checked-in smoke example:

```bash
swift run autoresearch evaluate \
  --problem Examples/tiny-lab-notes/problem.md \
  --description baseline
```

Run the Project Gutenberg example:

```bash
swift run autoresearch evaluate \
  --problem Examples/alice-gutenberg/problem.md \
  --description baseline
```

The evaluator prints the parsed metric and appends a row to the example
`results.tsv`.

## Data Preparation

`prepare` accepts a UTF-8 text file or a directory of `.txt` files:

```bash
swift run autoresearch prepare --input corpus.txt
```

Prepared data is written to:

```text
~/.cache/swift-autoresearch/data/train.txt
~/.cache/swift-autoresearch/data/val.txt
```

Use `--cache-dir` or `AUTORESEARCH_CACHE_DIR` to choose a different cache root.

## Training

The default backend is the fast byte bigram harness:

```bash
swift run autoresearch train
```

Run the MLX backend on the Apple GPU:

```bash
swift run autoresearch train \
  --backend mlx \
  --mlx-device gpu \
  --time-budget 300
```

Common MLX controls:

```bash
swift run autoresearch train \
  --backend mlx \
  --mlx-device gpu \
  --max-seq-len 512 \
  --device-batch-size 8 \
  --total-batch-size 4096 \
  --learning-rate 0.001 \
  --weight-decay 0.0 \
  --mlx-layers 4 \
  --mlx-dim 256 \
  --mlx-heads 4 \
  --mlx-mlp-dim 1024 \
  --mlx-window-pattern SSSL
```

`L` means full causal attention for that layer. `S` means half-window causal
attention. The last layer always uses full attention.

## Tokenizers

The default tokenizer is byte-level:

```bash
swift run autoresearch train --backend mlx --tokenizer byte
```

BPE tokenization is available by loading a JSON artifact:

```bash
swift run autoresearch train \
  --backend mlx \
  --tokenizer bpe \
  --tokenizer-file tokenizer.json
```

The bigram backend is byte-only. BPE is currently runtime-only: this package
does not train BPE vocabularies.

### BPE Artifact Format

The artifact is JSON with these fields:

- `version`: currently `1`
- `bos_token_id`: integer token id for BOS
- `token_bytes`: array indexed by token id, with each entry as base64-encoded
  bytes
- `merge_ranks`: array of `{ "left": base64, "right": base64, "rank": int }`
  merge records
- `special_tokens`: object mapping special token strings to token ids

A production artifact must include all 256 single-byte tokens in `token_bytes`
so arbitrary UTF-8 text can be encoded. Special tokens, including BOS, have byte
length zero for BPB evaluation.

## Evaluation Loop

The generic evaluator reads a Markdown problem document with YAML front matter:

```markdown
---
name: my-problem
metric: score
direction: minimize
evaluator: bash evaluate.sh
timeout_seconds: 600
results: results.tsv
mutable:
  - candidate.sh
---
```

Run one evaluation:

```bash
swift run autoresearch evaluate \
  --problem problem.md \
  --description "baseline"
```

The evaluator command can be any executable that prints the configured metric
as `key: value`. Results are appended as TSV rows with this shape:

```text
commit	score	memory_gb	status	description
```

`status` is:

- `keep` for the first valid result or a strict metric improvement
- `discard` for a valid non-improvement
- `crash` for evaluator failure, timeout, or missing metric output

## Examples

### Tiny Lab Notes

A no-network smoke test with a tiny checked-in corpus:

```bash
swift run autoresearch evaluate \
  --problem Examples/tiny-lab-notes/problem.md \
  --description baseline
```

### Alice Gutenberg

A public-domain text example based on Project Gutenberg eBook #11,
`Alice's Adventures in Wonderland`:

```bash
swift run autoresearch evaluate \
  --problem Examples/alice-gutenberg/problem.md \
  --description baseline
```

### North Yorkshire Crime Hypotheses

A non-language-model example that scores one discovery claim against held-out
Police.uk crime data:

```bash
swift run autoresearch evaluate \
  --problem Examples/uk-crime-hypotheses/problem.md \
  --description baseline
```

## Output Fields

For MLX and bigram training, lower `val_bpb` is better. Final summary fields
include:

- `val_bpb`: validation bits per byte
- `training_seconds`: timed training loop duration
- `total_seconds`: full process duration
- `peak_vram_mb`: process peak resident memory as reported by the OS
- `total_tokens_M`: nominal training tokens processed
- `num_steps`: optimizer steps
- `num_params_M`: model parameters
- `depth`: model depth

Progress lines are diagnostic only. Example problem metrics are defined by each
problem document.

## Development Commands

```bash
swift test
swift run autoresearch prepare --help
swift run autoresearch train --help
swift run autoresearch evaluate --help
```
