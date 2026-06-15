
/// exported so webassembly can send strings to JS
function ctodSendString(ptr, len) {
	const s = toJsString(ptr, len);
	document.getElementById('ctod-output').value = s;
}

// Don't display errors while user is still typing
let timer;
let lastAction = 'paste';

function onCtodInput(target, action) {
	res = wasmSendString(target.value, 0);

	if (res == null) {
		return; // don't set timeout, input too big
	}

	if (action == 'paste' || lastAction != 'paste')
	{
		clearTimeout(timer);
		timer = setTimeout(() => {
			wasmSendString(target.value, 1);
			lastAction = 'none';
		}, /*msec*/ action == 'paste' ? 0 : 500);
	}

	lastAction = action;
}

async function initWasm()
{
	loadWasm('ctod.wasm', { ctodSendString });
	const inputField = document.getElementById('ctod-input');
	inputField.addEventListener('input', (ev) => onCtodInput(ev.target, 'input'));
	inputField.addEventListener('paste', (ev) => onCtodInput(ev.target, 'paste'));
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
