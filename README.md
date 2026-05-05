# swift-autoresearch

A Swift port of the core autoresearch training loop from
`~/src/github.com/karpathy/autoresearch`.

The default model is a dependency-free Swift-native byte-level bigram baseline.
The package also includes an MLX-backed causal transformer for native
tensor/autograd experiments. Both backends preserve the shape of the Python
loop: prepare data, pack token batches, train for a fixed wall-clock budget,
evaluate validation bits per byte, and print the same summary fields.

## Quick Start

```bash
swift run autoresearch evaluate \
  --problem Examples/alice-gutenberg/problem.md \
  --description baseline
```

That command downloads a small public-domain Project Gutenberg text on first
run, prepares it, trains the MLX backend for a fixed budget, parses `val_bpb`,
and appends one row to the example `results.tsv`.

`prepare` still exists as a lower-level command. It requires an explicit UTF-8
text file or directory of `.txt` files.

Xcode builds MLX's Metal shader bundle as part of the package build. Plain
SwiftPM CLI builds do not, so the CLI automatically prepares `mlx.metallib`
next to the executable before MLX starts. It first reuses Xcode's
`mlx-swift_Cmlx.bundle` when present, then falls back to compiling MLX's
generated kernels with Xcode's Metal Toolchain. If the Metal Toolchain
component is missing, install it once with:

```bash
xcodebuild -downloadComponent MetalToolchain
```

Use the Apple GPU explicitly:

```bash
swift run autoresearch train --backend mlx --mlx-device gpu --time-budget 300
```

## Xcode And CLI

Keep `Package.swift` as the source of truth. Xcode can open the Swift package
and build the same `autoresearch` executable product that SwiftPM runs
from the shell:

```bash
swift run autoresearch train --backend mlx --mlx-device gpu
```

For command-line MLX runs from SwiftPM, no separate setup command or shell
script is required after the Metal Toolchain component is installed.

Prepared data is stored in `~/.cache/swift-autoresearch/data/` by default:

- `train.txt`
- `val.txt`

You can override the cache location with `--cache-dir` or the
`AUTORESEARCH_CACHE_DIR` environment variable.

## Generic Problems

The generic loop mirrors the original autoresearch contract: the problem
document is immutable, the evaluator is fixed, and the agent mutates only the
declared candidate files. The evaluator can be any command as long as it prints
the configured metric as `key: value` text.

```markdown
---
name: my-problem
metric: score
direction: minimize
evaluator: bash evaluate.sh
timeout_seconds: 600
results: results.tsv
mutable:
  - train.py
---
```

Run one evaluation and append the result:

```bash
swift run autoresearch evaluate --problem problem.md --description baseline
```

`evaluate` streams the evaluator output live between phase markers, so long
training or benchmark runs show their own progress. Use `--quiet` for scripted
runs that should only print the final parsed result.

The results file follows the original TSV shape:

```text
commit	score	memory_gb	status	description
```

`status` is `keep` for the first valid result or a strict metric improvement,
`discard` for a non-improvement, and `crash` when the evaluator exits non-zero,
times out, or does not print the metric.

## Examples

The examples are intentionally separate. Each problem owns its own immutable
`problem.md`, fixed `evaluate.sh`, cache directory, and `results.tsv`.

### Alice Gutenberg

This is the main silly public-data example. It uses the Project Gutenberg
plain-text UTF-8 edition of `Alice's Adventures in Wonderland`, eBook #11:

<https://www.gutenberg.org/ebooks/11>

1. Read the immutable problem contract:

   ```bash
   sed -n '1,120p' Examples/alice-gutenberg/problem.md
   ```

2. Run the baseline evaluation:

   ```bash
   swift run autoresearch evaluate \
     --problem Examples/alice-gutenberg/problem.md \
     --description baseline
   ```

3. Inspect the run log and results:

   ```bash
   tail -n 40 Examples/alice-gutenberg/run.log
   cat Examples/alice-gutenberg/results.tsv
   ```

4. Start an agent loop on a fresh branch. The problem document and evaluator
   stay fixed. The agent mutates only paths listed under `mutable`, commits a
   candidate, runs:

   ```bash
   swift run autoresearch evaluate \
     --problem Examples/alice-gutenberg/problem.md \
     --description "short experiment description"
   ```

   A `keep` row means the candidate beat the previous best metric. A `discard`
   row means the candidate ran but did not improve. A `crash` row means the
   evaluator failed, timed out, or did not print `val_bpb`.

The evaluator performs the concrete MLX run:

```bash
swift run autoresearch train \
  --backend mlx \
  --mlx-device gpu \
  --cache-dir .build/alice-gutenberg/cache \
  --time-budget 5 \
  --max-seq-len 128 \
  --device-batch-size 4 \
  --total-batch-size 512 \
  --eval-tokens 4096 \
  --mlx-layers 1 \
  --mlx-dim 32 \
  --mlx-heads 4 \
  --mlx-mlp-dim 64
```

### Tiny Lab Notes

This is a no-network smoke example with a tiny checked-in corpus:

```bash
swift run autoresearch evaluate \
  --problem Examples/tiny-lab-notes/problem.md \
  --description baseline
```

It is useful for checking the loop quickly, but it is too small to be an
interesting optimization target.

### Other Problem Shapes

The loop is domain-neutral. A problem can tune Swift code, Go code, a trading
strategy, data-cleaning rules, or model hyperparameters. Keep the same split:

- `problem.md`: immutable goal, metric, direction, timeout, mutable paths.
- `evaluate.sh`: fixed evaluator that prints `metric: value`.
- mutable files: the candidate surface the agent can edit.
- `results.tsv`: uncommitted experiment log.

## What Is Ported

- Fixed-time training loop.
- Batch packing with BOS-aligned rows and no padding.
- Validation BPB evaluation.
- Learning-rate warmdown schedule.
- Final summary output compatible with the original `program.md` expectations.
- A deterministic bigram baseline model and optimizer implemented in Swift.
- A small MLX-backed causal transformer backend for native tensor/autograd experiments.

## Current Limitation

This is not yet a numerical parity port of `train.py`. The original uses
PyTorch, CUDA, FlashAttention, a BPE tokenizer, Parquet data shards, Muon, and a
larger GPT architecture. The MLX backend gives us a native Swift tensor path to
iterate on, while the bigram backend stays useful for fast harness tests.

## Useful Commands

```bash
swift test
swift run autoresearch prepare --help
swift run autoresearch train --help
swift run autoresearch train --backend mlx --mlx-device gpu --time-budget 5 --max-seq-len 128 --device-batch-size 4 --total-batch-size 512 --eval-tokens 4096
swift run autoresearch evaluate --problem Examples/tiny-lab-notes/problem.md --description baseline
swift run autoresearch evaluate --problem Examples/alice-gutenberg/problem.md --description baseline
```
