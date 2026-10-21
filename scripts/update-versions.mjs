import { readFile, writeFile, appendFile, mkdtemp } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { pathToFileURL } from 'node:url';

const packages = [
  { name: '@opencode/cli', arg: 'OPENCODE_VERSION', label: 'OpenCode', repo: 'anomalyco/opencode' },
  { name: '@openchamber/web', arg: 'OPENCHAMBER_VERSION', label: 'OpenChamber', repo: 'openchamber/openchamber' },
];

export function isUpdateDay(date = new Date(), event = 'schedule') {
  if (event === 'workflow_dispatch') return true;
  if (event !== 'schedule') throw new Error('Unsupported workflow event.');
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/Los_Angeles', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(date).map(({ type, value }) => [type, value]));
  const day = Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day)) / 86400000;
  return (day - Date.UTC(2026, 9, 21) / 86400000) % 2 === 0;
}

function stable(version) {
  if (typeof version !== 'string' || !/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version)) {
    throw new Error('Expected an exact stable version.');
  }
  return version.split('.').map(BigInt);
}

function compare(a, b) {
  const left = stable(a);
  const right = stable(b);
  for (let i = 0; i < 3; i++) {
    if (left[i] !== right[i]) return left[i] > right[i] ? 1 : -1;
  }
  return 0;
}

function one(text, pattern, description) {
  const matches = [...text.matchAll(pattern)];
  if (matches.length !== 1) throw new Error(`Unexpected pin occurrences: ${description}.`);
  return matches[0];
}

async function request(fetchImpl, url, allowMissing = false, token) {
  let response;
  try {
    response = await fetchImpl(url, {
      signal: AbortSignal.timeout(20000),
      headers: { Accept: 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    });
  } catch {
    throw new Error(`Request failed or timed out: ${new URL(url).hostname}.`);
  }
  if (allowMissing && response.status === 404) return null;
  if (!response.ok) throw new Error(`HTTP ${response.status} from ${new URL(url).hostname}.`);
  try {
    return await response.json();
  } catch {
    throw new Error(`Invalid JSON from ${new URL(url).hostname}.`);
  }
}

export async function updateVersions({ root, fetchImpl = fetch, now = new Date(), event = 'schedule', token } = {}) {
  if (!isUpdateDay(now, event)) return { changed: false, message: '' };
  const dockerPath = join(root, 'Dockerfile');
  const readmePath = join(root, 'README.md');
  let docker = await readFile(dockerPath, 'utf8');
  let readme = await readFile(readmePath, 'utf8');
  const changes = [];
  // Validate every local and remote pin before changing either file.
  for (const pkg of packages) {
    const pattern = new RegExp(`^ARG ${pkg.arg}=([^\\r\\n]+)$`, 'gm');
    const old = one(docker, pattern, `Dockerfile ${pkg.arg}`)[1];
    stable(old);
    if ([...docker.matchAll(new RegExp(`\\bARG\\s+${pkg.arg}\\b`, 'g'))].length !== 1) {
      throw new Error(`Unexpected pin occurrences: ${pkg.arg}.`);
    }
    const documented = one(readme, pattern, `README ${pkg.arg}`)[1];
    const prosePattern = new RegExp(`\\b${pkg.label} ([0-9]+\\.[0-9]+\\.[0-9]+)(?=[\\s,;]|\\.(?:\\s|$)|$)`, 'g');
    const prose = one(readme, prosePattern, `README ${pkg.label}`)[1];
    if (documented !== old || prose !== old) throw new Error(`Pin mismatch: ${pkg.name}.`);
    if ([...readme.matchAll(new RegExp(`\\bARG\\s+${pkg.arg}\\b`, 'g'))].length !== 1) {
      throw new Error(`Unexpected pin occurrences: README ${pkg.arg}.`);
    }
    const metadata = await request(fetchImpl, `https://registry.npmjs.org/${encodeURIComponent(pkg.name)}/latest`);
    const latest = metadata?.version;
    const direction = compare(latest, old);
    if (direction < 0) throw new Error(`Refusing downgrade: ${pkg.name}.`);
    if (direction > 0) changes.push({ ...pkg, old, latest, pattern, prosePattern });
  }
  if (!changes.length) return { changed: false, message: '' };
  const notes = [];
  for (const pkg of changes) {
    const release = await request(fetchImpl,
      `https://api.github.com/repos/${pkg.repo}/releases/tags/v${pkg.latest}`, true, token);
    if (release && (release.tag_name !== `v${pkg.latest}` || release.draft || release.prerelease)) {
      throw new Error(`Unexpected release metadata: ${pkg.name}.`);
    }
    const body = typeof release?.body === 'string' ? release.body.trim() : '';
    const available = body.replace(/\s/g, '').length >= 80 && !/^(no (release )?notes|tbd|coming soon|full changelog:)/i.test(body);
    const releaseLink = `https://github.com/${pkg.repo}/releases/tag/v${pkg.latest}`;
    notes.push(`${pkg.name}: ${pkg.old} -> ${pkg.latest}\nRelease: ${releaseLink}`
      + (available ? '\nRelease notes: see the official release.'
        : `\nRelease notes unavailable (missing or minimal). Compare: https://github.com/${pkg.repo}/compare/v${pkg.old}...v${pkg.latest}`));
  }
  for (const pkg of changes) {
    docker = docker.replace(pkg.pattern, `ARG ${pkg.arg}=${pkg.latest}`);
    readme = readme.replace(pkg.pattern, `ARG ${pkg.arg}=${pkg.latest}`)
      .replace(pkg.prosePattern, `${pkg.label} ${pkg.latest}`);
  }
  const message = `chore: update ${changes.map(pkg => `${pkg.name} ${pkg.old} -> ${pkg.latest}`).join(', ')}\n\n${notes.join('\n\n')}\n`;
  await writeFile(dockerPath, docker);
  await writeFile(readmePath, readme);
  return { changed: true, message };
}

async function main() {
  const root = resolve('.');
  const result = await updateVersions({ root, event: process.env.GITHUB_EVENT_NAME, token: process.env.GITHUB_TOKEN });
  let output = `changed=${result.changed}\n`;
  if (result.changed) {
    const directory = await mkdtemp(join(process.env.RUNNER_TEMP || tmpdir(), 'version-update-'));
    const path = join(directory, 'commit-message.txt');
    if (path.startsWith(`${root}/`) || /[\r\n]/.test(path)) throw new Error('Unsafe commit message path.');
    await writeFile(path, result.message, { mode: 0o600 });
    output += `message_path=${path}\n`;
  }
  if (process.env.GITHUB_OUTPUT) await appendFile(process.env.GITHUB_OUTPUT, output);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(error => {
    // Request errors contain only trusted host names and status codes, never response bodies or tokens.
    process.exitCode = 1;
    console.error('Version update failed. Registry, release, pin, or output validation failed; no commit is permitted.');
    if (/^HTTP \d+ from (api\.github\.com|registry\.npmjs\.org)\.$/.test(error.message)) console.error(error.message);
  });
}
