# Example Agent Prompt

Paste this into Codex, Claude Code, or another coding agent from the repository
root.

```text
Run an autoresearch loop for `Examples/01-quick-bigram`.

Read the example README and `problem.md`. Use the problem document as the
contract for the metric, direction, evaluator, result log, and mutable files.

Goal: improve `val_bpb`. Lower is better.

Run the evaluator with numbered descriptions, for example:
`swift run autoresearch evaluate --problem Examples/01-quick-bigram/problem.md --description "01 tune learning rate"`

Let the evaluator append result rows. Try 3-5 candidate changes, keeping
improvements and reverting regressions. Do not commit unless explicitly asked.

When finished, report the new result rows, explain which changes were kept or
discarded, and state the final `val_bpb`.
```
