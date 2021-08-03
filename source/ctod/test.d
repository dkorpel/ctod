module ctod.test;

import bops.string.string: stripWhite;
import ctod.translate;

private void test(string c, string d) {
	import bops.test: assertStringEqual;
	assertStringEqual(translateFile(stripWhite(c), "testmodule", false), stripWhite(d));
}

unittest {
	test("
struct S {

	struct {int y;} yy;
};

void foo(struct {int x;} *x);
", "

");


}