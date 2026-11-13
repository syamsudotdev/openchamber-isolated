# Language hints

Choose kinds from the roles that this codebase uses, not from this table. The table gives starting points. Use 4 to 6 kinds and keep `other` for the rest.

## Kinds by codebase type

| Codebase | Kinds, top layer first |
| --- | --- |
| Android (Kotlin, Java) | `screen` Activity / Fragment · `ui` Composable / View · `vm` ViewModel · `repo` Repository / port · `api` Service / API / Worker · `other` |
| iOS (Swift) | `screen` View controller / SwiftUI view · `vm` View model / store · `svc` Service / use case · `repo` Repository / storage · `api` API client · `other` |
| Web front end (TypeScript, JavaScript) | `route` Route / page · `ui` Component · `state` Hook / store · `client` API client · `other` |
| Back end (Go, Java, Kotlin, Python, C#, Ruby) | `entry` Handler / controller · `svc` Service · `repo` Repository / DAO · `ext` External client · `job` Job / consumer · `other` |
| Library or CLI | `entry` Command / public API · `core` Internal logic · `io` File / network adapter · `model` Data type · `other` |

## Edge types

Start with `c` call. Add a type only when the link is not a direct call:

| Id | Label | Dashed | Use for |
| --- | --- | --- | --- |
| `n` | navigate | no | Screen or route changes, intents, links, redirects |
| `i` | inject / observe | yes | Dependency injection, subscriptions, flows, observers, event listeners |
| `q` | enqueue | yes | Job queues, message brokers, WorkManager, background tasks |
| `h` | HTTP request | no | A client call to a server endpoint in the same repository |
| `e` | emit | yes | Events, signals, callbacks that a parent wires |

## Declaration lines

Point `decl` at the line that holds the declared name.

| Language | Rule |
| --- | --- |
| Kotlin, Java, C# | Skip annotations (`@Composable`, `@HiltViewModel`, `[Attr]`). For a class with a primary constructor, the header runs to `) {` or `) :`. |
| Swift | Skip attributes (`@MainActor`). `func`, `struct`, `class`, `protocol`, `extension` lines. |
| TypeScript, JavaScript | `function` and `class` lines are marked by themselves. For `const name = (...) =>`, add `symbols: ["name"]`. For a component in an `export default` expression, use an explicit range. |
| Python | Skip decorators. The header runs to the line that ends with `:`. |
| Go | `func (r *T) Name(` works; the receiver is skipped when names are marked. |
| Rust | Skip attributes (`#[derive]`). Lifetimes (`'a`) can confuse the bracket count; use an explicit `a-b` range when the header is wrong. |
| Other languages | Give explicit `a-b` ranges when the review text shows a wrong header. |

## Holding bodies

| Language | Rule |
| --- | --- |
| Kotlin | A call inside a lambda (Compose `onClick = { … }`, `launch { … }`) is held by the named function around the lambda. A class-level `val x = object : T { … }` or `by lazy { … }` is held by the property declaration. |
| JavaScript, TypeScript | A class method without a keyword (`render() {`) is not a function header. The script then shows the method as a declaration body, for its `decl` and for call sites inside it. A function passed inline as an argument is held by the named function around it. |
| Python | Bodies follow indentation. Decorators are outside the body. |
| Go, Rust, Swift, C# | Brace bodies need no override, except where a comment has unbalanced brackets. |
| Macro or template code | Give `@c-d` for each part. |

## Call-site lines

- Point at the line with the call. For a chained or multi-line call, point at the line where the call starts.
- For a callback that a parent wires (Compose lambda, React prop, Swift closure, Go func value), use two references joined with `|`: the line in the child that invokes the callback, and the line in the parent that binds it.
- For a call through an interface, point at the call in the caller. Name the implementation in the edge `note`.
- For a framework entry (route table, manifest, dependency-injection module), point at the registration line.
