#!/usr/bin/env node
// Usage: node build.mjs <repoRoot> <spec.json> <out.html> [review.txt]
// Validates the spec, copies every referenced source line verbatim from the working tree, finds the whole function
// that holds each snippet, injects the data into assets/template.html, and writes a plain-text review of every snippet and body.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { execFileSync } from 'node:child_process';

const [root, specPath, outPath, reviewPath] = process.argv.slice(2);
if (!root || !specPath || !outPath) {
  console.error('Usage: node build.mjs <repoRoot> <spec.json> <out.html> [review.txt]');
  process.exit(2);
}
const RENDER_LIMIT = 200000;
const LONG_BODY = 600;
const DEFAULT_EDGE_TYPES = { c: { label: 'call' } };
const STATUSES = ['A', 'M', 'U'];
const errors = [];
const fail = msg => errors.push(msg);

const spec = JSON.parse(fs.readFileSync(specPath, 'utf8'));
const kinds = spec.kinds || {};
const edgeTypes = spec.edgeTypes || DEFAULT_EDGE_TYPES;
const nodes = spec.nodes || {};
const tabs = spec.tabs || [];
if (!Object.keys(kinds).length) fail('spec.kinds is empty');
if (!tabs.length) fail('spec.tabs is empty');

for (const [id, n] of Object.entries(nodes)) {
  if (!n.label) fail(`node ${id}: label missing`);
  if (!(n.kind in kinds)) fail(`node ${id}: kind "${n.kind}" is not in spec.kinds`);
  if (!STATUSES.includes(n.status)) fail(`node ${id}: status "${n.status}" is not one of ${STATUSES.join(', ')}`);
}
for (const t of tabs) {
  const ids = (t.rows || []).flat();
  const seen = new Set();
  for (const id of ids) {
    if (!(id in nodes)) fail(`tab ${t.name}: row node "${id}" is not in spec.nodes`);
    if (seen.has(id)) fail(`tab ${t.name}: node "${id}" occurs in more than one row`);
    seen.add(id);
  }
  for (const [i, e] of (t.edges || []).entries()) {
    const where = `tab ${t.name} edge ${i} (${e.from} → ${e.to})`;
    if (!seen.has(e.from) || !seen.has(e.to)) fail(`${where}: both ends must be in this tab's rows`);
    if (!(e.type in edgeTypes)) fail(`${where}: type "${e.type}" is not in spec.edgeTypes`);
    if (!e.sites) fail(`${where}: sites missing`);
  }
}

const tracked = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'], { cwd: root, maxBuffer: 1 << 28 })
  .toString().split('\n').filter(Boolean);
const cache = {};
const read = f => (cache[f] ??= fs.readFileSync(path.join(root, f), 'utf8').split('\n'));
// A path is repo-relative, or a file name (or path tail) that matches exactly one file in the repository.
function resolve(name) {
  if (fs.existsSync(path.join(root, name)) && fs.statSync(path.join(root, name)).isFile()) return name;
  const hits = tracked.filter(f => f === name || f.endsWith('/' + name));
  if (hits.length === 1) return hits[0];
  throw new Error(`"${name}" matches ${hits.length} files${hits.length ? ': ' + hits.slice(0, 5).join(', ') : ''}. Use a longer path.`);
}

