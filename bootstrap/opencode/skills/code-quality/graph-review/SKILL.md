---
name: graph-review
description: "Graphical code review: turn a branch diff into one interactive call-graph page. Clicking a node highlights its callers and callees in place and shows their verbatim code, up to the whole function that holds it. Works for any language or codebase. Use when the user asks for a graph, visual, or call-graph review of a diff, branch, or pull request, or asks how the changed code connects."
---

# Graph review

Build one self-contained HTML page that draws the changed code as a call graph. The agent reads the code and writes a JSON **spec** (nodes, edges, call-site line numbers). The scripts copy every code line **verbatim** from the working tree, find the whole function that **holds** each snippet, build the page, and check it. The scripts and the page know nothing about a language: they work on brackets, line continuation, and indentation, and the spec carries the rest.

In a highlighted node, each code block has a **Whole function** switch, and the status bar has a **Whole functions** switch for all blocks. A switch replaces the snippet with the body that holds it: the selected node's function, the function around each caller's call site, and each callee's function. The snippet lines stay highlighted inside the body. A type node (class, object, interface) shows only its declaration.

`<skill>` below means this skill's directory. The scripts need Node.js 18 or later and a Git repository.

| File | Use |
| --- | --- |
| [`references/spec-format.md`](references/spec-format.md) | Spec schema. Read it before step 4. |
| [`references/language-hints.md`](references/language-hints.md) | Node kinds, edge types, and line-number rules for each language family. Read it in step 3. |
| [`examples/kotlin-mop-master/`](examples/kotlin-mop-master/README.md) | A complete 4-tab, 75-node spec from an Android Kotlin project. |
| `scripts/build.mjs` | Spec → page, plus a plain-text review of every extracted snippet and its holding body. |
| `scripts/check.mjs` | Stub-DOM test of the page and its switches, and verbatim test of every code line. |
| `assets/template.html` | The page. Light theme with its own colors; it does not depend on host CSS. |

Put the spec, the page, and the review text in the session scratchpad, never in the repository.

## Steps

### 1. Fix the base

Use the base ref the user gives. Otherwise use the repository's default branch. Then set `BASE=$(git merge-base <ref> HEAD)`. The scripts read the working tree, so uncommitted changes are part of the review. Tell the user when the working tree has uncommitted changes.

Done when: `BASE` is a commit and you know whether the working tree is clean.

### 2. List the change

Run `git diff --name-status $BASE` and `git ls-files --others --exclude-standard`. For each changed source file, read `git diff $BASE -- <file>` to find the changed declarations.

Done when: every changed file is in one of two lists: files that the graph will show, or files that it omits with a reason (tests, resources, generated code, build configuration, documentation).

### 3. Map the network

Read the code. Do not infer edges from names. Collect:

- **Nodes**: changed or added declarations that carry behavior (entry points, screens, handlers, services, repositories, workers, public functions), and unchanged declarations one hop away that bound the change.
- **Unchanged callers of changed code**: search every changed declaration's name across the repository. Add an unchanged caller as a node with status `U` when the change alters what it gets (a new parameter default, a changed behavior, a new subclass). These are the side impacts that a diff view hides.
- **Edges**: one edge for each caller → callee pair, with the exact call-site lines. A pair that calls through an interface gets one edge to the interface node; name the implementation in the edge note.
- **Kinds and edge types** for this codebase, from [`references/language-hints.md`](references/language-hints.md).

Done when: every node has a declaration line or a note that says why it has none, and every edge has at least one call-site line that you saw in the file.

### 4. Arrange the tabs and write the spec

Write the spec in the format of [`references/spec-format.md`](references/spec-format.md).

- Make an **Overview** tab first: entry points at the top, data and network at the bottom. Add one tab for each flow that has more detail.
- Put at most 6 nodes in a row and about 25 nodes in a tab. Order rows by layer so that most edges point down.
- Give a node the same id in every tab.

Done when: the spec has every node and edge from step 3, and each tab caption states in one sentence what the tab shows.

### 5. Build and read the review text

```bash
node <skill>/scripts/build.mjs <repoRoot> <spec.json> <page.html> <review.txt>
```

The script stops on each spec error (missing node, edge end outside the tab, ambiguous file name, line out of range). Fix the spec and run it again.

Then read all of `review.txt`. Each `DECL` block must show the start of the named declaration. Each `CALL` block must show the call that the edge names. When a block shows the wrong lines, correct the line number or give an explicit `a-b` range, and build again.

Each snippet line group ends with a `body:` line, with the `first` and `last` line of the holder:

- `body: function a-b`: `first` must be the header of the function that holds the snippet, and `last` must be the end of that function.
- `body: declaration a-b`: no function holds the snippet, so the body is the holding declaration (for example a property initializer). Confirm that no function holds it.
- `body: none` is correct for a type declaration, an abstract function, and a snippet that is already the whole function.
- `WARN long body` marks a body above 600 lines. Confirm that the range is one function.

Fix a wrong holder with `@a-b` after the part (see [References](references/spec-format.md#references)).

Done when: the build prints the counts, every block in `review.txt` shows the code that its title names, and every `body:` line names the holder of its snippet.

### 6. Check the page

```bash
node <skill>/scripts/check.mjs <page.html> <repoRoot>
```

It clicks every node in every tab, checks the highlighted and faded nodes and edges, turns the global and per-block **Whole function** switches on and off, and checks every snippet and body line against the source file. Fix the cause of each failure in the spec, then repeat from step 5.

Done when: the script prints `ok:`.

### 7. Deliver the page

- When a tool renders HTML in the chat (for example `openchamber_render` with `html`), read `page.html` and pass its exact contents. Do not retype or edit the page. The render limit is 200000 characters; `build.mjs` warns above it. Then split the tabs into two specs and render two pages in two answers.
- Otherwise, give the user the absolute path of `page.html` to open in a browser.

The page stores the source lines gzip-compressed and unpacks them with `DecompressionStream`, which current browsers support. Without it, the caption shows an error.

### 8. Report

Write the report in this order:

1. **Graph**: the base, the tabs, and the node and edge counts. Tell the user to click a node to see its callers and callees, to use **Whole function** on a block or **Whole functions** in the status bar to see the holding functions, and to click the selected node or **Clear selection** to return.
2. **Findings**: what the map showed: unchanged callers that the change reaches, high fan-in nodes, edges that cross layers in the wrong direction, changed code with no caller. Give `file:line` for each.
3. **Checked**: the `check.mjs` result line.
4. **Not checked**: the files omitted in step 2 with their reasons, uncommitted changes in the graph, and rendering in a real browser when you did not open one.
