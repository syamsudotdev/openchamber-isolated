---
name: verification-planning
description: Verification planning for non-trivial coding work. Use before implementing a feature, bug fix, refactor, cross-system change, or high-confidence behavior change that needs a credible project-specific evidence path.
---

# Verification Planning

## Build an evidence path

Before changing a non-trivial system, build an **evidence path**: a
project-specific route from the claim being made to evidence that can establish,
limit, or refute it.

The purpose is not to select a familiar technique. The purpose is to decide how
this system can reveal the truth of this particular change.

## 1. Frame the claim

State the behavior that needs to become true and the conditions that could make
a confident conclusion wrong.

Consider what must change, what must remain true, where the behavior crosses a
boundary, and which failure would matter most.

**Complete when:** the claim, its meaningful uncertainty, and its important
failure modes are concrete enough to investigate.

## 2. Design the evidence path

Derive possible evidence paths from the system itself: its controllable inputs,
observable effects, state transitions, invariants, boundaries, artifacts, and
ability to repeat or reverse a scenario.

Generate alternatives before choosing. Prefer the path that produces a
trustworthy conclusion with proportionate cost, safety, and effort.

**Complete when:** there is a preferred path, its limitations are understood,
and a weaker or stronger alternative is available if circumstances change.

## Set a verification budget

Before execution, record: claims → owner → narrow evidence and boundaries →
expected command count and measured time (or `Unknown`) → repeat conditions.
Identify real production components separately from fakes and fixtures. For each
test, use an independent expected result and name a plausible fault it must detect.

For each new or changed test, record a relevant failed assertion against the
natural defect or a representative temporary fault, then a pass after restoration.
Batch compatible faults and use one shared restored passing run when possible.
Every claimed test's relevant assertion must execute, fail, and then pass.
A fault that masks another fault invalidates that batch's evidence for the masked
case. Compiler and test-harness errors do not establish defect detection.

Before temporary mutations, preserve the exact source state and arrange guarded
restoration, including interruption cleanup. Verify restoration before final checks.
Serialize mutations against other source readers and runners. Parallel review
must not inspect partially mutated source. Exhaustive mutation campaigns require
an explicit budget; they are not the default.

Run targeted child tests only when needed. After reconciliation, the parent owns
one final gate. Required repository and release checks still apply. Reuse results
only while relevant code, inputs, environment, and state remain valid. Rerun
invalidated checks; do not force an unconditional full-suite rerun.

Record actual commands, raw outcomes, failures, and limits. Put source evidence
at a path accessible to its intended consumer. During long batches, report
completed commands, active commands, and remaining work from measured status,
not guessed progress. After interruption, inspect the existing command's status
and result before launching a duplicate.

## 3. Create a verification affordance when needed

When the existing system leaves the decisive truth too indirect or ambiguous,
extend the evidence path with a **verification affordance**: the smallest
capability that makes the relevant state controllable, observable, repeatable,
and diagnosable for an agent.

Ask what capability would let an agent establish the claim directly, repeat the
scenario from a known state, and explain a failure without inference. Prefer an
affordance that strengthens directness, determinism, agent-legibility,
isolation, resetability, or future reuse.

Treat the affordance as part of the evidence path, not an automatic product
feature. Decide deliberately whether it is temporary or durable before building
it.

**Complete when:** the chosen path can establish the claim directly enough for
its stakes, and any needed affordance has a defined lifecycle.

## 4. Research when the path is unknown

When the right evidence path depends on an unfamiliar dependency, framework,
external service, or rapidly changing capability, ask `@librarian` for focused
research before committing to an approach.

Ask for official or project-specific facilities, constraints, and trade-offs
that affect this exact verification problem. Use existing project evidence
directly when it already resolves the choice.

**Complete when:** the chosen path rests on known capabilities and real
constraints rather than assumption.

## 5. Make the path runnable

Prepare only the support needed to follow the evidence path reliably. Keep the
support narrow, repeatable, and safe to inspect.

Decide whether that support has recurring value or exists only to resolve the
current uncertainty. Retain durable value deliberately; remove temporary
support once it has served its purpose.

Ask before introducing dependencies, persistent diagnostic surfaces, or
structural changes whose sole purpose is evidence gathering.

**Complete when:** the path can be followed without guessing about setup,
state, or interpretation.

## 6. Close the evidence path

After implementation, follow the planned path and interpret the resulting
evidence against the original claim.

Report whether the claim was established, limited, or refuted; distinguish
known facts from remaining uncertainty.

**Complete when:** a future reader can see what supports the conclusion and
what remains outside its reach.

## Scope

Use this skill proportionately. Small mechanical changes can follow ordinary
project checks directly. For larger multi-phase work, let this skill establish
the evidence path that later work follows.

## Instruction self-test

- Two compatible faults reach both tests' relevant assertions: record both failures,
  restore exact source, then record both passes in one shared run.
- One fault prevents another assertion from running: reject the masked case's evidence.
- A temporary fault causes a compiler error: repair the experiment; this is not proof.
- Code, inputs, environment, and state remain unchanged: reuse the valid result.
- A baseline or input changes: rerun affected checks, not automatically the full suite.
