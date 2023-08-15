/**
C to D source code translator

Example usage:
```
ctod source.c header.h
```

Will output `source.d` and `header.d` translating the C code the best it can to D.
*/
module ctod.app;

import tree_sitter.api;

import std.stdio;
import std.path: withExtension;
import std.file;
import std.file: writeFile = write;
import std.path;

import ctod.translate;
private:

version(unittest) {} else
int main(string[] args)  {
	if (args.length < 2) {
		stderr.writeln("give at least one file argument");
		return -1;
	}
	try {
		foreach(i; 1..args.length) {
			TranslationSettings settings;
			if (args[i] == "--help") {
				printHelp(args[0]);
			} else {
				const fname = args[i];
				if (!(fname.extension == ".c" || fname.extension == ".h")) {
					stderr.writeln("file shoud have .c or .h extension, not ", fname.extension);
					return -1;
				}
				const source = cast(string) read(fname);
				const moduleName = fname.baseName.stripExtension;
				writeFile(fname.withExtension(".d"), translateFile(source, moduleName, settings));
			}
		}
	} catch (Exception e) {
		stderr.writeln(e.msg);
		return -1;
	}
	return 0;
}

void printHelp(string name) {
	writeln("Usage: ", name, " [FILES]\nOptions:\n  --strip  strip comments");
}
