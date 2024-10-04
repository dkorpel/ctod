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
import std.path : withExtension;
import std.file;
import std.file : writeFile = write;
import std.path;

import ctod.translate;
import ctod.util;

version (unittest) { } else
int main(string[] args)
{
	if (args.length < 2)
	{
		printHelp(args[0]);
		return -1;
	}
	try
	{
		foreach (i; 1 .. args.length)
		{
			if (args[i] == "--help")
			{
				printHelp(args[0]);
			}
			else
			{
				const fname = args[i];
				if (!(fname.extension == ".c" || fname.extension == ".h"))
				{
					stderr.writeln("file shoud have .c or .h extension, not ", fname.extension);
					return -1;
				}
				scope source = cast(string) fileReadText(fname);

				const moduleName = fname.baseName;
				writeFile(fname.withExtension(".d"), translateFile(source, moduleName));
			}
		}
	}
	catch (Exception e)
	{
		stderr.writeln(e.msg);
		return -1;
	}
	return 0;
}

void printHelp(string name)
{
	stderr.writeln("Usage: ", name, " [FILES]\n" ~
			"A translated .d file will be written to the same directory as each C source file.");
}
