---
name: swift-package-performance
metric: score
direction: minimize
evaluator: bash evaluate.sh
timeout_seconds: 180
results: results.tsv
mutable:
  - PackageUnderTest/Sources/BuildRunProbe/main.swift
---

# Swift Package Performance

This example measures a real developer workflow: clean release build time plus
the runtime of the built executable.

The evaluator copies `PackageUnderTest` into `.build/06-swift-package-performance/`,
runs `swift build -c release`, runs the built executable directly, verifies the
checksum, and reports. This example uses a plain bash evaluator:

```text
score: ...
build_seconds: ...
run_seconds: ...
checksum: ...
```

The score is `build_seconds + run_seconds`, and lower is better. The mutable
surface is the package executable source:

```text
PackageUnderTest/Sources/BuildRunProbe/main.swift
```

The checked-in candidate is intentionally poor. It has a chunky inferred
expression in the compile path and an obvious runtime hot loop that repeatedly
splits the same records inside an O(n^2) comparison.

## Evaluate

```bash
swift run autoresearch evaluate \
  --problem Examples/06-swift-package-performance/problem.md \
  --description local-smoke \
  --no-results \
  --log-file .build/example-logs/06-swift-package-performance.log
```
