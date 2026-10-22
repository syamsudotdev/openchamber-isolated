---
name: brow
description: Deepen a user prompt without expanding its scope. Use when the user
  asks for a deeper task, professional methods, primary evidence, or independent
  validation before a prompt rewrite.
---

# Deepen the prompt

Use the supplied prompt or the task clearly identified in the conversation. If neither is available, ask the user to provide the prompt.

Before rewriting, give four concise, task-specific assessments:

1. **Professional practice:** State what a top professional in the field would do here that the prompt does not request.
2. **Raw material:** Name the least-processed source material that professional would start from instead of summaries or other interpreted material. State when access to it is unknown.
3. **Methods and tools:** Name the specific methods and tools that professional would use. Explain what each contributes to this task.
4. **Independent validation:** State what evidence, external standard, reproducible test, or observable result would show correctness independently of the assistant's or user's opinion. For subjective work, identify observable evaluation criteria and their limits.

Then provide a self-contained **Rewritten prompt** that asks for exactly these improvements. Preserve the original objective, deliverable, constraints, and scope. Increase depth through better source material, methods, and validation, rather than additional tasks or deliverables. Keep unavailable inputs conditional, and distinguish assumptions from verified facts.

Stop after the rewrite. Execute the rewritten task only if the user separately requests execution.