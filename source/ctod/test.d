module ctod.test;

@safe:

import ctod.translate;
import ctod.util;

unittest
{
	string t = fileReadText("source/ctod/testcases.md");
	string c = null;
	string d = null;
	bool inC = false;
	bool inD = false;
	size_t lineNumber = 0;
	foreach (line; t.splitter('\n'))
	{
		lineNumber++;
		if (line.startsWith("```C"))
		{
			inC = true;
		}
		else if (line.startsWith("```D"))
		{
			inD = true;
		}
		else if (line.startsWith("```"))
		{
			inC = false;
			if (inD)
			{
				test(c, d, lineNumber);
				inD = false;
				c = null;
				d = null;
			}
		}
		else if (inC)
		{
			c ~= line ~ "\n";
		}
		else if (inD)
		{
			d ~= line ~ "\n";
		}
	}
}

private void test(string c, string d, size_t line = __LINE__) @trusted
{
	const actual = translateFile(c, "testmodule")[56 .. $];

	if (actual != d)
	{
		stderr.writeln("Error on line ", line);
		stderr.writeln("--- EXPECTED: ---");
		stderr.writeln(d);
		stderr.writeln("--- ACTUAL:   ---");
		stderr.writeln(actual);
		stderr.writeln("-----------------");
		assert(actual == d);
	}
}

unittest
{
	version(none) // TODO
	test(
		"#define CONSTANT ((size_t)1 << (sizeof(size_t) * 2))",
		"enum CONSTANT = (cast(size_t)1 << (size_t.sizeof * 2))"
	);
}
