import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { after, test } from 'node:test';

// Load the released plugin itself. Only its filesystem and process transport
// are mocked; no RTK or OpenCode process runs in this suite.
const source = readFileSync(new URL('../bootstrap/opencode/plugins/rtk.ts', import.meta.url), 'utf8');
const pluginURL = `data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(source)).toString('base64')}`;
const state = { present: true, capable: true, answer: '{"command":"rtk git status"}', error: null, calls: [] };
globalThis.__rtkPluginTest = {
  existsSync: (path) => state.present && path === '/mock/bin/rtk',
  statSync: () => ({ isDirectory: () => false }),
  execFile: (file, argv, options, callback) => {
    state.calls.push({ file, argv, options });
    const probe = argv.at(-1) === '--help';
    queueMicrotask(() => callback(probe ? (state.capable ? null : new Error('unsupported backend')) : state.error,
      probe ? '' : state.answer));
  },
};
const mocks = {
  'node:fs': 'export const { existsSync, statSync } = globalThis.__rtkPluginTest;',
  'node:child_process': 'export const { execFile } = globalThis.__rtkPluginTest;',
};
const loader = registerHooks({
  resolve(specifier, context, nextResolve) {
    if (context.parentURL === pluginURL && mocks[specifier]) {
      return { url: `data:text/javascript,${encodeURIComponent(mocks[specifier])}`, shortCircuit: true };
    }
    return nextResolve(specifier, context);
  },
});
let module;
try {
  module = await import(pluginURL);
} finally {
  loader.deregister();
}
const plugin = module.default;
const originalPath = process.env.PATH;
const originalDisabled = process.env.RTK_DISABLED;
const originalWarn = console.warn;
after(() => {
  if (originalPath === undefined) delete process.env.PATH;
  else process.env.PATH = originalPath;
  if (originalDisabled === undefined) delete process.env.RTK_DISABLED;
  else process.env.RTK_DISABLED = originalDisabled;
  console.warn = originalWarn;
  delete globalThis.__rtkPluginTest;
});

function reset() {
  module._resetCachedRtkPath?.();
  Object.assign(state, { present: true, capable: true, answer: '{"command":"rtk git status"}', error: null, calls: [] });
  process.env.PATH = '/mock/bin';
  delete process.env.RTK_DISABLED;
  console.warn = () => {};
}

async function setup() {
  const registrations = [];
  await plugin.setup({ tool: { hook: async (name, callback) => registrations.push({ name, callback }) } });
  return registrations;
}

// Exposes the legacy callable export that the V2 object schema rejects.
test('default export uses the V2 object schema', () => {
  assert.equal(typeof plugin, 'object');
  assert.notEqual(plugin, null);
  assert.equal(plugin.id, 'rtk');
  assert.equal(typeof plugin.setup, 'function');
  assert.equal(typeof plugin.server, 'function');
  assert.equal(module.RtkOpenCodePlugin, plugin);
});

// Exposes wrong backend selection, missing agent forwarding, and lost mutation.
test('V2 hook rewrites bash and shell input without replacing the event', async () => {
  reset();
  const registrations = await setup();
  assert.equal(registrations.length, 1);
  assert.equal(registrations[0].name, 'execute.before');
  assert.deepEqual(state.calls[0], {
    file: '/mock/bin/rtk', argv: ['hook', 'opencode', '--help'],
    options: { encoding: 'utf8', timeout: 3000, windowsHide: true },
  });
  for (const tool of ['bash', 'shell', 'BASH']) {
    state.answer = ' {"command":"  rtk git status  "} ';
    const input = { command: 'git status', description: 'unchanged' };
    const event = { tool, input, agent: 'build', sessionID: 'session', id: 'call' };
    const before = structuredClone(event);
    await registrations[0].callback(event);
    assert.equal(event.input, input);
    assert.deepEqual(event, { ...before, input: { command: 'rtk git status', description: 'unchanged' } });
    assert.deepEqual(state.calls.at(-1).argv, ['hook', 'opencode', '--agent', 'build', 'git status']);
  }
});

// Exposes registration when no usable RTK backend exists.
test('missing binary and missing hook backend register no hooks', async () => {
  reset();
  state.present = false;
  assert.deepEqual(await setup(), []);
  assert.deepEqual(state.calls, []);
  reset();
  state.capable = false;
  assert.deepEqual(await setup(), []);
  assert.deepEqual(state.calls.map((call) => call.argv), [['hook', 'opencode', '--help']]);
});

// Exposes overwriting commands with empty, invalid, unchanged, or failed answers.
test('unusable answers and process failures pass through unchanged', async () => {
  reset();
  const [{ callback }] = await setup();
  for (const answer of ['{}', '', 'not JSON', 'null', '{"command":42}', '{"command":" "}', '{"command":"git status"}']) {
    state.answer = answer;
    const event = { tool: 'bash', input: { command: 'git status' } };
    await callback(event);
    assert.deepEqual(event, { tool: 'bash', input: { command: 'git status' } });
  }
  for (const message of ['non-zero exit', 'timeout', 'spawn failure']) {
    state.answer = '{"command":"rtk git status"}';
    state.error = new Error(message);
    const event = { tool: 'shell', input: { command: 'git status' } };
    await callback(event);
    assert.equal(event.input.command, 'git status');
  }
});

// Exposes sending unsupported tools, invalid input, or disabled calls to RTK.
test('unsupported tools, invalid input, and RTK_DISABLED do not invoke the backend', async () => {
  reset();
  const [{ callback }] = await setup();
  state.calls = [];
  for (const event of [
    { tool: 'read', input: { command: 'git status' } },
    { tool: 'bash', input: null },
    { tool: 'bash', input: {} },
    { tool: 'bash', input: { command: 42 } },
    { tool: 'bash', input: { command: '  ' } },
    {},
  ]) {
    const before = structuredClone(event);
    await callback(event);
    assert.deepEqual(event, before);
  }
  process.env.RTK_DISABLED = '1';
  const event = { tool: 'bash', input: { command: 'git status' } };
  await callback(event);
  assert.equal(event.input.command, 'git status');
  assert.deepEqual(state.calls, []);
});

// Exposes invented agent values and capability probes repeated per setup.
test('setup caches a successful probe and omits a non-string agent', async () => {
  reset();
  const [{ callback }] = await setup();
  await setup();
  assert.equal(state.calls.length, 1);
  const event = { tool: 'bash', agent: 42, input: { command: 'git status' } };
  await callback(event);
  assert.equal(event.input.command, 'rtk git status');
  assert.deepEqual(state.calls.at(-1).argv, ['hook', 'opencode', 'git status']);
});

// Exposes breaking the official V1 compatibility entrypoint while adopting V2.
test('server hook mutates V1 output.args and does not forward an agent', async () => {
  reset();
  const hooks = await plugin.server();
  const args = { command: 'git status', description: 'unchanged' };
  await hooks['tool.execute.before']({ tool: 'bash', agent: 'build' }, { args });
  assert.deepEqual(args, { command: 'rtk git status', description: 'unchanged' });
  assert.deepEqual(state.calls.at(-1).argv, ['hook', 'opencode', 'git status']);
});
