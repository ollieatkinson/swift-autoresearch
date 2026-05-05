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
run, prepares it, trains a fixed MLX baseline and the mutable candidate, parses
`improvement_bpb`, and appends one row to the example `results.tsv`.

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
  - candidate.sh
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

## Reading Output

For MLX training examples, `val_bpb` is validation bits per byte and lower is
better. The examples make the improvement explicit by running an immutable weak
baseline and the mutable candidate on the same data, then printing
`improvement_bpb = baseline_val_bpb - candidate_val_bpb`. Positive
`improvement_bpb` means the candidate predicts held-out bytes better than the
fixed baseline.

The live training lines are diagnostic. `loss` shows current training loss,
`tok/sec` shows throughput, `dt` shows step time, `epoch` shows data progress,
and `remaining` shows the wall-clock budget left. The final summary fields such
as `num_steps`, `total_tokens_M`, `training_seconds`, and `peak_vram_mb` explain
what fit inside the budget. They are useful for understanding why a candidate
won or lost, but `improvement_bpb` is the metric used by the example loop.

For generic problem examples, the final parsed metric and `status` are the
important loop output. The run log keeps the evaluator's full stdout and stderr.
For the North Yorkshire example, `score` is maximized. The candidate sees only
Jan-Feb discovery summaries and returns one claim. The evaluator scores that
claim on March hold-out data and prints discovery/hold-out counts, shares,
`z_score`, `p_value`, `lift`, and `effect_size`. The smoking gun is a claim that
was found in discovery and still holds in the held-out month.

## Examples

The examples are intentionally separate. Each problem owns its own immutable
`problem.md`, fixed `evaluate.sh`, mutable candidate file, cache directory, and
`results.tsv`. The examples do not mutate the package implementation; the agent
mutates only example-local candidate files.

### Alice Gutenberg

This is the main silly public-data example. It uses the Project Gutenberg
plain-text UTF-8 edition of `Alice's Adventures in Wonderland`, eBook #11:

<https://www.gutenberg.org/ebooks/11>

The only mutable file is
[Examples/alice-gutenberg/candidate.sh](Examples/alice-gutenberg/candidate.sh).
It is intentionally small: the agent can change MLX model size, batch size,
sequence length, learning rate, and weight decay without touching the
`autoresearch` package source. The evaluator prints `baseline_val_bpb`,
`candidate_val_bpb`, and `improvement_bpb` so it is obvious what got better.

1. Read the immutable problem contract:

   ```bash
   sed -n '1,120p' Examples/alice-gutenberg/problem.md
   ```

2. Run one evaluation:

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
   stay fixed. The agent mutates only `Examples/alice-gutenberg/candidate.sh`,
   commits a candidate, runs:

   ```bash
   swift run autoresearch evaluate \
     --problem Examples/alice-gutenberg/problem.md \
     --description "short experiment description"
   ```

   A `keep` row means the candidate beat the previous best improvement. A
   `discard` row means the candidate ran but did not improve. A `crash` row
   means the evaluator failed, timed out, or did not print `improvement_bpb`.

The candidate portion of the evaluator performs this MLX run after the fixed
baseline run:

```bash
source Examples/alice-gutenberg/candidate.sh
swift run autoresearch train \
  --backend mlx \
  --mlx-device gpu \
  --cache-dir .build/alice-gutenberg/cache \
  --time-budget 5 \
  --max-seq-len "$MAX_SEQ_LEN" \
  --device-batch-size "$DEVICE_BATCH_SIZE" \
  --total-batch-size "$TOTAL_BATCH_SIZE" \
  --eval-tokens 4096 \
  --learning-rate "$LEARNING_RATE" \
  --weight-decay "$WEIGHT_DECAY" \
  --mlx-layers "$MLX_LAYERS" \
  --mlx-dim "$MLX_DIM" \
  --mlx-heads "$MLX_HEADS" \
  --mlx-mlp-dim "$MLX_MLP_DIM"
```

### Tiny Lab Notes

This is a no-network smoke example with a tiny checked-in corpus:

```bash
swift run autoresearch evaluate \
  --problem Examples/tiny-lab-notes/problem.md \
  --description baseline
```

It is useful for checking the loop quickly, but it is too small to be an
interesting optimization target. Its mutable file is
[Examples/tiny-lab-notes/candidate.sh](Examples/tiny-lab-notes/candidate.sh).
The evaluator compares the candidate against an immutable weak MLX baseline and
prints `improvement_bpb`, so the smoke test has the same "what got better"
shape as the larger Alice example.

### North Yorkshire Crime Hypotheses

This example is a self-contained open-data hypothesis search. It uses the
Police.uk street-level crime API catalogued by data.gov.uk, caches a fixed slice
of January-March 2024 data around York, Harrogate, Scarborough, and
Northallerton, and validates one mutable discovery strategy:

```bash
swift run autoresearch evaluate \
  --problem Examples/uk-crime-hypotheses/problem.md \
  --description baseline
```

Only [Examples/uk-crime-hypotheses/candidate.py](Examples/uk-crime-hypotheses/candidate.py)
is mutable. The fixed evaluator owns the data download, aggregation, hold-out
split, statistical test, and scoring. The checked-in candidate sees Jan-Feb
summaries, selects one claim, and the evaluator checks whether March supports
it. A useful candidate edit is to change that selection strategy: add different
category filters, adjust minimum counts, penalize tiny reference groups, or
search lower shares as well as higher shares.

### Other Problem Shapes

The loop is domain-neutral. A problem can tune Swift code, Go code, a trading
strategy, data-cleaning rules, or model hyperparameters. Keep the same split:

- `problem.md`: immutable goal, metric, direction, timeout, mutable paths.
- `evaluate.sh`: fixed evaluator that prints `metric: value`.
- candidate files: mutable code/config the agent can edit.
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
