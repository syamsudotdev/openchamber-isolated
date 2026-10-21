import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { isUpdateDay, updateVersions } from '../scripts/update-versions.mjs';

const docker = 'ARG OPENCODE_VERSION=2.0.32\nARG OPENCHAMBER_VERSION=2.4.0\n';
const readme = `The image pins OpenChamber 2.4.0 and OpenCode 2.0.32. The build requires Node.\n${docker}`;
const release = version => ({ tag_name: `v${version}`, body: 'These official release notes describe the published application changes in sufficient detail for readers to inspect upstream.' });

async function fixture(t, options = {}) {
  const root = await mkdtemp(join(tmpdir(), 'update-versions-test-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await writeFile(join(root, 'Dockerfile'), options.docker ?? docker);
  await writeFile(join(root, 'README.md'), options.readme ?? readme);
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push(url);
    assert.ok(init.signal instanceof AbortSignal);
    assert.equal(init.headers.Authorization, url.includes('api.github.com') ? 'Bearer fixture-token' : undefined);
    let value;
    if (url.includes('registry.npmjs.org')) {
      const index = url.includes('opencode') ? 0 : 1;
      value = { version: (options.versions ?? ['2.0.33', '2.4.1'])[index] };
    } else {
      const version = url.split('/v').at(-1);
      value = options.release === undefined ? release(version) : options.release;
    }
    if (options.fetch) return options.fetch(url, value);
    return { ok: true, status: 200, json: async () => value };
  };
  return {
    root, calls,
    run: (extra = {}) => updateVersions({ root, fetchImpl, event: 'workflow_dispatch', token: 'fixture-token', ...extra }),
    contents: async () => Promise.all(['Dockerfile', 'README.md'].map(file => readFile(join(root, file), 'utf8'))),
  };
}

test('updates both pins and both documentation references with official links', async t => {
  const f = await fixture(t);
  const result = await f.run();
  assert.equal(result.changed, true);
  assert.deepEqual(await f.contents(), [docker.replace('2.0.32', '2.0.33').replace('2.4.0', '2.4.1'), readme.replaceAll('2.0.32', '2.0.33').replaceAll('2.4.0', '2.4.1')]);
  assert.match(result.message, /@opencode\/cli 2\.0\.32 -> 2\.0\.33/);
  assert.match(result.message, /https:\/\/github.com\/anomalyco\/opencode\/releases\/tag\/v2.0.33/);
  assert.match(result.message, /https:\/\/github.com\/openchamber\/openchamber\/releases\/tag\/v2.4.1/);
  assert.doesNotMatch(result.message, /unavailable|Compare:/);
});

for (const versions of [['2.0.33', '2.4.0'], ['2.0.32', '2.4.1']]) {
  test(`single update ${versions.join('/')}: notes omit unchanged package`, async t => {
    const f = await fixture(t, { versions });
    const result = await f.run();
    const changed = versions[0] === '2.0.33' ? '@opencode/cli' : '@openchamber/web';
    const unchanged = changed === '@opencode/cli' ? '@openchamber/web' : '@opencode/cli';
    assert.ok(result.message.includes(changed));
    assert.ok(!result.message.includes(unchanged));
    assert.equal(f.calls.filter(url => url.includes('api.github.com')).length, 1);
  });
}

test('no-op does not write or request releases', async t => {
  const f = await fixture(t, { versions: ['2.0.32', '2.4.0'] });
  assert.deepEqual(await f.run(), { changed: false, message: '' });
  assert.deepEqual(await f.contents(), [docker, readme]);
  assert.equal(f.calls.length, 2);
});

test('repository pins and documentation satisfy the updater contract', async t => {
  const sourceDocker = await readFile(new URL('../Dockerfile', import.meta.url), 'utf8');
  const sourceReadme = await readFile(new URL('../README.md', import.meta.url), 'utf8');
  const versions = ['OPENCODE_VERSION', 'OPENCHAMBER_VERSION'].map(arg =>
    sourceDocker.match(new RegExp(`^ARG ${arg}=(.+)$`, 'm'))[1]);
  const f = await fixture(t, { docker: sourceDocker, readme: sourceReadme, versions });
  assert.equal((await f.run()).changed, false);
  assert.deepEqual(await f.contents(), [sourceDocker, sourceReadme]);
});

for (const bad of [undefined, null, '', 'latest', '2.4.1-beta.1', 'v2.4.1', '02.4.1', '2.3.9', '2.4.1\ninjected']) {
  test(`rejects second package ${JSON.stringify(bad)} before either write`, async t => {
    const f = await fixture(t, { versions: ['2.0.33', bad] });
    await assert.rejects(f.run(), /stable version|downgrade/);
    assert.deepEqual(await f.contents(), [docker, readme]);
  });
}

for (const options of [
  { docker: `${docker}ARG OPENCODE_VERSION=2.0.32\n` },
  { docker: `${docker}ARG  OPENCODE_VERSION=2.0.32\n` },
  { readme: readme.replace('OpenCode 2.0.32', 'OpenCode 2.0.31') },
  { readme: readme.replace('ARG OPENCHAMBER_VERSION=2.4.0', 'ARG OPENCHAMBER_VERSION=2.3.0') },
  { readme: `${readme}OpenChamber 2.4.0\n` },
]) {
  test(`rejects unexpected pins ${JSON.stringify(options)}`, async t => {
    const f = await fixture(t, options);
    const before = await f.contents();
    await assert.rejects(f.run(), /pin occurrences|Pin mismatch/);
    assert.deepEqual(await f.contents(), before);
  });
}

for (const host of ['registry.npmjs.org', 'api.github.com']) {
  for (const status of [403, 429, 500]) {
    test(`fails closed on ${host} HTTP ${status}`, async t => {
      const f = await fixture(t, { fetch: (url, value) => ({
        ok: !url.includes(host), status: url.includes(host) ? status : 200, json: async () => value,
      }) });
      await assert.rejects(f.run(), new RegExp(`HTTP ${status} from ${host}`));
      assert.deepEqual(await f.contents(), [docker, readme]);
    });
  }
  for (const fault of ['network', 'json']) {
    test(`fails closed on ${host} ${fault}`, async t => {
      const f = await fixture(t, { fetch: (url, value) => {
        if (url.includes(host) && fault === 'network') throw new Error('secret untrusted response');
        return { ok: true, status: 200, json: async () => {
          if (url.includes(host)) throw new Error('secret untrusted response');
          return value;
        } };
      } });
      await assert.rejects(f.run(), /Request failed or timed out|Invalid JSON/);
      assert.deepEqual(await f.contents(), [docker, readme]);
    });
  }
}

for (const body of ['', 'Bug fixes.', 'Full changelog: https://example.test/' + 'a'.repeat(100)]) {
  test(`minimal notes use explicit comparison fallback: ${body.slice(0, 20)}`, async t => {
    const f = await fixture(t, { release: { tag_name: 'v2.0.33', body }, versions: ['2.0.33', '2.4.0'] });
    const { message } = await f.run();
    assert.match(message, /Release notes unavailable/);
    assert.match(message, /https:\/\/github.com\/anomalyco\/opencode\/compare\/v2.0.32\.\.\.v2.0.33/);
    assert.ok(!message.includes('example.test'));
  });
}

test('missing release uses fallback; registry 404 does not', async t => {
  const f = await fixture(t, { fetch: (url, value) => url.includes('api.github.com')
    ? { ok: false, status: 404 } : { ok: true, status: 200, json: async () => value } });
  assert.match((await f.run()).message, /Release notes unavailable/);
  const bad = await fixture(t, { fetch: () => ({ ok: false, status: 404 }) });
  await assert.rejects(bad.run(), /HTTP 404/);
});

test('unexpected release metadata prevents writes', async t => {
  const f = await fixture(t, { release: { tag_name: 'v9.9.9', body: 'x'.repeat(100) } });
  await assert.rejects(f.run(), /Unexpected release metadata/);
  assert.deepEqual(await f.contents(), [docker, readme]);
});

test('calendar parity crosses months, years, DST, and UTC midnight', () => {
  for (const [date, expected] of [
    ['2026-10-21T03:00:00Z', false], ['2026-10-21T20:00:00-07:00', true],
    ['2026-10-22T20:00:00-07:00', false], ['2026-10-31T20:00:00-07:00', true],
    ['2026-11-01T01:30:00-07:00', false], ['2026-11-01T01:30:00-08:00', false],
    ['2026-11-02T20:00:00-08:00', true], ['2026-12-31T20:00:00-08:00', false],
    ['2027-01-01T20:00:00-08:00', true], ['2027-03-13T20:00:00-08:00', false],
    ['2027-03-14T20:00:00-07:00', true], ['2027-03-15T20:00:00-07:00', false],
  ]) assert.equal(isUpdateDay(new Date(date)), expected, date);
  assert.equal(isUpdateDay(new Date('2026-10-22T20:00:00-07:00'), 'workflow_dispatch'), true);
  assert.throws(() => isUpdateDay(new Date(), 'pull_request'), /Unsupported/);
});

test('inactive date skips all file reads and requests', async () => {
  assert.deepEqual(await updateVersions({ root: '/does-not-exist', now: new Date('2026-10-22T20:00:00-07:00') }), { changed: false, message: '' });
});

test('workflow keeps tests/build ahead of commit and rejects moved main', async () => {
  const workflow = await readFile(new URL('../.github/workflows/update-versions.yml', import.meta.url), 'utf8');
  assert.match(workflow, /cron: '0 20 \* \* \*'\n\s+timezone: America\/Los_Angeles/);
  assert.match(workflow, /if: github.ref == 'refs\/heads\/main'/);
  assert.match(workflow, /cancel-in-progress: false/);
  assert.doesNotMatch(workflow, /continue-on-error|always\(|--force|pull_request|secrets\./);
  const commitIndex = workflow.indexOf('git commit -F');
  assert.ok(commitIndex >= 0, 'Commit command must exist.');
  for (const command of ['sh tests/bootstrap.sh', 'sh tests/install-tools.sh', 'sh tests/android-install.sh', 'node --test tests/rtk-plugin.mjs', 'node --test tests/update-versions.mjs', 'docker build --platform linux/amd64']) {
    const commandIndex = workflow.indexOf(command);
    assert.ok(commandIndex >= 0, `Required command must exist: ${command}`);
    assert.ok(commandIndex < commitIndex, `Required command must precede commit: ${command}`);
  }
  assert.equal((workflow.match(/if: steps.versions.outputs.changed == 'true'/g) ?? []).length, 3);
  assert.match(workflow, /git add -- Dockerfile README.md/);
  assert.match(workflow, /test "\$\(git diff --name-only \| LC_ALL=C sort\)" = "\$\(printf 'Dockerfile\\nREADME.md'\)"/);
  assert.match(workflow, /git fetch origin main\n\s+test "\$\(git rev-parse HEAD\)" = "\$\(git rev-parse origin\/main\)"/);
  assert.ok(workflow.indexOf('git fetch origin main') < workflow.indexOf('git commit -F'));
  assert.ok(workflow.indexOf('git commit -F') < workflow.indexOf('git push origin HEAD:main'));
  assert.match(workflow, /run: \|\n\s+set -eu/);
});

for (const scenario of ['success', 'failed validation', 'moved main']) {
  test(`commit shell ${scenario}: push occurs only after all checks pass`, async t => {
    const workflow = await readFile(new URL('../.github/workflows/update-versions.yml', import.meta.url), 'utf8');
    const block = workflow.match(/- name: Commit and push only validated changes[\s\S]*?run: \|\n((?: {10}[^\n]*(?:\n|$))+)/);
    assert.ok(block, 'Commit shell block must exist.');
    const script = block[1].replace(/^ {10}/gm, '');
    const root = await mkdtemp(join(tmpdir(), 'update-commit-test-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    const tracePath = join(root, 'git-trace');
    // Every Git command is stubbed. This fixture cannot contact or push to a remote.
    await writeFile(join(root, 'git'), `#!/bin/sh
set -eu
printf '%s\\n' "$*" >> "$TRACE_PATH"
case "$*" in
  'branch --show-current') printf 'main\\n' ;;
  'ls-files --others --exclude-standard'|'diff --cached --name-only') ;;
  'diff --name-only') printf 'Dockerfile\\nREADME.md\\n' ;;
  'diff --check') test "$SCENARIO" != 'failed validation' ;;
  'fetch origin main') ;;
  'rev-parse HEAD') printf 'original-head\\n' ;;
  'rev-parse origin/main')
    if test "$SCENARIO" = 'moved main'; then printf 'new-head\\n'; else printf 'original-head\\n'; fi ;;
  'config user.name '*|'config user.email '*|'add -- Dockerfile README.md'|'commit -F '*|'push origin HEAD:main') ;;
  *) printf 'Unexpected Git command\\n' >&2; exit 90 ;;
esac
`, { mode: 0o700 });
    const result = spawnSync('bash', ['-e', '-o', 'pipefail', '-c', script], {
      cwd: root, encoding: 'utf8', timeout: 10000,
      env: { ...process.env, PATH: `${root}:${process.env.PATH}`, TRACE_PATH: tracePath,
        SCENARIO: scenario, MESSAGE_PATH: join(root, 'message.txt') },
    });
    assert.ifError(result.error);
    const trace = await readFile(tracePath, 'utf8');
    assert.ok(trace.includes('diff --check\n'), 'Diff validation must execute.');
    if (scenario === 'success') {
      assert.equal(result.status, 0, result.stderr);
      assert.ok(trace.includes('commit -F '), 'Successful checks must permit commit.');
      assert.ok(trace.endsWith('push origin HEAD:main\n'), 'Successful checks must reach the push stub.');
    } else {
      assert.notEqual(result.status, 0, 'A failed check must abort the shell.');
      assert.doesNotMatch(trace, /(?:^|\n)(?:add|commit|push) /, 'A failed check must prevent staging, commit, and push.');
      if (scenario === 'moved main') assert.ok(trace.includes('rev-parse origin/main\n'));
      else assert.ok(!trace.includes('fetch origin main\n'), 'Failed diff validation must stop before fetch.');
    }
  });
}
