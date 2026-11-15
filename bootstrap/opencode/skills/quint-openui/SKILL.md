---
name: quint-openui
description: Convert a Quint trace (ITF JSON) and its typecheck output into an openui-lang block for the OpenChamber chat, with a deterministic script. Use when the user wants to see a Quint simulation, counterexample, or spec definitions as UI blocks (steps, state table, action and invariant cards). For writing or debugging the spec itself, use quint-lang or quint-modeling.
---

# quint-openui

Render a Quint trace as an openui-lang program. The script `scripts/itf_to_openui.py` produces the program. Do not write the program by hand: the same inputs must always give the same output.

## Requirements

- `quint` 0.33.1 on `PATH` (`npm i -g --prefix ~/.local @informalsystems/quint@0.33.1`).
- `uv`. The script uses only the Python standard library.

## Procedure

1. Generate the trace. Use `--mbt` so that each step has its action name and nondeterministic picks. Use a fixed `--seed` when the result must be repeatable.
   ```bash
   quint run SPEC.qnt --invariant=INV --mbt --seed=0x1 --out-itf=trace.itf.json
   ```
   Exit code 1 with `error: Invariant violated` is a normal result. The trace contains the counterexample.
2. Generate the IR. It supplies the `///` doc comments and the variables that each definition reads and updates.
   ```bash
   quint typecheck SPEC.qnt --out=ir.json
   ```
3. Convert. Pass the same invariant name that `quint run` checked.
   ```bash
   uv run ~/.config/opencode/skills/quint-openui/scripts/itf_to_openui.py trace.itf.json --ir ir.json --invariant INV
   ```
   Add `--main MODULE` when the IR has more than one module.
4. Put the stdout, unchanged, in the reply between a line ```openui-lang and a line ```.

## Output

- `status`: a `Callout`. Tone `error` when the ITF status is `violation`, the last state is the violating state.
- `flow`: `Steps`, one for each state, with the action call and the changed values.
- `states`: a `Table`, one row for each state and one column for each map key or record field.
- `defs` (only with `--ir`): `Tabs` with cards for state variables, actions, and values.

## Limits

- Without `--mbt`, the action column shows `unknown`. Do not infer the action from the state change.
- `--mbt` is experimental in Quint. If a newer Quint changes `mbt::actionTaken` or `mbt::nondetPicks`, run the tests again.
- `--out-itf` with `--n-traces` writes one file per trace. Convert each file separately.

## Tests

```bash
uv run --with pytest==9.2.0 pytest -q ~/.config/opencode/skills/quint-openui/tests
```

`tests/fixtures/bank.expected.openui` was written by hand from `bank.itf.json`. Do not regenerate it with the script.
