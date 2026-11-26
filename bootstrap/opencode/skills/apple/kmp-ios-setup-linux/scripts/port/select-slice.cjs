#!/usr/bin/env node
// Driver for port/inspect-archive.cjs: write the baseline ARM64 subtype-0 slice
// of a universal (FAT) static archive to a new regular archive.
//   node select-slice.cjs <inspect-archive.cjs> <input.a> <output.a>
// The inspector stays byte-identical to the gate3 record; this driver only
// calls its exported selectArchive and writes the selected bytes.
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const [inspectorPath, inputPath, outputPath] = process.argv.slice(2);
if (!inspectorPath || !inputPath || !outputPath) {
  console.error('usage: select-slice.cjs <inspect-archive.cjs> <input.a> <output.a>');
  process.exit(2);
}
const {selectArchive} = require(path.resolve(inspectorPath));
const selected = selectArchive(fs.readFileSync(inputPath));
if (!selected.universal) {
  console.error('select-slice: input is not a universal archive');
  process.exit(1);
}
fs.writeFileSync(outputPath, selected.bytes);
console.error(`select-slice: CPU 0x${selected.selected.cpu.toString(16)} subtype ${selected.selected.subtype}, ${selected.bytes.length} bytes -> ${outputPath}`);
