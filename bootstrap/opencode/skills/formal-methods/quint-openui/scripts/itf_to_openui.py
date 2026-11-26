# /// script
# requires-python = ">=3.13"
# dependencies = []
# ///
"""Convert a Quint ITF trace into an OpenChamber openui-lang program.

Usage:
  uv run itf_to_openui.py TRACE.itf.json [--ir TYPECHECK.json] [--invariant NAME] [--main MODULE]

The output depends only on the input files. ITF #meta fields such as the
timestamp are ignored, except the status.
"""

import argparse
import json
import sys

MBT_ACTION = "mbt::actionTaken"
MBT_PICKS = "mbt::nondetPicks"
EMPTY_TUPLE = {"#tup": []}
MAX_SAFE_INT = 2**53 - 1


def is_variant(value):
    return isinstance(value, dict) and set(value) == {"tag", "value"}


def is_record(value):
    return isinstance(value, dict) and not is_variant(value) and not any(k.startswith("#") for k in value)


def render(value):
    """Render an ITF value as Quint-like text. Strings are not quoted."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "[" + ", ".join(render(v) for v in value) + "]"
    if "#bigint" in value:
        return value["#bigint"]
    if "#set" in value:
        return "Set(" + ", ".join(render(v) for v in value["#set"]) + ")"
    if "#tup" in value:
        return "(" + ", ".join(render(v) for v in value["#tup"]) + ")"
    if "#map" in value:
        return "Map(" + ", ".join(f"{render(k)} -> {render(v)}" for k, v in value["#map"]) + ")"
    if is_variant(value):
        if value["value"] == EMPTY_TUPLE:
            return value["tag"]
        return f"{value['tag']}({render(value['value'])})"
    return "{ " + ", ".join(f"{k}: {render(v)}" for k, v in value.items()) + " }"


def flatten(path, value, out):
    """Split maps and records into one leaf entry for each key or field."""
    if isinstance(value, dict) and value.get("#map"):
        for k, v in value["#map"]:
            flatten(f"{path}[{render(k)}]", v, out)
    elif is_record(value) and value:
        for k, v in value.items():
            flatten(f"{path}.{k}", v, out)
    else:
        out[path] = value
    return out


def flatten_state(state):
    out = {}
    for name, value in state.items():
        if name != "#meta" and not name.startswith("mbt::"):
            flatten(name, value, out)
    return out


def cell(value):
    """Return a number for integers that JavaScript can hold, otherwise text."""
    if isinstance(value, dict) and "#bigint" in value:
        number = int(value["#bigint"])
        if abs(number) <= MAX_SAFE_INT:
            return number
    return render(value)


def call_text(state):
    action = state.get(MBT_ACTION) or "unknown"
    picks = state.get(MBT_PICKS, {})
    args = [f"{k}: {render(v['value'])}" for k, v in sorted(picks.items()) if v.get("tag") == "Some"]
    return f"{action}({', '.join(args)})" if args else action


def diff_markdown(prev, cur):
    paths = list(cur) + [p for p in prev if p not in cur]
    lines = []
    for path in paths:
        before, after = prev.get(path), cur.get(path)
        if before != after:
            old = "—" if before is None else render(before)
            new = "—" if after is None else render(after)
            lines.append(f"- `{path}`: {old} → {new}")
    return "\n".join(lines) or "No change."


def entity_vars(entity, out):
    if entity.get("kind") == "concrete":
        out.extend(v["name"] for v in entity.get("stateVariables", []))
    elif entity.get("kind") == "union":
        for e in entity.get("entities", []):
            entity_vars(e, out)


def effect_vars(effect, component_kind):
    """List the state variables that an effect reads or updates, in first-seen order."""
    if effect.get("kind") == "arrow":
        effect = effect["result"]
    names = []
    for component in effect.get("components", []):
        if component.get("kind") == component_kind:
            entity_vars(component["entity"], names)
    return list(dict.fromkeys(names))


def s(text):
    return json.dumps(text, ensure_ascii=False)


def literal(value):
    return str(value) if isinstance(value, int) else s(value)


def def_card(decl, effects, violated):
    kind = "var" if decl["kind"] == "var" else decl.get("qualifier") or decl["kind"]
    children = [f"Badge({s(kind)}, \"info\")"]
    if violated:
        children.append('Badge("violated", "error")')
    children.append(f"Text({s(decl.get('doc') or 'No `///` comment.')})")
    effect = effects.get(str(decl["id"]), {}).get("effect")
    if effect and decl["kind"] != "var":
        parts = []
        for label, kind_name in (("Reads", "read"), ("Updates", "update")):
            names = effect_vars(effect, kind_name)
            if names:
                parts.append(f"{label}: " + ", ".join(f"`{n}`" for n in names) + ".")
        if parts:
            children.append(f"Text({s(' '.join(parts))})")
    return f"Card({s('`' + decl['name'] + '`')}, [{', '.join(children)}])"


def select_module(ir, main):
    modules = ir["modules"]
    if main:
        return next(m for m in modules if m["name"] == main)
    if len(modules) != 1:
        raise SystemExit(f"error: the IR has {len(modules)} modules; pass --main")
    return modules[0]


def def_tabs(ir, main, invariant, violation):
    module = select_module(ir, main)
    effects = ir.get("effects", {})
    groups = {"tab_vars": [], "tab_actions": [], "tab_values": []}
    for decl in module["declarations"]:
        if decl["kind"] == "var":
            group = "tab_vars"
        elif decl["kind"] == "def" and decl.get("qualifier") == "action":
            group = "tab_actions"
        elif decl["kind"] in ("def", "const"):
            group = "tab_values"
        else:
            continue
        violated = violation and decl["name"] == invariant
        groups[group].append(def_card(decl, effects, violated))
    labels = {"tab_vars": "State variables", "tab_actions": "Actions", "tab_values": "Values"}
    used = [name for name, cards in groups.items() if cards]
    lines = [f"defs = Tabs([{', '.join(used)}])"]
    lines += [f"{name} = Tab({s(labels[name])}, [{', '.join(groups[name])}])" for name in used]
    return lines


def convert(trace, ir=None, invariant=None, main=None):
    states = trace["states"]
    violation = trace.get("#meta", {}).get("status") == "violation"
    last = len(states) - 1

    if violation:
        who = f"`{invariant}`" if invariant else "An invariant"
        status = f"status = Callout({s(f'{who} fails at state {last}.')}, \"error\", \"Invariant violated\")"
    else:
        recorded = trace.get("#meta", {}).get("status") or "not recorded"
        status = f"status = Callout({s(f'The trace has {len(states)} states. Status: {recorded}.')}, \"info\", \"Trace\")"

    flat = [flatten_state(state) for state in states]
    steps = []
    for i, state in enumerate(states):
        body = "Initial state." if i == 0 else diff_markdown(flat[i - 1], flat[i])
        steps.append(f"{{title: {s(f'State {i}: {call_text(state)}')}, markdown: {s(body)}}}")

    paths = list(dict.fromkeys(p for f in flat for p in f))
    columns = ["State", "Action"] + paths
    rows = []
    for i, state in enumerate(states):
        cells = [i, call_text(state)] + [cell(flat[i][p]) if p in flat[i] else "—" for p in paths]
        rows.append("[" + ", ".join(literal(c) for c in cells) + "]")

    parts = ["status", "flow", "states"] + (["defs"] if ir else [])
    lines = [
        f"root = Stack([{', '.join(parts)}])",
        status,
        f"flow = Steps([{', '.join(steps)}], \"column\")",
        f"states = Table([{', '.join(s(c) for c in columns)}], [{', '.join(rows)}])",
    ]
    if ir:
        lines += def_tabs(ir, main, invariant, violation)
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description="Convert a Quint ITF trace into openui-lang.")
    parser.add_argument("trace", help="ITF trace from `quint run --mbt --out-itf=...`")
    parser.add_argument("--ir", help="output of `quint typecheck --out=...`, for docs and effects")
    parser.add_argument("--invariant", help="name of the checked invariant, as passed to `quint run`")
    parser.add_argument("--main", help="main module name in the IR, when it has more than one module")
    args = parser.parse_args(argv)

    with open(args.trace, encoding="utf-8") as f:
        trace = json.load(f)
    ir = None
    if args.ir:
        with open(args.ir, encoding="utf-8") as f:
            ir = json.load(f)
    sys.stdout.write(convert(trace, ir, args.invariant, args.main))


if __name__ == "__main__":
    main()
