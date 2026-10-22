---
name: showcase
description: Capture a screenshot or record a showcase journey from the approved conversation, with text-only verification and opaque media artifacts.
---

# Showcase

Create the requested artifact from the approved journey. Use the same workflow for any project or technology.

## Absolute media boundary

Treat every non-text binary as opaque while this skill is active. This boundary has no exception, even if a later user request asks for media inspection. Stop the conflicting action and explain the boundary.

Save or copy raw artifacts only through opaque transport. Never read, open, render, decode, sample, base64-encode, hash, or upload media. Never use OCR, vision, `ffprobe`, frame extraction, or a file-panel open. Never return images or buffers in tool output. A capture API can produce a buffer internally; discard its return value without assigning, inspecting, or logging it.

Inspect only text: semantic JSON, DOM, accessibility information, backend state, and text logs. Check artifact existence, nonzero size, paths, timestamps, and other filesystem metadata only. Metadata cannot prove image content or recording quality. Never claim pixel verification or verified motion from text evidence.

## Establish the approved journey

1. Read the recent conversation and the relevant change history. Use the latest user instruction when it replaces an older instruction.
2. Write the exact initial state, actions, inputs, expected results, and business completion conditions. Connect the changed behavior to the requested showcase. A business completion condition is a positive observable result, such as a saved item with the expected identifier.
3. Preserve existing requirements. Do not reset data, authentication, defaults, or platform settings. Keep reduced-motion settings unchanged. Do not replace automatic showcase behavior with manual scrolling.
4. Ask one focused question if critical ambiguity prevents the correct journey. Obtain approval for any missing launch, install, capture, or state-changing action before execution.
5. Select a scenario-specific, explicit, bounded business-readiness timeout. Check that the recorder limit fits startup, actions, business readiness, and the final hold. Reserve a stop margin and assign a safety watchdog. Shorten the approved scenario or request a suitable recorder if it does not fit.

Proceed only when the approved sequence and completion conditions are explicit. Do not install dependencies to make capture possible.

## Prepare and execute

1. Use existing tools. For Android, read [the Android branch](references/android.md). For a browser, read [the web branch](references/web.md). Read only the applicable branch. For another platform, identify an existing text-observation and opaque-capture path before proceeding.
2. Install and launch the latest verified build when authorized. Preserve app data and authentication. Verify build identity from text when available. If the latest build is not verified or installation is not authorized, report that limitation before capture. Do not silently use an older build.
3. Verify the required initial state with text evidence. Stop if it does not match. Do not repair it through an unapproved reset.
4. For a recording, start the recorder before the first journey action. Confirm that recording started through process or API state. Keep one lifecycle owner responsible for stopping and finalizing it, including on failure.
5. Execute the exact approved actions. Derive selectors or coordinates from current text observations. Record each action and its input without exposing secrets.
6. Wait for the positive business completion condition within its timeout. A fixed sleep, a completed click, or the absence of a spinner alone is not completion. Report failure if business readiness does not occur before the timeout. Preserve any partial artifact with a clear label.

## Final state and capture

Start one monotonic deadline when the final business completion condition first becomes true. The entire final UI settle and hold interval must not exceed **five seconds**. Never restart or extend this deadline when state changes, bounds stabilize, or an animation starts. Keep the business-readiness timeout separate from this deadline.

Observe relevant finite entry and exit animations, including an exiting overlay. Exclude infinite decorative loops. Never wait for an infinite animation to end. Keep confirming the business state. Two matching semantic bounds snapshots can support stability; they do not prove pixel stability.

When finite animations have ended and the business state remains confirmed, allow one captured-frame or render opportunity before finalizing the recording. Include this opportunity inside the same five-second deadline. Do not stop immediately after a click or the first semantic appearance. Do not add a fixed three-second hold.

For a screenshot, capture after the target is ready and the bounded settle check completes. For a recording, include the final UI before stopping. If a finite animation exceeds the deadline, or its end cannot be verified, capture the best available state within the bound. Mark it as best effort. State that the final frame is not verified. If business state becomes invalid, report the failure instead of claiming success. Do not wait beyond the deadline to regain readiness.

Finalization and opaque transfer occur after the hold. Use a separate bounded finalization timeout. Do not count finalization as a longer UI hold or use it as a reason to keep recording indefinitely.

## Artifacts and evidence

Default to a unique, safe output name under the current working directory, such as `showcase-<UTC-time>-<unique-suffix>/`. Use exclusive creation or an existence check that prevents overwriting. Use platform-appropriate screenshot and recording extensions. Do not hardcode a workspace, organization, app, or journey input.

Keep original artifacts. Do not overwrite or delete local or device artifacts. Cleanup requires explicit approval for the exact named paths. On failure, keep available artifacts and label them partial or best effort.

Keep temporary text evidence outside tracked project files. Record:

- The initial state and its text evidence.
- The exact actions and non-secret inputs.
- The expected and actual business completion conditions.
- The business timeout and observed readiness time.
- The final settle and hold elapsed time, which must be at most five seconds.
- The finite-animation evidence and any unverified condition.
- The artifact path, byte size, and latest build identifier when known.
- Each limitation, including that binaries remained opaque.

Report the artifact paths and limitations in text. Do not open the artifacts for the user through a tool.

## Reusable user prompts

### Screenshot

> Use Showcase to capture a screenshot of <target> in <project/platform>. Use the approved conversation and changes through <history boundary>. Start from <initial state>. Execute <exact actions and inputs>. Confirm <positive business condition> within <business timeout>. Use the latest verified build if <install/launch authorization>. Preserve data, authentication, defaults, and platform settings. Save to <optional output directory>. Keep all media opaque. Report text evidence and limitations.

### Recording

> Use Showcase to record <journey> in <project/platform>. Use the approved conversation and changes through <history boundary>. Start from <initial state>. Execute <exact actions and inputs>. Confirm <positive business condition> within <business timeout>. Use the latest verified build if <install/launch authorization>. Start recording before the first action. Include the final UI with a single settle and hold deadline of at most five seconds. Preserve data, authentication, defaults, and platform settings. Save to <optional output directory>. Keep all media opaque. Report text evidence and limitations.
