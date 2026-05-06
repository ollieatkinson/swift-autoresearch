# Example Agent Prompt

Paste this into Codex, Claude Code, or another coding agent from the repository
root.

```text
Run an autoresearch loop for `Examples/05-uk-crime-holdout`.

Read the example README and `problem.md`. Use the problem document as the
contract for the metric, direction, evaluator, result log, and mutable files.

Goal: find an operationally useful crime-pattern claim that survives the March
holdout. Improve `score`, but do not chase a higher score if the selected claim
is less useful for analyst triage.

Run the evaluator with numbered descriptions, for example:
`swift run autoresearch evaluate --problem Examples/05-uk-crime-holdout/problem.md --description "01 tune claim strategy"`

Let the evaluator append result rows. Try 4-7 candidate changes, keeping
improvements and reverting regressions. Prefer local-vs-pooled-baseline claims
over weakest named-town comparisons. Do not commit unless explicitly asked.

When finished, report the new result rows, explain which claims were useful or
misleading, and state the final `score`, `claim`, `holdout_lift`, and
`candidate_random_percentile`.
```
