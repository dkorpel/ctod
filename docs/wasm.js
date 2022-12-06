/*
import { WASI } from 'wasi';

// https://nodejs.org/api/wasi.html
const wasi = new WASI({
	args: argv,
	env,
	preopens: {}
});
*/

// Stubs for WASI, needed because tree-sitter uses `fwrite(stderr, ...)` for error printing
function clock_time_get() { return 0; }
function fd_close() { return 0; }
function fd_seek() { return 0; }
function fd_write() { return 0; }
function proc_exit() { return 0; }

// Some WASI binaries require:
// const importObject = { wasi_unstable: wasi.wasiImport };
// const importObject = { wasi_snapshot_preview1: wasi.wasiImport };

// Our own glue code
function jsConsoleLog(ptr, len) { console.log(toJsString(ptr, len)); }
function jsAbort(ptr, len) { throw new Error(toJsString(ptr, len)) }
function jsGetTimeMillis() { return new Date().getTime(); }

var wasmInstance;

function toJsString(ptr, len) {
	try {
		var buffer = new Uint8Array(wasmInstance.exports.memory.buffer, ptr, len);
		return string = new TextDecoder().decode(buffer);
	} catch (err) {
		return "eh?";
	}
}

/// Send strings from JS to webassembly
function wasmSendString(str, type) {
	const bytes = new TextEncoder().encode(str); // Encode in utf-8
	// Copy the string into memory allocated in the WebAssembly
	const ptr = wasmInstance.exports.getStringMessageBuffer();
	const len = wasmInstance.exports.getStringMessageBufferLen();
	if (bytes.byteLength > len) {
		alert("input too big, must be at most " + len + " bytes") // #meh
		return null;
	}
	const buffer = new Uint8Array(wasmInstance.exports.memory.buffer, ptr, bytes.byteLength + 1); // '0' terminator
	buffer.set(bytes);
	buffer[bytes.byteLength] = 0; // while Uint8Array is initialized to 0, don't rely on that
	wasmInstance.exports.receiveStringMessage(buffer.byteOffset, bytes.byteLength + 1, type);
	return buffer;
}

async function loadWasm(fileName, imports) {
	const importObject = {
		wasi_snapshot_preview1: { clock_time_get, fd_close, fd_seek, fd_write, proc_exit },
		env: { ...imports, jsConsoleLog, jsAbort, jsGetTimeMillis }
	};
	const fetchPromise = new Promise(resolve => {
		var request = new XMLHttpRequest();
		request.open('GET', fileName);
		request.responseType = 'arraybuffer';
		request.onload = e => resolve(request.response);
		request.onerror = function () {
			resolve(undefined);
			console.error("Could not retrieve WebAssembly object");
		};
		request.send();
	})

	const buffer = await fetchPromise;
	const module = await WebAssembly.compile(buffer);
	wasmInstance = await WebAssembly.instantiate(module, importObject);
	return wasmInstance;
}
