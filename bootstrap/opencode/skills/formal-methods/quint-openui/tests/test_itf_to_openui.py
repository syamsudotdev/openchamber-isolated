import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).parent
FIXTURES = HERE / "fixtures"
SPEC = importlib.util.spec_from_file_location("itf_to_openui", HERE.parent / "scripts" / "itf_to_openui.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def load(name):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def test_bank_trace_matches_hand_written_program():
    # Expected output was written by hand from the trace, not produced by the script.
    out = mod.convert(load("bank.itf.json"), load("bank.ir.json"), "no_negatives")
    assert out == (FIXTURES / "bank.expected.openui").read_text(encoding="utf-8")


def test_render_composite_values():
    assert mod.render({"#set": [{"#bigint": "1"}, {"#bigint": "2"}]}) == "Set(1, 2)"
    assert mod.render({"#tup": ["a", True]}) == "(a, true)"
    assert mod.render({"tag": "Some", "value": {"#bigint": "7"}}) == "Some(7)"
    assert mod.render({"tag": "None", "value": {"#tup": []}}) == "None"
    assert mod.render({"x": [{"#bigint": "1"}]}) == "{ x: [1] }"


def test_diff_shows_added_and_removed_map_keys():
    prev = mod.flatten("m", {"#map": [["a", {"#bigint": "1"}]]}, {})
    cur = mod.flatten("m", {"#map": [["b", {"#bigint": "2"}]]}, {})
    assert mod.diff_markdown(prev, cur) == "- `m[b]`: — → 2\n- `m[a]`: 1 → —"


def test_trace_without_mbt_uses_unknown_action():
    trace = load("bank.itf.json")
    for state in trace["states"]:
        del state["mbt::actionTaken"], state["mbt::nondetPicks"]
    out = mod.convert(trace)
    assert '{title: "State 1: unknown", markdown: "- `balances[bob]`: 0 → 75"}' in out
    assert '[1, "unknown", 0, 75, 0]' in out
    assert "defs" not in out
