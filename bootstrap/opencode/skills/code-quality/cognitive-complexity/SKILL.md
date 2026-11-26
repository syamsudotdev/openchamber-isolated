---
name: cognitive-complexity
description: Measure and reduce per-function Cognitive Complexity with the project's Sonar S3776 configuration and analyzer while preserving behavior, cohesion, and readable control flow. Use when Sonar reports S3776, a function exceeds its Cognitive Complexity threshold, or the user asks to assess or refactor deeply nested control flow without substituting cyclomatic complexity.
---

# Cognitive Complexity

Purpose: Measure how difficult control flow is to understand. Reduce that burden without gaming the metric or damaging cohesion.

## Inspect S3776 first

1. Find the active Sonar rule `S3776` for the target language.
2. Read its configured threshold from the project quality profile, analyzer configuration, or lint configuration.
3. Identify suppressions and scope overrides that affect the target function.
4. Treat project configuration as authoritative.

## Use the correct analyzer

Prefer the project's Sonar analyzer. Otherwise, use SonarQube for IDE or a configured `eslint-plugin-sonarjs` rule.

Never substitute cyclomatic-complexity tools or rules. They measure a different property and produce incompatible scores.

If no applicable analyzer is available, calculate a manual estimate. Label every manual score as an estimate.

## Understand the score

Start each function at 0. Add structural increments for:

- `if`, `else if`, and `else` branches.
- Ternary expressions.
- A `switch` once, not once per `case`.
- Loops.
- `catch` clauses.
- Sequences of binary logical operators, according to Sonar's sequence rules.
- Labeled or multi-level jumps.
- Recursion.

Apply nesting penalties according to the applicable Sonar language rules. Deeper flow-breaking structures cost more.

Do not increment for normal function calls, normal returns, `try`, `finally`, optional chaining, or null-coalescing operations. Language-specific compensations and exceptions belong to the analyzer. Do not recreate them from memory when an analyzer is available.

## Apply thresholds per function

Use the configured project threshold. If the project has no override, use these Sonar defaults:

- 15 for most languages.
- 25 for C, C++, and Objective-C.

Treat the threshold as a per-function review trigger. Do not average scores across a file or module.

## Refactor tactics

Apply these tactics in order:

1. Add guard clauses to remove nesting.
2. Extract a coherent responsibility into a well-named helper.
3. Use a `switch` or lookup only when one discriminator makes it valid and clearer.
4. Replace complex inline conditions with named predicates.
5. Flatten loops with early `continue`, early exit, or coherent extraction.
6. Introduce polymorphism only when the same dispatch repeats in multiple places.

Stop when the function is below its threshold. Also stop when further extraction harms cohesion or makes control flow harder to follow.

## Do not game the metric

- Preserve behavior and public contracts.
- Do not hide branches in dense expressions, callbacks, macros, reflection, or dynamic dispatch.
- Do not split one coherent function into trivial forwarding helpers only to lower its score.
- Do not move complexity into unmeasured generated code or excluded paths.
- Do not replace explicit logic with a lookup or polymorphism unless the domain model supports it.
- Do not suppress `S3776` without a documented reason and an explicit remaining exception.

## Workflow

1. Measure touched functions with the configured analyzer.
2. Rank functions by Cognitive Complexity above the active threshold.
3. Explain the control-flow structures and nesting that create each hotspot.
4. Refactor the worst hotspot with the tactics above.
5. Re-measure with the same analyzer and configuration.
6. Run applicable tests and other behavior checks.

## Final report

End each refactor with this table:

```markdown
## Cognitive Complexity report
| Function | Before | After | Threshold | Main reduction | Tool | Extracted helpers | Behavior verification | Remaining exceptions |
|----------|--------|-------|-----------|----------------|------|-------------------|-----------------------|----------------------|
| parseOrder | 24 | 12 | 15 | Removed nested conditionals with guards | Sonar analyzer | validateHeader, resolveDiscount | Unit tests passed | None |
```

Mark estimated scores in the `Tool` column. Keep explanations concise.
