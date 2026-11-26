# Android capture branch

Apply the core Showcase contract. Read the installed `android-cli` skill and its required interaction references before using `android` commands. Use their text-only paths. If a reference requires image inspection, stop that part and retain the Showcase media boundary. Do not install tools or dependencies.

## Prepare and observe

Identify the device serial, authorized component, and latest verified APK from text evidence. Preserve app data. The following commands are illustrative. Supply approved values; do not execute placeholders.

```sh
adb -s "$SERIAL" install -r "$LATEST_APK"
adb -s "$SERIAL" shell am start -n "$COMPONENT"
android layout --device "$SERIAL" --full --output "$OUT/layout.json"
```

Use `install -r` only when installation is authorized. Do not uninstall or clear app data. Confirm the installed build identifier through package metadata when available. Read the layout JSON as text. Refresh it before each coordinate-based action. Do not reuse stale coordinates or derive coordinates from images.

For an approved Latin-text input, an illustrative command is `adb -s "$SERIAL" shell input text 'sample%sinput'`. Here `%s` represents a space. This does not provide general Unicode or IME support. Use an existing app or input harness for those inputs. Do not place secrets in command logs or clipboard contents.

## Screenshot

After the core readiness and bounded settle checks, stream the screenshot directly to a new file:

```sh
adb -s "$SERIAL" exec-out screencap -p > "$OUT/screenshot.png"
```

Prevent overwriting before running this command. Do not capture stdout into a tool result or a model-visible buffer. Validate only filesystem metadata.

## Recording lifecycle

Use one owner for the remote recorder process and the host transport process. Keep both process identifiers separately. Start before the first action. A typical recorder command is:

```sh
adb -s "$SERIAL" shell screenrecord --time-limit 180 "$REMOTE_VIDEO"
```

Run it through an existing managed background mechanism. Obtain the exact remote PID through text process state for this invocation. A host `adb` PID is not the remote recorder PID. Confirm the remote command and its unique output path before stopping it. Validate that the remote PID contains decimal digits only and is greater than zero. Never interpolate an unvalidated process listing into a shell command. Do not use broad `pkill` or `killall` commands.

Check the device's supported recorder limit before execution. The illustrated 180-second limit is a safety limit, not the business timeout or final hold. Fit the whole journey inside the supported limit with a stop margin. Arrange a bounded watchdog that stops only this recorder if the task fails or its owner exits.

After the core final-state opportunity, send SIGINT to the validated exact remote PID. Use `adb -s "$SERIAL" shell kill -INT "$REMOTE_PID"`. Await recorder completion through the managed host process and remote text process state. Use an explicit bounded finalization timeout, such as 15 seconds. Never use an unbounded polling loop. Do not pull while the recorder is still active.

When completion is confirmed, transfer the opaque artifact:

```sh
adb -s "$SERIAL" pull "$REMOTE_VIDEO" "$OUT/recording.mp4"
```

If finalization times out, report failure. Keep the device artifact. Do not claim a complete recording or remove the artifact. Keep device intermediates unless the user approves their exact paths for cleanup.

## Final-state evidence

Use layout JSON, app text logs, backend state, or an existing text animation-status harness. Observe finite animations relevant to the target and exiting overlays if that harness exposes them. Layout bounds alone cannot prove that an animation finished. Two matching snapshots only support semantic stability.

If Android exposes no reliable text animation or frame-opportunity evidence, use the core five-second bound for best-effort capture. Report the limitation. Do not claim that pixels, motion, or the final recorded frame were verified. Do not change animation scales or reduced-motion settings.

## Official reference

Consult the [Android Debug Bridge reference](https://developer.android.com/tools/adb) for device commands. Use the installed Android CLI skill for its current layout command contract.
