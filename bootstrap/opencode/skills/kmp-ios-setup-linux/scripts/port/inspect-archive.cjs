const fs = require('node:fs');
const assert = require('node:assert/strict');

function bounds(buffer, offset, size, label) {
  assert(Number.isSafeInteger(offset) && Number.isSafeInteger(size) && offset >= 0 && size >= 0 && offset <= buffer.length && size <= buffer.length - offset, `${label}: invalid bounds`);
}
function cstring(buffer, offset, limit, label) {
  bounds(buffer, offset, limit - offset, label);
  const end = buffer.indexOf(0, offset);
  assert(end >= offset && end < limit, `${label}: missing string terminator`);
  return buffer.subarray(offset, end).toString('utf8');
}
function field(header, start, end, radix, label) {
  const text = header.subarray(start, end).toString('ascii').trim();
  assert((radix === 8 ? /^[0-7]+$/ : /^[0-9]+$/).test(text), `${label}: invalid numeric field`);
  const result = Number.parseInt(text, radix);
  assert(Number.isSafeInteger(result), `${label}: unsafe numeric field`);
  return result;
}
function inspectObject(data, member = {name: '<object>', payloadOffset: 0, headerOffset: 0}, maximumMinimumOS = 0x00100000) {
  bounds(data, 0, 32, 'Mach-O header');
  assert.equal(data.readUInt32LE(0), 0xfeedfacf, `Unexpected archive payload: ${member.name}; expected Mach-O 64-bit`);
  assert.equal(data.readUInt32LE(4), 0x0100000c, 'Mach-O CPU must be ARM64');
  assert.equal(data.readUInt32LE(8) & 0x00ffffff, 0, 'Mach-O CPU subtype must be baseline ARM64');
  assert.equal(data.readUInt32LE(12), 1, 'Mach-O file type must be MH_OBJECT');
  const commandCount = data.readUInt32LE(16);
  const commandBytes = data.readUInt32LE(20);
  bounds(data, 32, commandBytes, 'Mach-O load commands');
  assert(commandCount <= commandBytes / 8, 'Mach-O command count exceeds command bytes');
  let offset = 32;
  const buildVersions = [];
  const sections = [];
  let symbolTable;
  for (let index = 0; index < commandCount; index++) {
    bounds(data, offset, 8, 'Mach-O load command header');
    const command = data.readUInt32LE(offset);
    const size = data.readUInt32LE(offset + 4);
    assert(size >= 8 && size % 8 === 0 && size <= 32 + commandBytes - offset, 'Mach-O load command has invalid bounds');
    if (command === 0x32) {
      assert(size >= 24, 'LC_BUILD_VERSION is truncated');
      assert.equal(size, 24 + data.readUInt32LE(offset + 20) * 8, 'LC_BUILD_VERSION tool count is invalid');
      const platform = data.readUInt32LE(offset + 8);
      const minimumOS = data.readUInt32LE(offset + 12);
      assert.equal(platform, 2, 'Mach-O build platform must be iOS (2)');
      assert(minimumOS > 0 && minimumOS <= maximumMinimumOS, 'Mach-O minimum OS must be at most app iOS 16.0');
      buildVersions.push({platform, minimumOS, commandArchiveOffset: member.payloadOffset + offset});
    } else if (command === 0x25) {
      // Older device objects use LC_VERSION_MIN_IPHONEOS instead of LC_BUILD_VERSION.
      // ARM64 baseline plus this iPhoneOS command denotes device, not ARM64 simulator.
      assert.equal(size, 16, 'LC_VERSION_MIN_IPHONEOS size is invalid');
      const minimumOS = data.readUInt32LE(offset + 8);
      assert(minimumOS > 0 && minimumOS <= maximumMinimumOS, 'Mach-O minimum OS must be at most app iOS 16.0');
      buildVersions.push({platform: 2, minimumOS, legacy: true, commandArchiveOffset: member.payloadOffset + offset});
    } else if ([0x24, 0x2f, 0x30].includes(command)) {
      assert.fail('Non-iOS legacy deployment command');
    } else if (command === 0x19) {
      assert(size >= 72, 'LC_SEGMENT_64 is truncated');
      const count = data.readUInt32LE(offset + 64);
      assert.equal(size, 72 + count * 80, 'LC_SEGMENT_64 section count is invalid');
      const segmentFileOffset = Number(data.readBigUInt64LE(offset + 40));
      const segmentFileSize = Number(data.readBigUInt64LE(offset + 48));
      bounds(data, segmentFileOffset, segmentFileSize, 'Mach-O segment content');
      for (let section = 0; section < count; section++) {
        const entry = offset + 72 + section * 80;
        const name = data.subarray(entry, entry + 16).toString().replace(/\0.*$/, '');
        const segment = data.subarray(entry + 16, entry + 32).toString().replace(/\0.*$/, '');
        assert(!(segment === '__LLVM' && ['__bitcode', '__bundle'].includes(name)), 'Embedded LLVM bitcode is unsupported');
        const address = data.readBigUInt64LE(entry + 32);
        const bytes = Number(data.readBigUInt64LE(entry + 40));
        const fileOffset = data.readUInt32LE(entry + 48);
        const relocationsOffset = data.readUInt32LE(entry + 56);
        const relocations = data.readUInt32LE(entry + 60);
        const flags = data.readUInt32LE(entry + 64);
        const kind = flags & 0xff;
        if (![1, 0xc, 0x12].includes(kind)) bounds(data, fileOffset, bytes, `Mach-O section ${name}`);
        if (relocations) bounds(data, relocationsOffset, relocations * 8, 'Mach-O relocations');
        sections.push({name, address, bytes, fileOffset, flags});
      }
    } else if (command === 2) {
      assert.equal(size, 24, 'LC_SYMTAB size is invalid');
      assert(!symbolTable, 'Duplicate LC_SYMTAB');
      symbolTable = {
        offset: data.readUInt32LE(offset + 8), count: data.readUInt32LE(offset + 12),
        strings: data.readUInt32LE(offset + 16), stringBytes: data.readUInt32LE(offset + 20)
      };
      bounds(data, symbolTable.offset, symbolTable.count * 16, 'Mach-O symbol table');
      bounds(data, symbolTable.strings, symbolTable.stringBytes, 'Mach-O string table');
    }
    offset += size;
  }
  assert.equal(offset, 32 + commandBytes, 'Mach-O load commands do not consume sizeofcmds');
  assert.equal(buildVersions.length, 1, 'Expected exactly one iOS deployment command');
  assert(symbolTable, 'Mach-O object must contain a symbol table');
  const definedSymbols = [];
  for (let index = 0; index < symbolTable.count; index++) {
    const entry = symbolTable.offset + index * 16;
    const stringIndex = data.readUInt32LE(entry);
    assert(stringIndex < symbolTable.stringBytes, 'Mach-O symbol string index is invalid');
    const name = cstring(data, symbolTable.strings + stringIndex, symbolTable.strings + symbolTable.stringBytes, 'Mach-O symbol name');
    const type = data[entry + 4];
    const section = data[entry + 5];
    if (!(type & 0xe0) && (type & 0x0e) === 0x0e) {
      assert(section > 0 && section <= sections.length, 'Mach-O symbol section index is invalid');
      const descriptor = sections[section - 1];
      const value = data.readBigUInt64LE(entry + 8);
      assert(value >= descriptor.address && value <= descriptor.address + BigInt(descriptor.bytes), 'Mach-O defined symbol lies outside its section');
      definedSymbols.push({name, external: !!(type & 1), section: descriptor.name, address: value.toString(), instructionSection: !!(descriptor.flags & 0x80000400)});
    } else if (!(type & 0xe0) && (type & 0x0e) === 2) {
      definedSymbols.push({name, external: !!(type & 1), section: 'ABS', instructionSection: false});
    } else if (!(type & 0xe0) && (type & 0x0f) === 1 && data.readBigUInt64LE(entry + 8) > 0n) {
      definedSymbols.push({name, external: true, section: 'COMMON', instructionSection: false});
    }
  }
  return {name: member.name, headerOffset: member.headerOffset, payloadOffset: member.payloadOffset, bytes: data.length, buildVersions, definedSymbols, sections: sections.map(({name, bytes, flags}) => ({name, bytes, flags}))};
}
function inspectArchive(data, maximumMinimumOS = 0x00100000) {
  assert(Buffer.isBuffer(data));
  bounds(data, 0, 8, 'Archive signature');
  assert.equal(data.subarray(0, 8).toString(), '!<arch>\n', 'Must be a regular native ar archive');
  const members = [];
  let offset = 8;
  while (offset < data.length) {
    bounds(data, offset, 60, 'Archive member header');
    const header = data.subarray(offset, offset + 60);
    assert.equal(header.subarray(58, 60).toString(), '`\n', 'Archive member header trailer is invalid');
    field(header, 16, 28, 10, 'Archive timestamp');
    field(header, 28, 34, 10, 'Archive UID');
    field(header, 34, 40, 10, 'Archive GID');
    field(header, 40, 48, 8, 'Archive mode');
    const size = field(header, 48, 58, 10, 'Archive size');
    bounds(data, offset + 60, size, 'Archive member payload');
    let name = header.subarray(0, 16).toString('ascii').trim();
    let payloadOffset = offset + 60;
    let payloadSize = size;
    if (name.startsWith('#1/')) {
      assert(/^#1\/\d+$/.test(name), 'Invalid BSD extended name');
      const nameBytes = Number(name.slice(3));
      assert(Number.isSafeInteger(nameBytes) && nameBytes > 0 && nameBytes <= size, 'Invalid BSD extended name bounds');
      const raw = data.subarray(payloadOffset, payloadOffset + nameBytes);
      const zero = raw.indexOf(0);
      if (zero >= 0) assert(raw.subarray(zero).every(x => x === 0), 'Nonzero bytes after extended name terminator');
      name = raw.subarray(0, zero < 0 ? nameBytes : zero).toString('utf8');
      payloadOffset += nameBytes;
      payloadSize -= nameBytes;
    } else if (name.endsWith('/') && name.length > 1) name = name.slice(0, -1);
    assert(name.length > 0 && !name.includes('\0'), 'Archive member name is invalid');
    members.push({name, headerOffset: offset, payloadOffset, payloadSize});
    offset += 60 + size;
    if (size % 2) {
      bounds(data, offset, 1, 'Archive alignment');
      assert.equal(data[offset], 10, 'Archive alignment must be newline');
      offset++;
    }
  }
  assert.equal(offset, data.length, 'Archive has trailing bytes');
  const indexes = members.filter(member => ['__.SYMDEF', '__.SYMDEF SORTED'].includes(member.name));
  assert.equal(indexes.length, 1, 'Expected exactly one valid BSD archive symbol table');
  assert.equal(members[0], indexes[0], 'BSD archive symbol table must be the first member');
  const objects = members.filter(member => !indexes.includes(member)).map(member => inspectObject(data.subarray(member.payloadOffset, member.payloadOffset + member.payloadSize), member, maximumMinimumOS));
  assert(objects.length > 0, 'Archive must contain Mach-O objects');
  const tableMember = indexes[0];
  const table = data.subarray(tableMember.payloadOffset, tableMember.payloadOffset + tableMember.payloadSize);
  bounds(table, 0, 4, 'Archive ranlib header');
  const ranlibBytes = table.readUInt32LE(0);
  assert.equal(ranlibBytes % 8, 0, 'Archive ranlib entries must be 8 bytes');
  bounds(table, 4, ranlibBytes + 4, 'Archive ranlib entries');
  const stringsOffset = 4 + ranlibBytes + 4;
  const stringBytes = table.readUInt32LE(4 + ranlibBytes);
  bounds(table, stringsOffset, stringBytes, 'Archive ranlib strings');
  const tail = table.subarray(stringsOffset + stringBytes);
  assert(tail.length <= 7 && tail.every(x => x === 0), 'Archive symbol table has unexpected trailing data');
  const indexedDefinitions = new Set();
  const objectsByOffset = new Map(objects.map(object => [object.headerOffset, object]));
  const externalNames = new Map(objects.map(object => [object.headerOffset, new Set(object.definedSymbols.filter(symbol => symbol.external).map(symbol => symbol.name))]));
  let previousName;
  for (let entry = 4; entry < 4 + ranlibBytes; entry += 8) {
    const stringIndex = table.readUInt32LE(entry);
    assert(stringIndex < stringBytes, 'Archive ranlib string index is invalid');
    const name = cstring(table, stringsOffset + stringIndex, stringsOffset + stringBytes, 'Archive indexed symbol');
    const object = objectsByOffset.get(table.readUInt32LE(entry + 4));
    assert(object, 'Archive indexed symbol must reference an object member header');
    assert(externalNames.get(object.headerOffset).has(name), 'Archive indexed symbol must exist as an external definition in its object');
    const key = `${object.headerOffset}\0${name}`;
    assert(!indexedDefinitions.has(key), 'Archive contains a duplicate indexed definition');
    indexedDefinitions.add(key);
    if (tableMember.name === '__.SYMDEF SORTED' && previousName !== undefined) assert(Buffer.compare(Buffer.from(previousName), Buffer.from(name)) <= 0, 'Sorted archive symbol table is not sorted');
    previousName = name;
  }
  for (const object of objects) {
    for (const symbol of object.definedSymbols.filter(symbol => symbol.external)) {
      assert(indexedDefinitions.has(`${object.headerOffset}\0${symbol.name}`), 'Archive symbol table omits an external definition');
    }
  }
  return {archiveBytes: data.length, symbolTableEntries: ranlibBytes / 8, objects};
}

// Input-only selection. The output checker deliberately accepts regular archives only.
function selectArchive(data) {
  bounds(data, 0, 4, 'Archive magic');
  const magic = data.readUInt32BE(0);
  assert(![0xcafebabf, 0xbfbafeca].includes(magic), 'FAT64 archives are unsupported');
  if (magic !== 0xcafebabe) {
    inspectArchive(data);
    return {bytes: data, universal: false};
  }
  bounds(data, 0, 8, 'FAT header');
  const count = data.readUInt32BE(4);
  assert(count > 0, 'FAT architecture table must not be empty');
  bounds(data, 8, count * 20, 'FAT architecture table');
  const tableEnd = 8 + count * 20;
  const entries = [];
  const identities = new Set();
  for (let index = 0; index < count; index++) {
    const record = 8 + index * 20;
    const cpu = data.readUInt32BE(record);
    const subtype = data.readUInt32BE(record + 4);
    const offset = data.readUInt32BE(record + 8);
    const size = data.readUInt32BE(record + 12);
    const alignment = data.readUInt32BE(record + 16);
    // Capability bits must not hide a second record for the same architecture.
    const identity = `${cpu}:${subtype & 0x00ffffff}`;
    assert(!identities.has(identity), 'FAT duplicate architecture identity');
    identities.add(identity);
    assert(alignment <= 31, 'FAT alignment exponent is invalid');
    assert(offset >= tableEnd && size > 0, 'FAT slice overlaps table or is empty');
    bounds(data, offset, size, 'FAT slice');
    assert.equal(offset % (2 ** alignment), 0, 'FAT slice is unaligned');
    entries.push({cpu, subtype, offset, size, alignment});
  }
  const ordered = [...entries].sort((a, b) => a.offset - b.offset);
  for (let index = 1; index < ordered.length; index++) {
    assert(ordered[index - 1].offset + ordered[index - 1].size <= ordered[index].offset, 'FAT slices overlap');
  }
  const candidates = entries.filter(entry => entry.cpu === 0x0100000c && entry.subtype === 0);
  assert.equal(candidates.length, 1, 'FAT must contain exactly one baseline ARM64 subtype 0 slice');
  const selected = candidates[0];
  const bytes = data.subarray(selected.offset, selected.offset + selected.size);
  // This checks the inner container and every device ARM64 object before extraction.
  inspectArchive(bytes);
  return {bytes, universal: true, selected, entries};
}

module.exports = {inspectArchive, inspectObject, selectArchive};
if (require.main === module) {
  const result = inspectArchive(fs.readFileSync(process.argv[2]));
  console.log(JSON.stringify(result, null, 2));
  console.log('PASS: regular Darwin archive; bounded device ARM64 objects; deployment <= iOS 16.0; validated symbol index');
}
