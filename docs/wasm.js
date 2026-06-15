
function toJsString(ptr, len) {return new TextDecoder().decode(new Uint8Array(wasm.exports.memory.buffer, ptr, len));}
function wasmStoreJsString(str, ptr, len) {return new TextEncoder().encodeInto(str, new Uint8Array(wasm.exports.memory.buffer, ptr, len)).written;}

var wasm;
async function loadWasm(fileName, imports) {
	const importObject = {
		// Stubs for WASI, needed because tree-sitter uses `fwrite(stderr, ...)` for error printing
		wasi_snapshot_preview1: {
			fd_write: (fd, iovs_ptr, iovs_len, nwritten_ptr) => {
				const view = new DataView(wasm.exports.memory.buffer);
				let text = '';
				let written = 0;
				for (let i = 0; i < iovs_len; i++) {
					const ptr = view.getUint32(iovs_ptr + i * 8, true);
					const len = view.getUint32(iovs_ptr + i * 8 + 4, true);
					text += toJsString(ptr, len);
					written += len;
				}
				view.setUint32(nwritten_ptr, written, true);
				(fd === 2 ? console.error : console.log)(text.replace(/\n$/, ''));
				return 0;
			},
			proc_exit: (code) => { throw new Error('exit ' + code); },
			fd_close: () => 0,
			fd_seek: () => 0,
			clock_time_get: (_clock_id, _precision, time_ptr) => {
				const nowNs = performance.now() * 1_000_000;
				const view = new DataView(wasm.exports.memory.buffer);
				view.setUint32(time_ptr,     nowNs >>> 0,                      true);
				view.setUint32(time_ptr + 4, Math.floor(nowNs / 0x100000000), true);
				return 0;
			},
		},
		env: { ...imports,
			// LLVM's loop-idiom pass (-Oz) can lower a hand-written null-terminated
			// string loop into a call to libc strlen, leaving it as an undefined import.
			strlen: (ptr) => { const m = new Uint8Array(wasm.exports.memory.buffer); let n = 0; while (m[ptr + n] !== 0) n++; return n; },
			jsConsoleLog: (len, ptr) => { console.log(toJsString(ptr, len)); },
			jsConsoleError: (len, ptr) => { console.error(toJsString(ptr, len)); },
			jsGetTimeMillis: () => { return new Date().getTime(); },
			jsDomSetInnerHtml: (idLen, idPtr, len, ptr) => { document.getElementById(toJsString(idPtr, idLen)).innerHTML = toJsString(ptr, len); },
			jsDomSetValue: (idLen, idPtr, len, ptr) => { document.getElementById(toJsString(idPtr, idLen)).value = toJsString(ptr, len); },
			jsDomGetValue: (idLen, idPtr, len, ptr) => { wasmStoreJsString(document.getElementById(toJsString(idPtr, idLen)).value, ptr, len); },
		}
	};

	const { instance } = await WebAssembly.instantiateStreaming(fetch(fileName), importObject);
	wasm = instance;
	return wasm;
}

// Write a JS string into the wasm scratch buffer and hand it to the wasm module.
// type = 0 for immediate update (user still typing), 1 for update after user stopped.
// Returns false (without sending) if the string does not fit in the buffer.
function wasmSendString(str, type) {
	const ptr = wasm.exports.getStringMessageBuffer();
	const cap = wasm.exports.getStringMessageBufferLen();
	const written = wasmStoreJsString(str, ptr, cap - 1); // leave room for '\0'
	if (written >= cap - 1) {
		return false; // input too big, possibly truncated - don't send
	}
	new Uint8Array(wasm.exports.memory.buffer)[ptr + written] = 0;
	wasm.exports.receiveStringMessage(ptr, written + 1, type); // length includes '\0'
	return true;
}
