# Kotlin example: MOP Master

[`spec.json`](spec.json) is the call graph of the MOP Master feature branch (`feat/mop-master-android`) against `rc` in the 99.co Android app. It is a Kotlin project with Fragments, Jetpack Compose, legacy Views, Hilt ViewModels, repositories, Retrofit, and WorkManager.

- 4 tabs: Overview, Results & export, Filters, Dashboard & BTO report.
- 75 nodes, 121 edges, 73 declarations, 101 call-site snippets.
- 175 of 219 snippet parts have a holding body: 171 functions and 4 holding declarations. The largest body is `MopMasterResultsScreen` (388 lines). The class and interface nodes show their declaration only.
- The line numbers match commit `f10795d7f9`. At that commit, `build.mjs` and `check.mjs` pass with 9943 verbatim lines, and the page has 110187 characters. With later source changes, `review.txt` shows the shifted lines.

## What to copy from it

| Pattern | Where in `spec.json` |
| --- | --- |
| Android kinds: `screen`, `ui`, `vm`, `repo`, `api`, `other` | `kinds` |
| Four edge types: call, navigate, inject / observe (dashed), enqueue (dashed) | `edgeTypes` |
| A node per ViewModel function, so that one ViewModel splits into its public API and its internal steps | tab `Results & export`, nodes `fApply` to `fFile` |
| An interface node with the implementation in the note | nodes `repo`, `exRepo`, `exJobs`, `cfg` |
| An unchanged caller that a changed shared class reaches (status `U`) | node `ftf` and its edges in tab `Filters` |
| A destination group with no declaration | nodes `toolDest`, `payPlan` |
| A Compose callback wired in the Fragment: two references joined with `\|` | edge `pager` → `fLoadMore` |
| One declaration with two parts | node `fFile`: `MopMasterResultsViewModel.kt:405,412` |
| Many endpoints in one interface as explicit ranges | node `apiSearch` |
| A node that occurs in several tabs with the same id | `resFrag`, `resVm`, `upsell` |
