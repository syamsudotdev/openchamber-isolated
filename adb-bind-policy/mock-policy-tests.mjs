// Local control-flow tests only. No host cgroups, BPF programs, or units are used.
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const directory = fileURLToPath(new URL('.', import.meta.url));
const source = readFileSync(new URL('policy.sh', import.meta.url), 'utf8');
const expected = '/user.slice/user-1000.slice/user@1000.service/openchamber.slice';
const quote = (value) => `'${value.replaceAll("'", "'\\''")}'`;

function scenario(name, fault = false) {
  const work = mkdtempSync(`${directory}.mock-policy-`);
  try {
    const cg = `${work}/cgroup`;
    const pins = `${work}/pins`;
    const state = `${work}/state`;
    const log = `${work}/calls`;
    mkdirSync(cg);
    mkdirSync(pins);
    writeFileSync(`${pins}/deny_bind4`, 'mock pin 101');
    writeFileSync(`${pins}/deny_bind6`, 'mock pin 102');
    writeFileSync(`${work}/object`, 'mock object');
    const populated = ['populated-stop', 'partial-start'].includes(name) ? 1 : 0;
    writeFileSync(`${cg}/cgroup.events`, `populated ${populated}\nfrozen 0\n`);
    if (name === 'missing-events') rmSync(`${cg}/cgroup.events`);
    if (name !== 'unknown-pins') writeFileSync(state, `${expected}\n42\n101\n102\n`, { mode: 0o600 });
    let script = source
      .replace('[[ $EUID == 0 ]]', '[[ 1 == 1 ]]')
      .replace('readonly cg=/sys/fs/cgroup$expected', `readonly cg=${quote(cg)}`)
      .replace('readonly pins=/sys/fs/bpf/openchamber-bind-policy', `readonly pins=${quote(pins)}`)
      .replace('readonly state=/run/openchamber-bind-policy.state', `readonly state=${quote(state)}`)
      .replace('readonly object=/etc/openchamber-bind-policy/deny5037.o', `readonly object=${quote(`${work}/object`)}`)
      .replace('mktemp /run/openchamber-bind-policy.state.XXXXXX', `mktemp ${quote(`${work}/state.XXXXXX`)}`);
    if (fault && name === 'populated-stop') {
      script = script.replace(/^[ \t]*empty_slice \|\|.*$/gm, '    : # representative missing populated gates');
    }
    if (fault && name === 'lookup-failure') {
      script = script.replace('listing=$(bpftool cgroup show "$cg") || return 2', 'listing=$(bpftool cgroup show "$cg") || return 1');
    }
    if (fault && name === 'unknown-pins') {
      script = script.replace('        read_identity\n    else', '        id4=101; id6=102\n    else');
    }
    if (fault && name === 'empty-success-start') {
      script = script.replace('    [[ -z ${listing//[[:space:]]/} ]] && return 1\n', '');
    }
    // All host-inspection commands are intercepted. Mutation commands can only
    // reach the rewritten temporary paths. The helper never loads programs here.
    const mocks = `
id() { printf '1000\\n'; }
stat() {
  case "$*" in
    '-f -c %T /sys/fs/cgroup') echo cgroup2fs;;
    '-f -c %T /sys/fs/bpf') echo bpf_fs;;
    '-c %u '*) echo 0;;
    '-c %i '*) echo 42;;
    '-c %a '*'/pins') echo 700;;
    '-c %a '*'/state') echo 600;;
    '-c %a '*) echo 755;;
    *) return 2;;
  esac
}
readlink() { printf '%s\\n' "$2"; }
runuser() { [[ "$*" != *' show '* ]] || echo ${quote(expected)}; return 0; }
mock_bind4=no
mock_bind6=no
bpftool() {
  printf '%s\\n' "$*" >> ${quote(log)}
  if [[ "$1 $2" == 'prog show' ]]; then
    [[ "$*" == *deny_bind4 ]] && echo '101: cgroup_sock_addr name deny_bind4' || echo '102: cgroup_sock_addr name deny_bind6'
  elif [[ "$1 $2" == 'cgroup show' ]]; then
    [[ ${quote(name)} != lookup-failure ]] || return 2
    if [[ ${quote(name)} == empty-success-start && $mock_bind4 == no && $mock_bind6 == no ]]; then
      return 0
    fi
    echo 'ID AttachType AttachFlags Name'
    if [[ ${quote(name)} == empty-success-start ]]; then
      [[ $mock_bind4 != yes ]] || echo '101 bind4 multi deny_bind4'
      [[ $mock_bind6 != yes ]] || echo '102 bind6 multi deny_bind6'
    fi
    if [[ ${quote(name)} == populated-stop || ${quote(name)} == missing-events || ${quote(name)} == detach-failure ]]; then
      echo '101 bind4 multi deny_bind4'
      echo '102 bind6 multi deny_bind6'
    fi
  elif [[ "$1 $2" == 'cgroup attach' ]]; then
    [[ ${quote(name)} != partial-start || "$4" != bind6 ]] || return 1
    if [[ "$4" == bind4 ]]; then mock_bind4=yes; else mock_bind6=yes; fi
  elif [[ "$1 $2" == 'cgroup detach' ]]; then
    [[ ${quote(name)} != detach-failure ]] || return 1
  else
    return 2
  fi
}
`;
    // Keep real root_only_writable function syntax in view, but replace its body
    // for these unprivileged fixtures, which do not claim root ownership evidence.
    script = script.replace(/root_only_writable\(\) \{[\s\S]*?\n\}/, 'root_only_writable() { return 0; }');
    const file = `${work}/helper.sh`;
    writeFileSync(file, mocks + script);
    const action = ['populated-stop', 'missing-events', 'detach-failure'].includes(name) ? 'stop' : 'start';
    const result = spawnSync('bash', [file, action], { encoding: 'utf8' });
    const calls = existsSync(log) ? readFileSync(log, 'utf8') : '';
    if (name === 'partial-start') {
      assert.ok(calls.includes(`cgroup attach ${cg} bind4`), 'Partial start must reach bind4 attachment');
      assert.ok(calls.includes(`cgroup attach ${cg} bind6`), 'Partial start must reach bind6 failure');
      assert.ok(result.stderr.includes('Partial-start rollback failed or was unsafe'), 'Partial start must report retained protection');
    }
    if (name === 'detach-failure') {
      assert.ok(calls.includes(`cgroup detach ${cg} bind4`), 'Cleanup must reach the simulated detach failure');
      assert.ok(!calls.includes(`cgroup detach ${cg} bind6`), 'Cleanup must stop after the first detach failure');
    }
    if (name === 'empty-success-start') {
      assert.equal(result.status, 0, `${name}: startup must accept successful empty inspection: ${result.stderr}`);
      assert.ok(calls.includes(`cgroup attach ${cg} bind4`), 'Empty inspection must permit bind4 attachment');
      assert.ok(calls.includes(`cgroup attach ${cg} bind6`), 'Startup must attach bind6');
      assert.ok(!calls.includes('cgroup detach'), 'Successful startup must not roll back attachments');
    } else {
      assert.notEqual(result.status, 0, `${name}: unsafe operation must fail`);
    }
    assert.ok(existsSync(`${pins}/deny_bind4`) && existsSync(`${pins}/deny_bind6`), `${name}: retain pins`);
    if (name !== 'unknown-pins') assert.ok(existsSync(state), `${name}: retain identity`);
    else assert.ok(!existsSync(state), 'Unknown pins must not receive an adopted identity');
    if (['populated-stop', 'missing-events', 'partial-start'].includes(name)) {
      assert.ok(!calls.includes('cgroup detach'), `${name}: no detach without proven empty slice`);
    }
    if (['lookup-failure', 'unknown-pins'].includes(name)) {
      assert.ok(!calls.includes('cgroup attach'), `${name}: no attach after failed inspection or identity check`);
    }
  } finally {
    rmSync(work, { recursive: true });
  }
}

for (const name of ['populated-stop', 'lookup-failure', 'unknown-pins', 'empty-success-start']) {
  assert.throws(() => scenario(name, true), assert.AssertionError, `${name}: test must expose representative fault`);
  console.log(`Detected representative fault: ${name}`);
}
for (const name of ['populated-stop', 'missing-events', 'lookup-failure', 'unknown-pins', 'partial-start', 'detach-failure', 'empty-success-start']) {
  scenario(name);
  console.log(`Passed: ${name}`);
}
