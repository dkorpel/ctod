import tree_sitter.api;
import core.stdc.stdio: printf;
import core.stdc.stdlib: free;
import core.stdc.string: strlen;

import std.stdio;
import std.exception;

import ctod.translate;

int main(string[] args) {
	try {
		enforce(args.length >= 2, "give a file argument");
		import std.path: baseName, extension, withExtension, stripExtension;
		import std.file: read, write;
		const fname = args[1];
		enforce(fname.extension == ".c" || fname.extension == ".h");
		const source = cast(string) read(fname);
		const moduleName = fname.baseName.stripExtension;
		write(fname.withExtension(".d"), translateFile(source, moduleName));
	} catch (Exception e) {
		writeln(e.msg);
		return -1;
	}
	return 0;
}
