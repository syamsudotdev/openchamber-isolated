#!/usr/bin/env node
// Usage: node check.mjs <page.html> <repoRoot>
// Runs the page script on a stub DOM, clicks every node in every tab, and checks the in-graph highlight:
// the selected node and its linked nodes show code, linked edges are on, and all other nodes and edges fade.
// It also turns on the global and per-block "Whole function" switches and checks the rendered lines.
// A second click must clear the selection. Every embedded code line, in snippets and in bodies, must match the working tree verbatim.
import fs from 'node:fs';
import path from 'node:path';

const [pagePath, root] = process.argv.slice(2);
if (!pagePath || !root) { console.error('Usage: node check.mjs <page.html> <repoRoot>'); process.exit(2); }
const html = fs.readFileSync(pagePath, 'utf8');
const scripts = html.split('<script>');
if (scripts.length !== 2) throw new Error(`expected one <script> element, found ${scripts.length - 1}`);
const code = scripts[1].split('</script>')[0];

class El {
  constructor(tag) { this.tag = tag; this.children = []; this.attrs = {}; this.styles = {}; this.className = ''; this._text = ''; this.hidden = false; this.listeners = {}; this.style = { setProperty: (k, v) => { this.styles[k] = v; } }; }
  appendChild(c) { this.children.push(c); return c; }
  setAttribute(k, v) { this.attrs[k] = String(v); }
  addEventListener(t, f) { this.listeners[t] = f; }
  set innerHTML(v) { this.children = []; }
  set textContent(v) { this._text = String(v); }
  get textContent() { return this._text + this.children.map(c => c.textContent).join(''); }
  all(pred, out = []) { for (const c of this.children) if (c instanceof El) { if (pred(c)) out.push(c); c.all(pred, out); } return out; }
}
const ids = {};
globalThis.document = {
  title: '',
  getElementById: id => (ids[id] ??= new El('div')),
  createElementNS: (_, t) => new El(t),
  createTextNode: t => ({ textContent: t }),
  querySelectorAll: sel => (sel === '#tabs button' ? ids.tabs.children : []),
};
const api = new Function(code + '\nreturn {DATA, TABS, SNIP, READY, draw, pick, blocks, isOpen, get sel(){return sel}, get whole(){return whole}};')();
await api.READY;
const g = () => ids.g;
const cls = c => c.attrs.class || '';
const fail = msg => { throw new Error(msg); };
const ev = { stopPropagation() {}, preventDefault() {} };

if (/cannot unpack/.test(ids.caption.textContent)) fail(ids.caption.textContent);
if (!document.title) fail('page title missing');
const legendItems = ids.legend.children.length;
const expectedLegend = Object.keys(api.DATA.kinds).length + 3 + Object.keys(api.DATA.edgeTypes).length;
if (legendItems !== expectedLegend) fail(`legend has ${legendItems} items, expected ${expectedLegend}`);
const unpainted = g().all(c => ['path', 'rect', 'circle'].includes(c.tag) && Object.values(c.attrs).some(v => v.includes('var(')));
if (unpainted.length) fail(`${unpainted.length} SVG attributes use var(); browsers ignore var() in presentation attributes`);

const parts = [...Object.values(api.SNIP.decl), ...Object.values(api.SNIP.call)].flat();
for (const s of parts) if (s.body && (s.body.first > s.first || s.body.last < s.last)) fail(`body ${s.file}:${s.body.lines} does not contain snippet ${s.lines}`);

const rows = () => g().all(c => c.tag === 'span' && c.className.split(' ')[0] === 'l');
const hits = () => g().all(c => c.tag === 'span' && c.className === 'l hit');
const toggles = () => g().all(c => c.tag === 'button' && c.className === 'tg');
// Lines and snippet hits the page must show for the current selection, from the page's own block model.
function expected(linked) {
  let lines = 0, hit = 0;
  for (const id of linked) for (const b of api.blocks(id)) for (const s of b.parts) {
    if (api.isOpen(s)) { lines += s.body.code.length; hit += s.last - s.first + 1; } else lines += s.code.length + (s.more ? 1 : 0);
  }
  return { lines, hit };
}
function compare(where, linked) {
  const want = expected(linked), got = { lines: rows().length, hit: hits().length };
  if (want.lines !== got.lines || want.hit !== got.hit) fail(`${where}: shows ${got.lines} lines and ${got.hit} hits, expected ${want.lines} and ${want.hit}`);
  return got;
}

