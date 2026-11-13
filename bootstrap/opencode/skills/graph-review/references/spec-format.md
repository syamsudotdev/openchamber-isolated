# Spec format

The spec is one JSON file. `build.mjs` validates it and stops with one `ERROR` line for each problem.

```json
{
  "title": "Checkout flow call graph vs main",
  "base": "main",
  "kinds": { "page": "Page / component", "hook": "Hook / state", "client": "HTTP client", "handler": "API handler", "job": "Background job" },
  "edgeTypes": { "c": { "label": "call" }, "h": { "label": "HTTP request" }, "q": { "label": "enqueue", "dashed": true } },
  "nodes": {
    "page": { "label": "CartPage", "kind": "page", "status": "M", "decl": "web/src/CartPage.tsx:3" },
    "hook": { "label": "useCart", "kind": "hook", "status": "A", "decl": "useCart.ts:3", "symbols": ["useCart"] },
    "handler": { "label": "checkout\n(API)", "kind": "handler", "status": "M", "decl": "api/checkout.py:5", "note": "Places the order and queues the receipt." },
    "receipt": { "label": "SendReceipt", "kind": "job", "status": "A", "decl": "worker/receipt.go:3" }
  },
  "tabs": [
    {
      "name": "Checkout",
      "caption": "The cart page posts the checkout. The API places the order and queues the receipt job.",
      "rowLabels": ["UI", "API", "Jobs"],
      "rows": [["page", "hook"], ["handler"], ["receipt"]],
      "edges": [
        { "from": "page", "to": "hook", "type": "c", "note": "useCart / checkout", "sites": "CartPage.tsx:4,6" },
        { "from": "hook", "to": "handler", "type": "h", "note": "POST checkout", "sites": "useCart.ts:8" },
        { "from": "handler", "to": "receipt", "type": "q", "note": "enqueue_receipt", "sites": "checkout.py:10" }
      ]
    }
  ]
}
```

## Top level

| Field | Required | Meaning |
| --- | --- | --- |
| `title` | no | Page title. |
| `base` | no | Base ref name shown in the hint line. |
| `kinds` | yes | Ordered map of kind id → legend text. Up to 6 kinds get distinct border colors; more kinds repeat the colors. A kind with the id `other` is always gray. |
| `edgeTypes` | no | Ordered map of edge type id → `{ "label", "dashed"? }`. Up to 6 types get distinct colors. Default: `{ "c": { "label": "call" } }`. Use `dashed` for indirect links (inject, observe, subscribe, enqueue, emit). |
| `nodes` | yes | Map of node id → node. |
| `tabs` | yes | Ordered list of tabs. The first tab opens first. |

## Node

| Field | Required | Meaning |
| --- | --- | --- |
| `label` | yes | Box text. `\n` breaks the line in the plain graph. In headers the parts join without a space, or with one space before `(` and `/`. |
| `kind` | yes | A key of `kinds`. Sets the border color. |
| `status` | yes | `A` added, `M` modified, `U` existing (unchanged). Sets the dot color. |
| `decl` | no | Declaration reference (see [References](#references)). Omit it for code outside the repository or a group of destinations; then write a `note`. |
| `note` | no | One or two sentences: what the node does in this change. Shown in the tooltip and in the expanded node. |
| `symbols` | no | Extra names to mark in code. The page marks names declared with a keyword (`class`, `fun`, `def`, `func`, `function`, `struct`, `interface`, and others) by itself. Add `symbols` for a declaration without such a keyword, for example `const useCart = (...) =>`. |

## Tab

| Field | Required | Meaning |
| --- | --- | --- |
| `name` | yes | Tab button text. Keep it short. |
| `caption` | no | One sentence above the graph. |
| `rows` | yes | List of rows, top to bottom. Each row is a list of node ids, left to right. A node occurs once in a tab. |
| `rowLabels` | no | Short label for each row, shown at the left. |
| `edges` | yes | Edges of this tab. Both ends must be in this tab's rows. |

## Edge

| Field | Required | Meaning |
| --- | --- | --- |
| `from` | yes | Caller node id. |
| `to` | yes | Callee node id. |
| `type` | yes | A key of `edgeTypes`. |
| `note` | no | Short text: what is called, or why. Identifiers in it get marked in the code: a capitalized word wherever it occurs, a lowercase word only where it is called (`name(`). |
| `sites` | yes | Call-site references in the caller, joined with `\|` (see [References](#references)). Edges with the same `sites` string share one snippet. |

## References

A reference is `path:lines`.

- `path` is repository-relative, or a file name or path tail that matches exactly one file in `git ls-files`. When the name matches more than one file, the build lists the matches; use a longer path.
- `lines` is a comma list. Each part is `n` or `a-b`.
  - `n` in `decl`: the declaration header from line `n` up to the line that opens the body or closes the parameter list (at most 9 lines). Point `n` at the line with the declared name, after annotations, decorators, and attributes.
  - `n` in `sites`: one statement from line `n`, up to bracket balance (at most 7 lines). A line that ends with a block opener (`{`, `{ x ->`, `=>`, `:`) and has balanced brackets before it stays one line. An unfinished statement gets the mark `… statement continues`.
  - `a-b`: exactly lines `a` to `b`. Use it when the heuristic picks the wrong lines, for example for code with unbalanced brackets in a comment, or Rust lifetimes (`'a`).
  - `@c-d` after a part sets the holding body to exactly lines `c` to `d`: `246@242-262`, `405-406@405-410`. The range must contain the part. Use it when `review.txt` shows a wrong `body:` line.
- `sites` joins references in different files with `|`: `Screen.kt:534|Fragment.kt:101`. Use this when a call goes through a callback that a second file wires.

Line numbers come from the working tree at build time. Rebuild after every source change.

## Holding bodies

`build.mjs` finds one body for each part. The body is what the **Whole function** switch shows.

| Part in | Body |
| --- | --- |
| `decl` | The function that starts at the part's first function header. Without a function header, the declaration that starts at the part's first line. A type header (class, object, interface, struct, enum, trait, protocol, record, `type`) gets no body, so the node shows only its declaration. |
| `sites` | The innermost function around the part's first line. Without one, the outermost declaration below the enclosing type, for example a property initializer. A type body is never a holder. |

- A **function header** is a line with `fun`, `func`, `function`, `def`, `fn`, or `sub`; a typed signature such as `public void run(`; an arrow-function assignment such as `const f = (` or `const f = async (x) =>`; or `init`, `constructor`, `deinit`, and `static` blocks.
- The body ends where the brackets balance and the statement does not continue on the next line. A header that ends with `:` and has deeper lines after it owns the indented block (Python).
- A part gets no body when the body would show no more lines than the snippet: a single-line function, an abstract function, or a class-level property.
