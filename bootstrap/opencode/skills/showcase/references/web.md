# Web capture branch

Apply the core Showcase contract. Use an existing Playwright and Chromium dependency only. Do not install a package or browser. Use an existing authorized authentication state without reading secret values into tool output. Preserve platform settings, including reduced motion.

## Observe and act

Use DOM, accessibility information, application text logs, and backend state. Choose current text selectors. Require the action locator to be visible and enabled before an action. Define a positive business locator or backend condition separately from animation readiness. Use an explicit timeout for every action and business wait.

## Bounded final settle

This complete JavaScript example exports a helper for an existing harness. `target` is an ElementHandle for a stable relevant container. Include exiting overlays in that container, or supply equivalent observation for a separate overlay root. `businessReady` confirms the approved positive condition. It must return promptly within the supplied remaining time. Bound all underlying API calls by that time.

```js
export async function settleFinal({ target, businessReady, budgetMs = 5000 }) {
  const start = performance.now();
  const deadline = start + Math.min(5000, Math.max(0, budgetMs));
  let previousBounds = null;
  const remaining = () => Math.max(0, deadline - performance.now());
  while (remaining() > 0) {
    if (!(await businessReady(remaining()))) {
      return { settled: false, reason: 'Business state changed', elapsedMs: performance.now() - start };
    }
    if (remaining() <= 0) break;
    const state = await target.evaluate((element) => {
      const bounds = element.getBoundingClientRect();
      const activeFinite = element.getAnimations({ subtree: true }).some((animation) => {
        const timing = animation.effect?.getComputedTiming();
        return timing && timing.iterations !== Infinity && Number.isFinite(timing.endTime)
          && (animation.pending || animation.playState === 'running' || animation.playState === 'paused');
      });
      return { bounds: JSON.stringify([bounds.x, bounds.y, bounds.width, bounds.height]), activeFinite };
    });
    if (remaining() <= 0) break;
    if (!state.activeFinite && state.bounds === previousBounds) {
      const frameBudget = remaining();
      const frameOpportunity = await target.evaluate((element, ms) => new Promise((resolve) => {
        const timer = setTimeout(() => resolve(false), ms);
        requestAnimationFrame(() => requestAnimationFrame(() => {
          clearTimeout(timer);
          resolve(true);
        }));
      }), frameBudget);
      if (remaining() <= 0) break;
      const confirmed = await businessReady(remaining());
      if (remaining() <= 0) break;
      return {
        settled: frameOpportunity && confirmed,
        reason: confirmed ? 'Text state and render opportunity observed' : 'Business state changed',
        elapsedMs: performance.now() - start,
      };
    }
    previousBounds = state.bounds;
    await new Promise((resolve) => setTimeout(resolve, Math.min(50, remaining())));
  }
  return { settled: false, reason: 'Final settle deadline reached', elapsedMs: performance.now() - start };
}
```

Call this helper immediately when final business readiness first becomes true. Deduct any elapsed time between that observation and the call from `budgetMs`. Never call it again to extend the same final hold. A paused finite animation is unresolved. Infinite iterations do not block capture. `pending` is a Boolean property; it is not a `playState` value.

The helper's bounds and render opportunity are text evidence, not pixel or video-frame proof. Browser calls can stall beyond their expected duration. Give the existing harness a watchdog tied to the same fixed deadline. At the deadline, stop waiting and begin best-effort capture or recorder finalization. Record actual elapsed time. Report any overrun. Keep a failed business condition distinct from an unverified animation end.

## Opaque capture lifecycle

Adapt these fragments in the existing harness. Supply approved placeholders for URL, viewport, paths, authentication options, and selectors. Do not create fake application selectors or inputs.

```js
const browser = await chromium.launch(existingLaunchOptions);
let context;
let video;
try {
  context = await browser.newContext({
    ...existingContextOptions,
    recordVideo: { dir: uniqueVideoDirectory },
  });
  const page = await context.newPage();
  video = page.video();
  // Recording starts with the page, before navigation and journey actions.
  await page.goto(approvedUrl, { timeout: navigationTimeoutMs });
  // Verify initial state, execute approved actions, and confirm business readiness.
  // Apply the single bounded final settle and render opportunity.
  // For a screenshot request, omit recordVideo and this video handle.
  await page.screenshot({ path: uniqueScreenshotPath, timeout: captureTimeoutMs });
  // Discard the screenshot return value. Never log or inspect it.
} finally {
  try {
    if (context) await context.close();
    // Context closure finalizes video before saveAs or path is used.
    if (video) await video.saveAs(uniqueRecordingPath);
  } finally {
    await browser.close();
  }
}
```

For a recording-only request, omit `page.screenshot`. For a screenshot-only request, omit video setup and saving. Use unique destination paths and check for conflicts before capture. Store only the video handle, not media bytes. `video.saveAs` copies the opaque recording after context closure. Do not read the resulting file or upload it.

Assign the lifecycle owner a separate bounded finalization watchdog. If context closure fails or times out, do not claim a finalized video. Preserve the temporary video directory. On a journey failure, finalize available video when possible and label the artifact partial. Never delete the original video or other artifacts without approval for their exact paths.

## Official references

- Read [video recording lifecycle](https://playwright.dev/docs/videos) when recording.
- Read [Video methods](https://playwright.dev/docs/api/class-video) when saving a recording.
- Read [page.screenshot](https://playwright.dev/docs/api/class-page#page-screenshot) when capturing a screenshot.
