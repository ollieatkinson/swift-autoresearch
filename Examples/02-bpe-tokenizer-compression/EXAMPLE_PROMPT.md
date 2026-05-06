# Example Agent Prompt

Paste this into Codex, Claude Code, or another coding agent from the repository
root.

```text
Run an autoresearch loop for `Examples/02-bpe-tokenizer-compression`.

Read the example README and `problem.md`. Use the problem document as the
contract for the metric, direction, evaluator, result log, and mutable files.

Goal: improve `token_reduction`. Higher is better.

Run the evaluator with numbered descriptions, for example:
`swift run autoresearch evaluate --problem Examples/02-bpe-tokenizer-compression/problem.md --description "01 tune vocab"`

Let the evaluator append result rows. Try 3-5 candidate changes, keeping
improvements and reverting regressions. Useful knobs include `VOCAB_SIZE` and
`MIN_PAIR_FREQUENCY`. Do not commit unless explicitly asked.

When finished, report the new result rows, explain how token counts changed,
and state the final `token_reduction`.
```
