# Example Agent Prompt

Paste this into Codex, Claude Code, or another coding agent from the repository
root.

```text
Run an autoresearch loop for `Examples/04-alice-gutenberg`.

Read the example README and `problem.md`. Use the problem document as the
contract for the metric, direction, evaluator, result log, and mutable files.

Goal: improve `improvement_bpb`. Higher is better.

Run the evaluator with numbered descriptions, for example:
`swift run autoresearch evaluate --problem Examples/04-alice-gutenberg/problem.md --description "01 tune training knobs"`

Let the evaluator append result rows. Try 3-5 candidate changes, keeping
improvements and reverting regressions. Useful knobs include learning rate,
model dimensions, batch sizes, sequence length, and weight decay. Do not commit
unless explicitly asked.

When finished, report the new result rows, explain which training knobs helped
or hurt, and state the final `improvement_bpb`.
```
