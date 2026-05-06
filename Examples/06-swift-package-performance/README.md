# 06 Swift Package Performance

Real-world Swift tooling example. This is a complete nested Swift package with
an executable target. The evaluator measures both parts a developer feels when
working on a command-line tool:

- clean release build time
- runtime of the built executable

The package starts intentionally bad. The source has a chunky type-inferred
expression in the compile path and an O(n^2) runtime loop that repeatedly
splits the same strings.

## Run It

```bash
swift run autoresearch evaluate \
  --problem Examples/06-swift-package-performance/problem.md \
  --description local-smoke \
  --no-results \
  --log-file .build/example-logs/06-swift-package-performance.log
```

Remove `--no-results` when you want to append a scored row to `results.tsv`.

## Use The Output

Look at the final block:

```text
score: ...
build_seconds: ...
run_seconds: ...
checksum: ...
scoring_rule: build_seconds + run_seconds
```

`score` is the metric, and lower is better. The evaluator verifies `checksum`
so a candidate cannot improve by deleting the work.

## What This Tests

This is a package-performance optimization task, not a language-model task. The
mutable file is:

```text
PackageUnderTest/Sources/BuildRunProbe/main.swift
```

The evaluator copies the package to `.build/06-swift-package-performance/`,
runs a clean `swift build -c release`, then runs the release executable
directly. Runtime does not include another SwiftPM build. The evaluator is a
plain bash script; there is no Python helper in this example.

## Demonstrated Local Run

A baseline local run produced:

```text
score: 7.473000
build_seconds: 2.971
run_seconds: 4.502
checksum: 53633945
```

The useful moment is that the total score separates the two bottlenecks. In
this starting package, runtime dominates, so parsing each record once and
replacing the O(n^2) comparison should matter more than shaving a few compiler
milliseconds.

## Autoresearch Loop

I ran this as a local autoresearch loop by letting the evaluator append to its
ignored `results.tsv`:

```bash
rm -f Examples/06-swift-package-performance/results.tsv
swift run autoresearch evaluate \
  --problem Examples/06-swift-package-performance/problem.md \
  --description "00 baseline string splitting"
```

Then I edited `PackageUnderTest/Sources/BuildRunProbe/main.swift` between runs
and repeated the same command with a new description. I did not commit the
generated `results.tsv`; the rows below are copied here to show the loop.

```text
commit   score     memory_gb  status   description
f654be6  7.473000  0.0        keep     00 baseline string splitting
f654be6  3.644000  0.0        keep     01 parse records once
f654be6  3.869000  0.0        discard  02 add no-op runtime audit
f654be6  3.854000  0.0        discard  03 aggregate repeated comparisons
f654be6  3.663000  0.0        discard  04 compact ids and array counts
f654be6  3.032000  0.0        keep     05 precompute fixed compile tax
```

The important behavior is that the evaluator kept only strict improvements
against the best previous kept score:

- `01 parse records once` was kept because it cut runtime by removing repeated
  string splitting from the hot loop.
- `02 add no-op runtime audit` preserved the checksum but was discarded because
  it made the program slower.
- `03 aggregate repeated comparisons` and `04 compact ids and array counts`
  were plausible optimizations, but they lost on the combined build-plus-run
  metric in this timing run.
- `05 precompute fixed compile tax` was kept because it preserved the checksum
  and lowered the combined score to `3.032000`.

All rows show the same commit because this was run with local uncommitted
candidate edits. The checked-in package remains at the intentionally slow
starting point so readers can reproduce the loop.

Useful fixes are intentionally obvious:

- split large inferred expressions into named, typed steps
- parse each record once instead of repeatedly splitting strings in the hot loop
- replace the O(n^2) comparison with precomputed counts or buckets
- keep the same printed checksum

## What It Does Not Prove

Single build timings are noisy. Spotlight, thermal state, SwiftPM caches, and
other local processes can move the number. Use this as a compact harness for
candidate comparison, then rerun promising changes more than once.

This example also measures a tiny package, not this repository's own build. The
point is to make build/run optimization safe to iterate on inside the example.

## Try Next

Edit `main.swift`, rerun the evaluator, and compare `score`. If `run_seconds`
drops but `build_seconds` rises, the combined metric will show whether the
tradeoff was actually worth it for this workflow.
