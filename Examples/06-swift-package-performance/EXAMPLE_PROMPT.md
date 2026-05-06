# Example Agent Prompt

Paste this into Codex, Claude Code, or another coding agent from the repository
root.

```text
Run an autoresearch loop for `Examples/06-swift-package-performance`.

Read the example README and `problem.md`. Use the problem document as the
contract for the metric, direction, evaluator, result log, and mutable files.

Goal: improve `score`, where score is clean release build time plus executable
runtime. Lower is better.

Run the evaluator with numbered descriptions, for example:
`swift run autoresearch evaluate --problem Examples/06-swift-package-performance/problem.md --description "01 optimize hot path"`

Let the evaluator append result rows. Try 4-7 candidate changes, keeping
improvements and reverting regressions. Preserve the checksum behavior; do not
remove work to make the program faster. Do not commit unless explicitly asked.

When finished, report the new result rows, explain build-time versus runtime
tradeoffs, and state the final `score`, `build_seconds`, `run_seconds`, and
`checksum`.
```
