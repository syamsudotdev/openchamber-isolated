# Journey brief template

Readers: product, design and QA. Write what users see and do. Do not write file paths, class names, function names or code. Replace each `<...>` placeholder. Keep the section order.

```markdown
# User journey brief: <feature name>

Status: <design and build state>. <Decision state, for example "All decisions are closed. The assumptions in section 9 are not yet confirmed.">. <When an engineering brief exists: "This brief is the user-journey version of the engineering brief. It has no platform implementation details.">

## Bottom line

- <3 to 7 bullets. Who sees what change, and what triggers it.>
- <Name each intended behavior that a reader can mistake for a defect.>

## 1. Who is affected

| User type | What changes |
|---|---|
| <user type> | <visible change, or "nothing changes"> |

<One sentence about what stays the same for the affected users.>

## 2. Where users meet it

<Number of entry points, and how many get the change.>

| # | Entry point | <state at start that differs between entry points> |
|---|---|---|
| 1 | <screen path, in the words of the app> | <value> |

## 3. UI component: <component name>

<Where the component is on the screen.>

| State | Who sees it | Look | Tap result | <content that changes> | <feedback, for example a tooltip> |
|---|---|---|---|---|---|
| <state> | <user type or condition> | <look, or "design needed"> | <result> | <content> | <feedback> |

**<Feedback> rules:**
- <When it shows.>
- <When it does not show again.>
- <What happens when the data changes while it is visible.>
- <What happens when the data is missing.>

## 4. User journeys

### J1. <user type> <goal>
1. <One action or one observable result for each step.>

<Write one journey for each user type and each trigger: first use, purchase or unlock, return to the screen, network error, other screens that show the same data.>

## 5. Edge states

| State | What the user sees |
|---|---|
| <older server, missing data, long text, large font, screen open for a long time, first request fails> | <result> |

## 6. Known trade-offs and how to mitigate them

| # | Trade-off | User impact | Mitigation | Owner |
|---|---|---|---|---|
| 1 | <trade-off, or "Defect today: ..."> | <what the user sees> | <action, check or accepted decision> | <team> |

## 7. Decision: <topic>

<The decision in plain words. Add one section for each decision that the user discussed, corrected or can read in two ways.>

## 8. Needs design and product input

1. <Item, with the assumption used until the input arrives.>

## 9. Assumptions

1. <A sentence that someone can confirm or reject.>

## 10. Out of scope

- <Item, with the reason when it was retracted or postponed.>
```
