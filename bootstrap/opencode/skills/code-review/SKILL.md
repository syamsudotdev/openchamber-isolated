---
name: code-review
description: "Review the changes since a fixed point (commit, branch, tag, or merge-base) along two axes: Standards (does the code follow this repo's documented coding standards?) and Spec (does the code match what the originating issue/spec asked for?). Runs both reviews in parallel sub-agents and reports them side by side. Use when the user wants to review a branch, a PR, work-in-progress changes, or asks to \"review since X\"."
---

Two-axis review of the diff between `HEAD` and a fixed point the user supplies:

- **Standards**: does the code conform to this repo's documented coding standards?
- **Spec**: does the code faithfully implement the originating issue / spec?

Both axes run as **parallel sub-agents** so they don't pollute each other's context, then this skill aggregates their findings.

Keep the review read-only. Findings and proposed specifications do not authorize
implementation. Follow-ups remain review work until the user authorizes writing.
Do not execute tests or apply temporary faults implicitly during review.

The issue tracker should have been provided to you. If `docs/agents/issue-tracker.md` is missing, tell the user to run `/setup-matt-pocock-skills`.

## Process

### 1. Pin the fixed point

Whatever the user said is the fixed point (a commit SHA, branch name, tag, `main`, `HEAD~5`, etc.). If they didn't specify one, ask for it.

Capture the diff command once: `git diff <fixed-point>...HEAD` (three-dot, so the comparison is against the merge-base). Also note the list of commits via `git log <fixed-point>..HEAD --oneline`.

Before going further, confirm the fixed point resolves (`git rev-parse <fixed-point>`) and the diff is non-empty. A bad ref or empty diff should fail here, not inside two parallel sub-agents.

### 2. Identify the spec source

Look for the originating spec, in this order:

1. Issue references in the commit messages (`#123`, `Closes #45`, GitLab `!67`, etc.), fetched via the workflow in `docs/agents/issue-tracker.md`.
2. A path the user passed as an argument.
3. A spec file under `docs/`, `specs/`, or `.scratch/` matching the branch name or feature.
4. If nothing is found, ask the user where the spec is. If they say there isn't one, the **Spec** sub-agent will skip and report "no spec available".

Record the spec source and version with the latest approved amendments. Mark
superseded clauses. Distinguish approved requirement changes from defects that
missed the original requirement. Report unresolved material conflicts instead of
choosing a requirement without evidence.

### 3. Identify the standards sources

Anything in the repo that documents how code should be written, such as `CODING_STANDARDS.md` or `CONTRIBUTING.md`.

On top of whatever the repo documents, the Standards axis always carries the **smell baseline** below: a fixed set of Fowler code smells (_Refactoring_, ch.3) that applies even when a repo documents nothing. Two rules bind it:

- **The repo overrides.** A documented repo standard always wins; where it endorses something the baseline would flag, suppress the smell.
- **Always a judgement call.** Each smell is a labelled heuristic ("possible Feature Envy"), never a hard violation. Exclude a check only when inspected tooling configuration confirms that tooling enforces that exact case. Review cases the tooling misses, including qualified identifiers that imports can replace.

Each smell reads *what it is* → *how to fix*; match it against the diff:

- **Mysterious Name**: a function, variable, or type whose name doesn't reveal what it does or holds. → rename it; if no honest name comes, the design's murky.
- **Duplicated Code**: the same logic shape appears in more than one hunk or file in the change. → extract the shared shape, call it from both.
- **Feature Envy**: a method that reaches into another object's data more than its own. → move the method onto the data it envies.
- **Data Clumps**: the same few fields or params keep travelling together (a type wanting to be born). → bundle them into one type, pass that.
- **Primitive Obsession**: a primitive or string standing in for a domain concept that deserves its own type. → give the concept its own small type.
- **Repeated Switches**: the same `switch`/`if`-cascade on the same type recurs across the change. → replace with polymorphism, or one map both sites share.
- **Shotgun Surgery**: one logical change forces scattered edits across many files in the diff. → gather what changes together into one module.
- **Divergent Change**: one file or module is edited for several unrelated reasons. → split so each module changes for one reason.
- **Speculative Generality**: abstraction, parameters, or hooks added for needs the spec doesn't have. → delete it; inline back until a real need shows.
- **Message Chains**: long `a.b().c().d()` navigation the caller shouldn't depend on. → hide the walk behind one method on the first object.
- **Middle Man**: a class or function that mostly just delegates onward. → cut it, call the real target direct.
- **Refused Bequest**: a subclass or implementer that ignores or overrides most of what it inherits. → drop the inheritance, use composition.

#### Mandatory Standards checks

Run all five checks even when no spec is available. Read unchanged callers and owners when needed to establish the mechanism. For each check, report `checked`, `not applicable`, or `not verified`, with a concise evidence path (`file:symbol`) and reason. Keep this coverage separate from findings. Use `not verified` for missing evidence, not `not applicable`.

1. **Ownership boundaries**: inspect child ancestor lookup, dependencies on concrete hosts, and child manipulation of parent layout or scrolling. Establish the intended owner and identify introduced coupling or bypassed owner contracts.
2. **Shared API growth**: distinguish feature-local behavior from shared requirements. Inspect new shared-component parameters, especially action-sheet styling. Require evidence of a real shared need in callers or documented contracts. Prefer the smallest feature-local remedy for one-feature needs; a content-slot redesign is not an automatic remedy.
3. **Cross-feature effects**: trace actual affected callers and configuration handoffs. Establish the changed contract and consequence for another feature. Coordinated row or registry edits alone are not evidence of Shotgun Surgery or a cross-feature defect.
4. **Import usage**: inspect qualified Kotlin and Java identifiers that imports can replace against repo rules. Confirm exact tooling coverage before excluding a case; do not silently omit import cases that tooling misses.
5. **Lifecycle retention**: inspect changed UI, listener, decorator, adapter, and composition registrations. Trace a long-lived root → strong references → destroyed view or callback, including unchanged owners. Check precise teardown order for observers, queued posts, layout listeners, holder pools, and restoration. Verify whether disposal actually breaks each relevant chain. Distinguish collectible cycles, temporary retention, a proven source-level retention root, and a runtime-confirmed leak. A source trace is not heap verification; state runtime evidence as unavailable unless actually obtained.

