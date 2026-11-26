---
name: rtk
description: How RTK condenses shell command output, and when to re-run a command with `rtk bypass`. Use before you run or troubleshoot a direct `rtk` command, or when command output looks empty, garbled, or contradicts its exit code.
---

<!-- Body is the RTK.md that `rtk init -g` generates in RTK OSS 1.0.0. -->

# Command output

Command output here is condensed to save tokens, keeping every signal and
dropping costly noise. Treat it as the complete result: run commands
normally, and batch related commands into one call to avoid extra turns.
Truncated results state their recovery path in their own output. Re-run a
command as `rtk bypass <cmd>` only when its result is unusable: empty when
output was clearly expected, contradicting its exit code, or garbled.
