module ctod.wasm;

version (WebAssembly):
nothrow:

import ctod.translate;

private extern (D) __gshared char[1 * 1024 * 1024] stringBuf = '\0';
private extern (C) char* getStringMessageBuffer() @system => stringBuf.ptr;
private extern (C) int getStringMessageBufferLen() @system => stringBuf.length;

// Note: length includes \0 terminator
extern (C) void receiveStringMessage(scope char* c, size_t length, int type) @trusted
{
	const str = c[0 .. length - 1]; // strip '\0'
	ctodInputString(str, type);
}

void ctodInputString(scope const(char)[] str, int updateType)
{
	// 0 == immediate, 1 == delayed
	if (updateType == 0)
		return;

	import bops.stdio;
	// stderr.writeln(__TIMESTAMP__);

	const source = cast(immutable) str;
	string res = translateFile(source, "");

	ctodSendString(res.ptr, res.length);
}

extern (C) void ctodSendString(scope const(char)* str, size_t len) @system;
