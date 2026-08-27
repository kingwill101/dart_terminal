import {readFile} from 'node:fs/promises';

const wasmPath = new URL(
  '../pkgs/vte/ghostty_vte_flutter/assets/ghostty-vt.wasm',
  import.meta.url,
);
const bytes = await readFile(wasmPath);
const module = await WebAssembly.compile(bytes);
const {exports} = await WebAssembly.instantiate(module);

const expectSuccess = (result, operation) => {
  if (result !== 0) {
    throw new Error(`${operation} failed with GhosttyResult ${result}`);
  }
};
const dataView = () => new DataView(exports.memory.buffer);

const terminalSlot = exports.ghostty_wasm_alloc_opaque();
expectSuccess(
  exports.ghostty_terminal_new(0, terminalSlot, 8, 2),
  'ghostty_terminal_new',
);
const terminal = exports.ghostty_wasm_take_opaque(terminalSlot);
if (terminal === 0) throw new Error('ghostty_terminal_new returned NULL');

const maxScrollback = exports.ghostty_wasm_alloc(4);
dataView().setUint32(maxScrollback, 10_000, true);
expectSuccess(
  exports.ghostty_terminal_set(terminal, 28, maxScrollback),
  'ghostty_terminal_set(scrollback max lines)',
);

const input = new TextEncoder().encode('latest upstream');
const inputPtr = exports.ghostty_wasm_alloc(input.length);
new Uint8Array(exports.memory.buffer, inputPtr, input.length).set(input);
exports.ghostty_terminal_vt_write(terminal, inputPtr, input.length);

// GhosttyFormatterTerminalOptions for wasm32. These offsets are mirrored by
// web_api.dart and intentionally exercised here as an ABI compatibility gate.
const formatterOptions = exports.ghostty_wasm_alloc(40);
new Uint8Array(exports.memory.buffer, formatterOptions, 40).fill(0);
dataView().setUint32(formatterOptions, 40, true);
dataView().setUint32(formatterOptions + 4, 0, true); // Plain text.
dataView().setUint8(formatterOptions + 9, 1); // Trim trailing whitespace.
dataView().setUint32(formatterOptions + 12, 24, true);
dataView().setUint32(formatterOptions + 24, 12, true);

const formatterSlot = exports.ghostty_wasm_alloc_opaque();
expectSuccess(
  exports.ghostty_formatter_terminal_new(
    0,
    formatterSlot,
    terminal,
    formatterOptions,
  ),
  'ghostty_formatter_terminal_new',
);
const formatter = exports.ghostty_wasm_take_opaque(formatterSlot);
if (formatter === 0) {
  throw new Error('ghostty_formatter_terminal_new returned NULL');
}

const outPtr = exports.ghostty_wasm_alloc(4);
const outLen = exports.ghostty_wasm_alloc(4);
expectSuccess(
  exports.ghostty_formatter_format_alloc(formatter, 0, outPtr, outLen),
  'ghostty_formatter_format_alloc',
);
const outputPtr = dataView().getUint32(outPtr, true);
const outputLen = dataView().getUint32(outLen, true);
const output = new TextDecoder().decode(
  new Uint8Array(exports.memory.buffer, outputPtr, outputLen),
);
if (output !== 'latest u\npstream') {
  throw new Error(`Unexpected formatter output: ${JSON.stringify(output)}`);
}

exports.ghostty_free(0, outputPtr, outputLen);
exports.ghostty_wasm_free(outLen, 4);
exports.ghostty_wasm_free(outPtr, 4);
exports.ghostty_formatter_free(formatter);
exports.ghostty_wasm_free_opaque(formatterSlot);
exports.ghostty_wasm_free(formatterOptions, 40);
exports.ghostty_wasm_free(inputPtr, input.length);
exports.ghostty_wasm_free(maxScrollback, 4);
exports.ghostty_terminal_free(terminal);
exports.ghostty_wasm_free_opaque(terminalSlot);

console.log(`Verified Ghostty VTE Wasm ABI (${bytes.length} bytes).`);
