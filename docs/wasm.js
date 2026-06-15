// Stubs for WASI, needed because tree-sitter uses `fwrite(stderr, ...)` for error printing
function clock_time_get() { return 0; }
function fd_close() { return 0; }
function fd_seek() { return 0; }
function fd_write() { return 0; }
function proc_exit() { return 0; }

// Our own glue code
function jsConsoleLog(len, ptr) { console.log(toJsString(ptr, len)); }
function jsConsoleError(len, ptr) { console.error(toJsString(ptr, len)); }
function jsAbort(len, ptr) { throw new Error(toJsString(ptr, len)); }
function jsGetTimeMillis() { return new Date().getTime(); }

var wasm;

function toJsString(ptr, len) {
	try {
		var buffer = new Uint8Array(wasm.exports.memory.buffer, ptr, len);
		return new TextDecoder().decode(buffer);
	} catch (err) {
		console.error(err);
		return "";
	}
}

/// Send strings from JS to webassembly
function wasmSendString(str, type) {
	let buf = wasmStoreJsString(str, wasm.exports.getStringMessageBuffer(), wasm.exports.getStringMessageBufferLen())
	wasm.exports.receiveStringMessage(buffer.byteOffset, bytes.byteLength + 1, type);
	return buffer;
}

function wasmStoreJsString(str, ptr, len) {
	const bytes = new TextEncoder().encode(str);
	if (bytes.byteLength > len)
	{
		alert("input too big, must be at most " + len + " bytes") // #meh
		return null;
	}
	const buffer = new Uint8Array(wasm.exports.memory.buffer, ptr, bytes.byteLength + 1); // '0' terminator
	buffer.set(bytes);
	buffer[bytes.byteLength] = 0; // while Uint8Array is initialized to 0, don't rely on that
	return buffer;
}

async function loadWasm(fileName, imports) {
	const importObject = {
		wasi_snapshot_preview1: { clock_time_get, fd_close, fd_seek, fd_write, proc_exit },
		env: { ...imports, jsConsoleLog, jsConsoleError, jsAbort, jsGetTimeMillis }
	};

	const { instance } = await WebAssembly.instantiateStreaming(fetch(fileName), importObject);
	wasm = instance;
	return instance;
}