Report only defects introduced or worsened against the pinned baseline. Each finding must identify its diff-hunk origin, mechanism, consequence, and minimal remedy. Compare baseline behavior when the origin is uncertain. Label heuristics as judgement calls and cite applicable repo rules for hard violations. Put pre-existing unchanged concerns in optional context, outside branch findings and counts. If evidence is insufficient, record a limitation rather than invent a defect.

#### Test-boundary evidence

For meaningful changed tests or coverage claims, list the claimed behavior, actual
production connection exercised, replaced dependencies, independent expected-result
source, and a plausible bug that could still pass. Apply this check in Spec, or in
Standards when no spec is available. A disconnected helper, callback spy, or manual
injection does not prove UI → ViewModel → repository → HTTP/cache wiring. Match the
required boundary to the claim; a full real stack is not required for every test.
Static review is not runtime proof. State execution-evidence status and source.
Keep unchanged pre-existing test gaps outside branch findings.

### 4. Spawn both sub-agents in parallel

Give both sub-agents the read-only scope rule above.

**Standards sub-agent prompt** MUST include:

- The full diff command and commit list.
- The list of standards-source files you found in step 3, **plus the smell baseline from step 3** pasted in full (the sub-agent has no other access to it).
- The complete **Mandatory Standards checks** section, including its coverage and baseline-attribution rules, pasted alongside the baseline. If pasting is not possible, provide the exact readable path `/home/node/.config/opencode/skills/code-review/SKILL.md` with an explicit instruction to read that section before reviewing. A section name alone is insufficient.
- When no spec is available, include the **Test-boundary evidence** check from this file and request its coverage separately from findings.
- The brief: "Report, per file/hunk where relevant, (a) introduced or worsened violations of documented standards: cite the standard (file + rule); and (b) introduced or worsened baseline smells: name the smell and quote the hunk. Apply the Mandatory Standards checks. Documented repo standards override baseline heuristics. Limit findings to 400 words. Return compact coverage for all five checks and limitations outside that word limit. Keep optional pre-existing context separate from branch findings and counts."

**Spec sub-agent prompt** should include:

- The diff command and commit list.
- The spec's readable path or fetched contents, source, version, latest approved amendments, and superseded clauses. Report unresolved material conflicts rather than guessing.
- The **Test-boundary evidence** check from this file, pasted or supplied through an exact readable path with an instruction to read it. Return its coverage and execution-evidence limits separately from findings.
- The brief: "Report introduced or worsened defects against the pinned baseline: (a) requirements the spec asked for that are missing or partial; (b) behaviour in the diff that wasn't asked for (scope creep); (c) requirements that look implemented but where the implementation looks wrong. Quote the spec line and identify the diff-hunk origin, mechanism, consequence, and minimal remedy for each finding. Keep unchanged pre-existing concerns separate from branch findings and counts. Under 400 words."

If the spec is missing, skip the Spec sub-agent and note this in the final report.

### 5. Aggregate

Present the two reports under `## Standards` and `## Spec` headings, verbatim or lightly cleaned. Do **not** merge or rerank findings, because the two axes are deliberately separate (see _Why two axes_).

Under Standards, preserve the five-check coverage report and limitations separately from findings. If coverage is missing, request it from the same Standards sub-agent before concluding. Keep optional pre-existing context outside finding counts. State relevant unverified lifecycle checks as an unresolved limitation; do not give blanket acceptance when these checks remain unverified. Keep missing-spec status explicit without suppressing Standards checks.

Preserve test-boundary coverage under its assigned axis, including execution-evidence
status and source. Request missing coverage from the same reviewer. Report material
spec conflicts and approved amendments without counting superseded clauses as defects.

End with a one-line summary: total findings per axis, and the worst issue _within each axis_ (if any). Don't pick a single winner across axes: that's the reranking the separation exists to prevent.

### Instruction self-test

Check these counterexamples when validating this review process:

- An added adapter → decorator → destroyed-view chain remains strongly held by a backstack owner after `dispose`: report the introduced retention mechanism despite the disposal call. Do not claim a heap-confirmed leak.
- New shared action-sheet styling parameters serve only one feature, with no shared contract need: flag possible Speculative Generality and offer a minimal feature-local remedy.
- Unchanged toolbar-to-host coupling exists at the pinned baseline: optional context only, not a branch finding.
- A discarded view/listener cycle has no long-lived root: the cycle alone does not establish a leak.
- A callback-spy test passes without production wiring: limit its coverage claim; do not infer end-to-end coverage or execute a fault during review.
- A later approved amendment replaces an original requirement: review the amendment and mark the old clause superseded, not missed.
- A user asks to refine test cases after a read-only review: return reviewed cases, not test-file edits.

## Why two axes

A change can pass one axis and fail the other:

- Code that follows every standard but implements the wrong thing → **Standards pass, Spec fail.**
- Code that does exactly what the issue asked but breaks the project's conventions → **Spec pass, Standards fail.**

Reporting them separately stops one axis from masking the other.