const strip = s => s
  .replace(/"(?:[^"\\]|\\.)*"/g, '""')
  .replace(/'(?:[^'\\]|\\.)*'/g, "''")
  .replace(/`(?:[^`\\]|\\.)*`/g, '``')
  .replace(/\/\/.*$/, '')
  .replace(/(^|\s)#\s.*$/, '$1');
const bal = s => { const t = strip(s); return (t.match(/[({[]/g) || []).length - (t.match(/[)}\]]/g) || []).length; };
const indentOf = l => l.match(/^\s*/)[0].length;
const OPENER = /(\{|->|=>|:)\s*$/, LAMBDA_HEAD = /\{[^{}]*(->|=>)\s*$/;
// Call site: one statement. A line that opens a block or lambda ('{', '{ x ->', '=>', ':') with balanced brackets before it stays a single line.
function stmt(lines, i, max = 7) {
  const out = [i];
  const head = strip(lines[i]);
  if (OPENER.test(head) && bal(head.replace(LAMBDA_HEAD, '').replace(OPENER, '')) <= 0) return out;
  let b = bal(lines[i]);
  while (b > 0 && out.length < max && i + out.length < lines.length) { const k = i + out.length; out.push(k); b += bal(lines[k]); }
  out.more = b > 0;
  return out;
}
// Declaration header: up to the line that opens the body or closes the parameter list.
function decl(lines, i, max = 9) {
  const out = []; let b = 0;
  for (let k = i; k < lines.length && out.length < max; k++) {
    out.push(k); b += bal(lines[k].replace(/\{\s*$/, ''));
    if (b <= 0 && !/[,(<]\s*$/.test(strip(lines[k]))) break;
  }
  return out;
}

// Body detection works on bracket depth, line continuation, and indentation, so it needs no parser for a language.
const COMMENT = /^\s*(\/\/|\/\*|\*|#|@|--)/;
const CONTROL = /^\s*(?:\}\s*)?(?:if|else|elif|for|foreach|while|until|unless|loop|do|switch|when|match|case|select|try|catch|except|finally|with|guard|return|throw|raise|new|await|yield|go|defer|assert|del|print|echo|not|in|is|lambda)\b/;
const TYPE_HEAD = [
  /^\s*(?:[\w()]+\s+)*(?:class|object|interface|struct|enum|trait|protocol|record|impl|extension|module|namespace|union)\b/,
  /^\s*(?:export\s+)?type\s+[A-Za-z_]\w*/,
];
const FUNC_HEAD = [
  /\b(?:fun|func|function|def|fn|sub)\b\s*[\w<(`$*]/,
  /^\s*(?:[\w<>[\],.?]+\s+)+[A-Za-z_$][\w$]*\s*\(/,
  /\b(?:const|let|var|val)\s+[A-Za-z_$][\w$]*\s*(?::[^=]+)?=\s*(?:async\s*)?(?:\(\s*$|function\b|(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*(?::[^=]+)?=>)/,
  /^\s*(?:(?:public|private|protected|internal|static|override|convenience|required)\s+)*(?:init|deinit|constructor|static)\b\s*[?!]?\s*[({]/,
];
const isTypeHeader = l => !COMMENT.test(l) && TYPE_HEAD.some(r => r.test(strip(l)));
const isFunctionHeader = l => !COMMENT.test(l) && !CONTROL.test(l) && !isTypeHeader(l) && FUNC_HEAD.some(r => r.test(strip(l)));
const CONT_END = /(=|,|\(|\[|\{|\.|&&|\|\||\+|->|=>|:)$/, CONT_START = /^\s*(\.(?!\.)|\?\.|\?:|\?\?|&&|\|\||\+(?!\+)|->|=>|:(?!:))/;
const nextCode = (lines, k) => { for (let j = k + 1; j < lines.length; j++) if (lines[j].trim()) return j; return -1; };
// Lines of the declaration or statement that starts at index s: until brackets balance and the statement does not continue.
// A header that ends with ':' and is followed by deeper lines owns an indented block (Python, YAML-like code).
function extent(lines, s) {
  let depth = 0; const base = indentOf(lines[s]);
  for (let k = s; k < lines.length; k++) {
    for (const ch of strip(lines[k])) {
      if ('({['.includes(ch)) depth++;
      else if (')}]'.includes(ch) && --depth < 0) return [s, Math.max(s, k - 1)];
    }
    if (depth > 0) continue;
    const tail = strip(lines[k]).trimEnd(), j = nextCode(lines, k);
    if (/:$/.test(tail) && j > 0 && indentOf(lines[j]) > base) {
      let end = k;
      for (let m = j; m < lines.length; m++) { if (!lines[m].trim()) continue; if (indentOf(lines[m]) <= base) break; end = m; }
      return [s, end];
    }
    if (CONT_END.test(tail) || (j > 0 && CONT_START.test(lines[j]))) continue;
    return [s, k];
  }
  return [s, lines.length - 1];
}
// The innermost function around line i. Without one, the outermost declaration below the enclosing type (a property initializer).
// A type body is never a holder.
function holder(lines, i) {
  if (isFunctionHeader(lines[i])) return { kind: 'f', range: extent(lines, i) };
  let ind = indentOf(lines[i]), member = null;
  for (let s = i - 1; s >= 0; s--) {
    const l = lines[s];
    if (!l.trim() || COMMENT.test(l)) continue;
    const li = indentOf(l);
    if (li >= ind) continue;
    if (isTypeHeader(l)) break;
    // A line that ends before i (a sibling, or the closing line of a multi-line header) does not narrow the search.
    const r = extent(lines, s);
    if (r[1] < i) continue;
    ind = li;
    if (isFunctionHeader(l)) return { kind: 'f', range: r };
    member = r;
  }
  if (!member && isTypeHeader(lines[i])) return null;
  return { kind: 'd', range: member || extent(lines, i) };
}
function declBody(lines, first, last) {
  const s = Array.from({ length: last - first + 1 }, (_, j) => first + j).find(k => isFunctionHeader(lines[k]) || isTypeHeader(lines[k]));
  if (s === undefined) return { kind: 'd', range: extent(lines, first) };
  if (isTypeHeader(lines[s])) return null;
  return { kind: 'f', range: extent(lines, s) };
}

// ref is "path:spec"; spec is a comma list of parts. A part is "n" (heuristic range from line n) or "a-b" (explicit range),
// optionally followed by "@c-d" to set the holding function's lines.
function take(ref, single, findBody) {
  const i = ref.lastIndexOf(':');
  if (i < 0) throw new Error(`"${ref}" has no ":lines" part`);
  const file = resolve(ref.slice(0, i)), spec = ref.slice(i + 1), lines = read(file);
  const range = (part, text) => {
    if (/^\d+-\d+$/.test(part)) { const [a, b] = part.split('-').map(Number); return Array.from({ length: b - a + 1 }, (_, j) => a - 1 + j); }
    if (/^\d+$/.test(part) && single) return single(lines, +part - 1);
    throw new Error(`"${ref}": "${text}" is not a line number or a range`);
  };
  return spec.split(',').map(part => {
    const [snip, bodySpec] = part.split('@');
    const idx = range(snip, part);
    if (idx.length === 0 || idx[0] < 0 || idx[idx.length - 1] >= lines.length) throw new Error(`"${ref}": line out of range (file has ${lines.length} lines)`);
    const first = idx[0], last = idx[idx.length - 1];
    let body = null;
    if (bodySpec !== undefined) {
      const b = range(bodySpec, part);
      if (b[0] < 0 || b[b.length - 1] >= lines.length) throw new Error(`"${ref}": body out of range`);
      if (b[0] > first || b[b.length - 1] < last) throw new Error(`"${ref}": body ${bodySpec} does not contain the snippet`);
      body = { kind: 'f', range: [b[0], b[b.length - 1]], given: true };
    } else body = findBody(lines, first, last);
    if (body) body.range = [Math.min(body.range[0], first), Math.max(body.range[1], last)];
    if (body && body.range[0] >= first && body.range[1] <= last) body = null;
    return { file, first: first + 1, last: last + 1, more: !!idx.more, body: body && { kind: body.kind, first: body.range[0] + 1, last: body.range[1] + 1, given: !!body.given } };
  });
}

const fileList = [], fi = f => { let k = fileList.indexOf(f); if (k < 0) { k = fileList.length; fileList.push(f); } return k; };
const used = {};
const use = (f, a, b) => { const s = (used[f] ??= new Set()); for (let k = a; k <= b; k++) s.add(k); };
const pack = s => {
  use(s.file, s.first, s.last);
  if (s.body) use(s.file, s.body.first, s.body.last);
  return [fi(s.file), s.first, s.last, s.more ? 1 : 0, s.body ? s.body.first : 0, s.body ? s.body.last : 0, s.body ? s.body.kind : ''];
};
const snippets = { decl: {}, call: {} }, review = [];
const BODY_NAME = { f: 'function', d: 'declaration' };
const show = parts => parts.flatMap(s => {
  const lines = read(s.file), out = [];
  for (let n = s.first; n <= s.last; n++) out.push(`  ${s.file}:${n}: ${lines[n - 1].trim()}`);
  if (s.more) out.push('  … statement continues');
  if (!s.body) out.push('  body: none');
  else {
    const size = s.body.last - s.body.first + 1;
    out.push(`  body: ${BODY_NAME[s.body.kind]}${s.body.given ? ' (given)' : ''} ${s.body.first}-${s.body.last} (${size} lines)${size > LONG_BODY ? ' WARN long body, check the range' : ''}`,
      `    first ${s.body.first}: ${lines[s.body.first - 1].trim()}`, `    last  ${s.body.last}: ${lines[s.body.last - 1].trim()}`);
  }
  return out;
});
for (const [id, n] of Object.entries(nodes)) {
  if (!n.decl) continue;
  try {
    const parts = take(n.decl, decl, (lines, a, b) => declBody(lines, a, b));
    snippets.decl[id] = parts.map(pack);
    review.push(`DECL ${id} [${n.label.replace(/\n/g, '')}]`, ...show(parts));
  } catch (err) { fail(`node ${id}: ${err.message}`); }
}
for (const t of tabs) for (const e of t.edges || []) {
  if (!e.sites || snippets.call[e.sites]) continue;
  try {
    const parts = e.sites.split('|').flatMap(ref => take(ref, stmt, (lines, a) => holder(lines, a)));
    snippets.call[e.sites] = parts.map(pack);
    review.push(`CALL ${e.from} -> ${e.to} [${edgeTypes[e.type]?.label}${e.note ? ' · ' + e.note : ''}]`, ...show(parts));
  } catch (err) { fail(`tab ${t.name} edge ${e.from} → ${e.to}: ${err.message}`); }
}
if (errors.length) { console.error(errors.map(m => 'ERROR ' + m).join('\n')); process.exit(1); }

// Source lines are stored once per file as runs [firstLine, [texts]], then gzip-compressed and base64-encoded,
// so that whole function bodies fit in one page.
const store = {};
for (const [f, set] of Object.entries(used)) {
  const runs = [], ns = [...set].sort((a, b) => a - b), lines = read(f);
  for (const n of ns) { const r = runs[runs.length - 1]; if (r && r[0] + r[1].length === n) r[1].push(lines[n - 1]); else runs.push([n, [lines[n - 1]]]); }
  store[fi(f)] = runs;
}
const code = zlib.gzipSync(Buffer.from(JSON.stringify(store), 'utf8'), { level: 9 }).toString('base64');
const data = {
  title: spec.title || 'Call graph review', base: spec.base || '', kinds, edgeTypes,
  nodes: Object.fromEntries(Object.entries(nodes).map(([id, n]) => [id, { label: n.label, kind: n.kind, status: n.status, note: n.note || '', symbols: n.symbols || [] }])),
  tabs: tabs.map(t => ({ name: t.name, caption: t.caption || '', rows: t.rows, rowLabels: t.rowLabels || [], edges: t.edges.map(e => ({ from: e.from, to: e.to, type: e.type, note: e.note || '', sites: e.sites })) })),
  files: fileList, snippets, code,
};
// '<' is escaped so no text can close the script element.
const text = JSON.stringify(data).replace(/</g, '\\u003c');
const template = fs.readFileSync(new URL('../assets/template.html', import.meta.url), 'utf8');
const escHtml = s => s.replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]);
const out = template.replace('/*GRAPH_DATA*/null', () => text).replace('<title>Call graph review</title>', () => `<title>${escHtml(data.title)}</title>`);
if (out === template) throw new Error('template placeholder missing');
fs.writeFileSync(outPath, out);
if (reviewPath) fs.writeFileSync(reviewPath, review.join('\n') + '\n');
const all = [...Object.values(snippets.decl), ...Object.values(snippets.call)].flat();
const nodeCount = new Set(tabs.flatMap(t => t.rows.flat())).size, edgeCount = tabs.reduce((s, t) => s + t.edges.length, 0);
const lineCount = Object.values(used).reduce((s, set) => s + set.size, 0);
console.log(`tabs=${tabs.length} nodes=${nodeCount} edges=${edgeCount} decl=${Object.keys(snippets.decl).length} call=${Object.keys(snippets.call).length} bodies=${all.filter(p => p[4]).length}/${all.length} lines=${lineCount} chars=${out.length}`);
if (out.length > RENDER_LIMIT) console.error(`WARN page has ${out.length} characters. An inline render accepts at most ${RENDER_LIMIT}. Split the tabs into two specs.`);
