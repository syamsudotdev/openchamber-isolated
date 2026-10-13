import net from 'node:net';
import assert from 'node:assert/strict';

const mode = process.argv[2];
assert.ok(['baseline', 'enforced'].includes(mode), 'Use baseline or enforced');

async function bind(host, port) {
  return new Promise((resolve) => {
    const server = net.createServer();
    server.once('error', (error) => resolve(error.code));
    server.listen({ host, port }, () => server.close(() => resolve('SUCCESS')));
  });
}

for (const host of ['127.0.0.1', '0.0.0.0', '::1', '::']) {
  const actual = await bind(host, 5037);
  console.log(`${mode}: TCP ${host}:5037 = ${actual}`);
  if (mode === 'enforced') assert.equal(actual, 'EPERM');
  else assert.ok(['SUCCESS', 'EADDRINUSE'].includes(actual), 'Baseline must not deny the bind');
}
for (const host of ['127.0.0.1', '::1']) {
  const actual = await bind(host, 0);
  console.log(`${mode}: TCP ${host}:0 = ${actual}`);
  assert.equal(actual, 'SUCCESS');
}

// Fixed ADB wire request: four hex length bytes, then the 12-byte host:version.
await new Promise((resolve, reject) => {
  const socket = net.createConnection({ host: '127.0.0.1', port: 5037 });
  let received = Buffer.alloc(0);
  socket.setTimeout(5000, () => socket.destroy(new Error('ADB handshake timed out')));
  socket.on('error', reject);
  socket.once('connect', () => socket.write('000chost:version'));
  socket.on('data', (data) => {
    received = Buffer.concat([received, data]);
    if (received.length < 8) return;
    try {
      assert.equal(received.subarray(0, 4).toString(), 'OKAY');
      const lengthText = received.subarray(4, 8).toString();
      assert.match(lengthText, /^[0-9a-fA-F]{4}$/);
      const length = Number.parseInt(lengthText, 16);
      assert.ok(length > 0 && length <= 1024);
      if (received.length < 8 + length) return;
      assert.match(received.subarray(8, 8 + length).toString(), /^[0-9a-fA-F]+$/);
      console.log(`${mode}: outbound ADB host:version = OKAY`);
      socket.destroy();
      resolve();
    } catch (error) {
      socket.destroy();
      reject(error);
    }
  });
  socket.once('end', () => reject(new Error('ADB closed before a complete reply')));
});
