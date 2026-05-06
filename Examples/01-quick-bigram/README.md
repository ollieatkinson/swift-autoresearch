# 01 Quick Bigram

Beginner example. This is the smallest useful language-model example in the
repo: it prepares a tiny checked-in corpus, trains the byte bigram backend, and
turns the run into a `val_bpb` score.

## Run It

```bash
swift run autoresearch evaluate \
  --problem Examples/01-quick-bigram/problem.md \
  --description local-smoke \
  --no-results \
  --log-file .build/example-logs/01-quick-bigram.log
```

Remove `--no-results` when you want to append a scored row to `results.tsv`.

## Use The Output

Look at the final block:

```text
val_bpb: ...
training_backend: bigram
tokenizer: byte
learning_rate: ...
```

`val_bpb` is validation bits per byte. Lower is better because the model needed
fewer bits, on average, to predict each held-out byte.

The useful moment is seeing the harness work without MLX: `candidate.sh` is the
only mutable file, but the evaluator prepares data, trains, parses the summary,
and produces a comparable score.

## Demonstrated Local Run

A local run produced:

```text
val_bpb: 5.252667
training_backend: bigram
tokenizer: byte
time_budget: 1
learning_rate: 0.25
```

This is not trying to be a strong language model. The useful result is that the
whole fixed-budget loop works in a few seconds with no MLX dependency: prepare
data, train, evaluate held-out bytes, parse a metric, and return a score.

That makes this the right first example when changing the evaluator or result
logging. If this example fails, the issue is probably in the harness contract,
not in GPU kernels or model architecture.

## Autoresearch Loop

This table shows a local autoresearch-style loop. The operator ran the
evaluator with numbered descriptions. Between rows, the model edited
`candidate.sh`; the evaluator appended each score to `results.tsv`; after the
loop, the checked-in candidate was restored.

```text
commit   val_bpb   memory_gb  status   description
f654be6  5.239434  0.0        keep     00 baseline learning rate
f654be6  6.041033  0.0        discard  01 lower learning rate
f654be6  5.136839  0.0        keep     02 double time budget
f654be6  7.192342  0.0        discard  03 too high learning rate
```

The useful behavior is that the evaluator makes tradeoffs visible even in the
smallest backend. Lowering the learning rate under-trained in the one-second
budget, doubling the budget improved the score, and pushing the learning rate
too high made held-out BPB worse.

## Try Next

Change `LEARNING_RATE` or `TIME_BUDGET` in `candidate.sh`, rerun the evaluator,
and compare the final `val_bpb`.
