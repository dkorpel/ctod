function sendInput() {
	wasmSendString(document.getElementById("ctod-input").value, 0);
}

/// exported so webassembly can send strings to JS
function ctodSendString(ptr, len) {
	const s = toJsString(ptr, len);
	document.getElementById('ctod-output').value = s;
}

// Don't display errors while user is still typing
let timer;

function onCtodInput(str) {
	res = wasmSendString(str, 0);

	if (res == null) {
		return; // don't set timeout, input too big
	}

	clearTimeout(timer);
	timer = setTimeout(() => {
		wasmSendString(str, 1);
	}, /*msec*/ 500);
}

async function initWasm() {
	wasmInstance = loadWasm('ctod.wasm', { ctodSendString });
	document.getElementById('ctod-input').addEventListener('input', (ev) => onCtodInput(ev.target.value));
}

window.addEventListener('load', (event) => {

	initWasm();

	// Make the tab key insert a '\t' instead of changing focus
	document.getElementById('ctod-input').addEventListener('keydown', (ev) => {
		if (ev.key == 'Tab') {
			let t = ev.target;
			ev.preventDefault();
			let start = t.selectionStart;
			t.value = t.value.substring(0, start) + "\t" + t.value.substring(t.selectionEnd);
			t.selectionStart = start + 1;
			t.selectionEnd = t.selectionStart;
		}
	});
});
