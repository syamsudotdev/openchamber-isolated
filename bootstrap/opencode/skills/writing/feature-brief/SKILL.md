---
name: feature-brief
description: "Write a decision brief for a human handoff: a non-technical journey brief for product, design and QA, an engineering brief for engineers, or both. Use when the user asks for a brief, a handoff to engineers or design, or a non-technical summary of a feature decision."
---

# Feature brief

A brief is a Markdown file that a person reads to act on a feature decision. It is not a chat summary and not a handoff to another agent.

There are two audiences:

- **Journey brief:** product, design and QA. It describes what users see and do. Template: [`JOURNEY.md`](JOURNEY.md).
- **Engineering brief:** engineers. It describes the contract, the code facts, the changes and the proof. Template: [`ENGINEERING.md`](ENGINEERING.md).

When both briefs exist, they describe the same decisions at two depths. The journey brief is the engineering brief without platform details.

## Steps

### 1. Collect the content

Put each item in exactly one group:

| Group | Requirement |
|---|---|
| Decision | Quote or cite the user statement that makes it. |
| Fact | Give its evidence: `file:line`, a payload, a command result or a document. |
| Assumption | State it as a sentence that someone can confirm or reject, and name who confirms it. |
| Unknown | Write `Unknown`, and name who can supply it. |

A user answer confirms only what it answers. When a short answer such as "yes" can close more than one point, record the narrow meaning as the decision and the wider meaning as an assumption.

**Complete when:** each decision has a source, each fact has evidence, and each other item is an assumption or `Unknown`.

### 2. Select the audience

Write the brief that the user asks for. When the user asks for a handoff to more than one group, write both.

**Complete when:** each brief to write has a named reader.

### 3. Write each brief

Read the template for each brief, and fill in each section. Remove a section that has no content, except Bottom line, Assumptions and Out of scope. Write "None" in those three sections when they are empty.

**Complete when:** each kept section has content that comes from step 1.

### 4. Check the briefs

Read each file in full. Do the checks below. Fix each failure, then read the changed sections again.

- **Status line:** it agrees with the Assumptions section. A brief with open assumptions does not say only "all decisions are closed".
- **Same facts in both briefs:** the decisions, counts, names, entry points, assumptions and out-of-scope items agree.
- **Same flow in both briefs:** each journey step is possible with the engineering changes. Example: a journey step that shows data after an unlock needs a change that loads that data again.
- **One term for each meaning:** each term has the same meaning in the whole file and in both files. Use plain names, for example "Bottom line", not "BLUF". Replace a vague word with the name of the thing, for example "server-side permission", not "access".
- **Trade-off rows:** each row has a mitigation and an owner. Each defect that users can see is also in the journey brief.
- **Journey brief:** it has no file paths, class names, function names or code.
- **Engineering brief:** each code fact has `file:line`. Each test names the fault that it must find. Each estimate is marked as an assumption.
- **Decision record:** a decision that the user corrected has an entry that gives the earlier reading and the correction.

**Complete when:** all checks pass for each file.

### 5. Report

In the reply, give:

1. The full path of each brief.
2. What changed, in 3 to 5 lines for each file.
3. The open assumptions and their owners.
4. One next action, for example "Ask backend to confirm the key name, then send the briefs."

Say that an edit is done only after you read the edited lines.

**Complete when:** the reader can send each brief without opening the chat.

## Rules for both briefs

- Write in ASD-STE100 Simplified Technical English. Use short, active sentences.
- Put the Bottom line first. It has 3 to 7 bullets. Each bullet is one fact or one decision.
- Use tables for comparisons, states and lists that have more than one attribute. Use numbered steps for journeys and changes.
- Write `Unknown` for a value that you cannot verify. Write "approximately" for an estimate.
- Use bold text only for the word that changes the meaning of a row or a sentence.
- Save each brief in the scratchpad directory. Save it in the repository only when the user names a path. Name the files `<feature>-user-journey-brief.md` and `<feature>-engineering-brief.md`.
- Keep a brief as the single source of truth for its audience. When a decision changes, update both briefs in the same turn.
