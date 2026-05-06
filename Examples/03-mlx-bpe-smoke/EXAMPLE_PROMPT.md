# Example Agent Prompt

Paste this into Codex, Claude Code, or another coding agent from the repository
root.

```text
Run an autoresearch loop for `Examples/03-mlx-bpe-smoke`.

Read the example README and `problem.md`. Use the problem document as the
contract for the metric, direction, evaluator, result log, and mutable files.

Goal: improve `val_bpb`. Lower is better.

Run the evaluator with numbered descriptions, for example:
`swift run autoresearch evaluate --problem Examples/03-mlx-bpe-smoke/problem.md --description "01 tune mlx settings"`

Let the evaluator append result rows. Try 3-5 candidate changes, keeping
improvements and reverting regressions. Useful knobs include tokenizer
settings, model size, sequence length, learning rate, and `MLX_DEVICE`. Do not
commit unless explicitly asked.

When finished, report the new result rows, explain whether tokenizer or model
settings drove the change, and state the final `val_bpb`.
```
