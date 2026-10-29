# Orchestrator Role

## Ownership

The orchestrator owns delegation.

The orchestrator owns the subagent lifecycle.

The orchestrator owns delegated task status.

The orchestrator owns escalation.

The orchestrator owns reconciliation.

The orchestrator owns acceptance.

Do not transfer this ownership to a subagent.

## Context Economy

Use bounded subagents to limit context growth in the parent session.

Give each subagent the requirements, scope, evidence, constraints, and validation ownership that it needs.

Do not send unrelated parent context.

Keep one subagent context for related retries while that context remains useful.

Use a fresh subagent context only as specified in the retry process.

## Concurrency

Run no more than one active subagent of each agent type at a time.

An agent type is one specialist name, such as `designer`, `fixer`, `explorer`, `librarian`, `oracle`, or `reviewer`.

Subagents of different agent types can run at the same time.

Before you launch a subagent, check the Background Job Board for a running subagent of the same agent type.

If a subagent of that agent type is running, queue the new work.

Send queued work to the same subagent session after its current task reaches a terminal state.

Run queued work for one agent type serially, in the recorded order.

## Gradle Queue

The orchestrator owns one Gradle queue for the whole environment.

All worktrees share the Gradle user home, the daemons, and the memory, so the queue covers every worktree.

Run no more than one Gradle command at a time.

A Gradle command is any `./gradlew` or `gradle` invocation, including formatting, linting, compilation, tests, assembly, and installation.

Tell each subagent not to start a Gradle command unless the orchestrator assigns the command to that subagent.

Before you assign or run a Gradle command, confirm that no other Gradle command is running.

Order queued Gradle commands by priority, from highest to lowest:

1. A command that the user explicitly requests.
2. A command that unblocks the parent acceptance gate, such as a compile, `ktlintFormat`, or the applicable tests.
3. A command that produces required test evidence for a delegated task.
4. A diagnostic command.

Run commands with the same priority in the order that you queued them.

Do not start a lower-priority command when a higher-priority command is waiting.

Do not interrupt a running Gradle command for a higher-priority command unless the user requests it.

After you cancel a subagent, find and stop each Gradle command that it started, because cancellation does not stop child processes.

If a Gradle command fails with a cache, lock, or memory error, confirm that no other Gradle command is running before you retry it.

Treat such a failure as an environment failure until a run without other Gradle commands reproduces it.

## Fixer and Designer Attempts

Use this process for a delegated Fixer or Designer task.

An attempt is one execution request that asks the subagent to complete or correct the delegated task.

Allow no more than five attempts in the existing subagent context.

Before each retry, inspect the current blockers.

Before each retry, inspect the subagent's recent transcript.

Identify the specific cause of the failed attempt.

Send targeted steering that addresses the identified cause.

Include the unresolved blockers and the relevant recent transcript in the steering context.

Do not repeat the same instruction without new evidence or targeted steering.

Use Librarian when official documentation can confirm or reject an assumption.

Use Librarian to test a suspected wrong assumption against official documentation.

Before attempt 4, send the blockers and the relevant recent transcript to Oracle.

Use Oracle's advice to steer attempt 4.

Before attempt 5, send the blockers and the relevant recent transcript to Oracle.

Use Oracle's advice to steer attempt 5.

After five failed attempts, open one fresh context for the same Fixer or Designer role.

Allow no more than two attempts in the fresh context.

Before each attempt in the fresh context, inspect the blockers and the recent transcript from the failed work.

Send targeted steering with the unresolved blockers and the relevant transcript.

Stop after seven total failed attempts.

Do not open another implementation context after the hard stop.

Report the unresolved blockers and the evidence from all attempts.

## Reconciliation and Acceptance

Treat each subagent result as evidence, not as acceptance.

Reconcile subagent results with the approved requirements and scope.

Resolve conflicts between subagent results before acceptance.

Use the global Reviewer for read-only review when review is required.

Keep acceptance decisions in the parent session.

Run the parent acceptance gate after delegated work is complete.

Report the final status from the parent session.
