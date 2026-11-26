# Engineering brief template

Readers: engineers. Each code fact has `file:line`. Replace each `<...>` placeholder. Keep the section order.

````markdown
# Engineering brief: <feature name>

Status: <implementation state>. <Decision state, for example "All decisions are closed. The working assumptions in section 1 are not yet confirmed.">. Source: <code reading on branch `<branch>`, documents, payloads>. <Tests or device runs done, or "No tests or device runs were done for this brief.">

## Bottom line

- <3 to 7 bullets: the contract change, the behavior change, the trigger, the highest risk with `file:line`.>
- <State whether the Quint rule applies, with a one-sentence reason.>

## 1. Decisions

| # | Decision |
|---|---|
| <topic> | <decision, with the data source and the default> |

**Working assumptions (not decided; confirm before you write code):**
1. <Assumption, and who confirms it.>

## 2. Payload

<Endpoint and the new or changed fields.>

```json
<payload snippet>
```

<Nullability rule from the repository, with its source.>

| Payload | Domain value |
|---|---|
| <field missing or `null`> | <default> |

## 3. Current code (facts)

| Area | Location | Fact |
|---|---|---|
| <area> | `<path>:<lines>` | <what the code does today> |

## 4. Impact radius

**<All callers or hosts of the shared code>:**

| # | Caller | Call site | <attribute that differs> |
|---|---|---|---|
| 1 | <caller> | `<file>:<line>` | <value> |

**<Trigger that happens more often than expected>:** <every path that triggers it, and the rule that each path must keep>.

**Not impacted:** <areas, with the reason for each area that reads the same data>.

**Impacted for all users:** <side effects outside the target users, or "None">.

## 5. Required changes

1. **<Change name>.** <What to change, where, and why. A state table when the change derives a state.>

<Add a backend or other-team change as a separate sentence after the list.>

## 6. State model (Quint)

<Only when the Quint rule applies. Specification path, the plan to run each invariant with a seed, and this table.>

| Invariant | Rule |
|---|---|
| `<name>` | <rule> |

## 7. Verification

**Unit tests:** <harness, fakes, fixtures>. Write expected values from this brief, not from test output. For each new test, record a failure against a temporary fault, then a pass after you restore the code.

| Test | Fault it must find |
|---|---|
| <input and expected result> | <plausible wrong implementation> |

**Project checks:** <commands from the repository guidance>.

**Manual QA:** <where the QA cases are, P0 cases, existing end-to-end flows, missing flows>.

## 8. Known trade-offs and mitigations

| # | Trade-off or risk | Mitigation | Owner |
|---|---|---|---|
| 1 | **<Label>:** <trade-off, risk or "Defect today: ..."> | <change number, test or accepted decision> | <team> |

## 9. Out of scope

- <Item, with the reason.>

## 10. Estimate (assumption, not measured)

| Work | Estimate |
|---|---|
| <work item> | approximately <value> |

## 11. Decision record: <topic>

<The earlier instruction or reading, the correction, and the final decision.>
````