let clicks = 0, codeLines = 0, wholeLines = 0, toggled = 0;
api.TABS.forEach((t, i) => {
  api.draw(i);
  if (ids.tabs.children[i].attrs['aria-pressed'] !== 'true') fail(`${t.name}: tab button not pressed`);
  if (g().all(c => c.tag === 'foreignObject').length) fail(`${t.name}: code shown with no selection`);
  const rowIds = t.rows.flat();
  if (g().all(c => c.tag === 'g' && c.attrs['data-id']).length !== rowIds.length) fail(`${t.name}: node count differs from rows`);
  if (g().all(c => c.tag === 'path' && cls(c).startsWith('edge')).length !== t.edges.length) fail(`${t.name}: edge count differs from spec`);
  for (const id of rowIds) {
    const where = `${t.name}/${id}`;
    const node = g().all(c => c.tag === 'g' && c.attrs['data-id'] === id)[0];
    node.listeners.click(); clicks++;
    if (api.sel !== id) fail(`${where}: click did not select`);
    const edges = t.edges.filter(e => e.from === id || e.to === id);
    const linked = new Set(edges.flatMap(e => [e.from, e.to]).concat(id));
    const fos = g().all(c => c.tag === 'foreignObject');
    if (fos.length !== linked.size) fail(`${where}: ${fos.length} code nodes vs ${linked.size} linked`);
    const on = g().all(c => c.tag === 'path' && cls(c).includes(' on')).length;
    const dim = g().all(c => c.tag === 'path' && cls(c).includes(' dim')).length;
    if (on !== edges.length || dim !== t.edges.length - edges.length) fail(`${where}: edges on ${on}/${edges.length} dim ${dim}/${t.edges.length - edges.length}`);
    const dimNodes = g().all(c => c.tag === 'g' && cls(c).includes(' dim')).length;
    if (dimNodes !== rowIds.length - linked.size) fail(`${where}: ${dimNodes} faded nodes, expected ${rowIds.length - linked.size}`);
    for (const e of edges) if (!api.SNIP.call[e.sites]?.length) fail(`${where}: edge ${e.from} → ${e.to} has no call-site code`);
    if (ids.bar.hidden) fail(`${where}: status bar hidden`);
    if (hits().length) fail(`${where}: body open before any switch`);
    codeLines += compare(where, linked).lines;

    const switches = toggles().length;
    ids.whole.onclick();
    if (!api.whole || ids.whole.attrs['aria-pressed'] !== 'true') fail(`${where}: global switch not on`);
    if (toggles().length !== switches || toggles().some(b => b.attrs['aria-pressed'] !== 'true')) fail(`${where}: global switch did not open every block`);
    wholeLines += compare(`${where} (whole functions)`, linked).lines;
    ids.whole.onclick();
    if (api.whole || hits().length) fail(`${where}: global switch did not close`);

    if (switches) {
      toggles()[0].listeners.click(ev); toggled++;
      const pressed = toggles().filter(b => b.attrs['aria-pressed'] === 'true').length;
      if (pressed < 1 || !hits().length) fail(`${where}: block switch did not open its body`);
      compare(`${where} (one block)`, linked);
      toggles().find(b => b.attrs['aria-pressed'] === 'true').listeners.click(ev);
      if (hits().length) fail(`${where}: block switch did not close its body`);
    }
    node.listeners.click();
    if (api.sel !== null || g().all(c => c.tag === 'foreignObject').length) fail(`${where}: second click did not clear`);
  }
  const first = rowIds[0];
  g().all(c => c.tag === 'g' && c.attrs['data-id'] === first)[0].listeners.click();
  ids.clear.onclick();
  if (api.sel !== null || !ids.bar.hidden) fail(`${t.name}: Clear selection did not clear`);
});

const src = {}; let checked = 0;
for (const s of parts) for (const l of [...s.code, ...(s.body ? s.body.code : [])]) {
  const line = (src[s.file] ??= fs.readFileSync(path.join(root, s.file), 'utf8').split('\n'))[l.n - 1];
  if (line === undefined || !line.endsWith(l.t) || line.slice(0, line.length - l.t.length).trim()) fail(`not verbatim ${s.file}:${l.n}`);
  checked++;
}
const bodies = parts.filter(s => s.body).length;
console.log(`ok: ${api.TABS.length} tabs, ${clicks} node clicks, ${toggled} block switches, ${codeLines} snippet lines and ${wholeLines} whole-function lines shown, ${bodies}/${parts.length} parts with a body, ${checked} lines verbatim, ${html.length} characters`);
