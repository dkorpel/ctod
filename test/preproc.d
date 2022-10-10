module preproc;
@nogc nothrow:
extern(C): __gshared:


private template HasVersion(string versionId) {
	mixin("version("~versionId~") {enum HasVersion = true;} else {enum HasVersion = false;}");
}
/* a comment outside the header guard */

 

//#pragma once

public import core.stdc.assert_;
public import core.stdc.string;
public import core.stdc.stdio;
public import small;

version = TEST;
enum PI = 3.14159265;
//#define LOL(x)
enum string SQR(string x) = ` (x*x)`;

enum string _GLFW_CONCAT_VERSION(string m, string n, string r) = ` #m "." #n "." #r`;
enum string _GLFW_MAKE_VERSION(string m, string n, string r) = ` _GLFW_CONCAT_VERSION(m, n, r)`;
enum _GLFW_VERSION_NUMBER = _GLFW_MAKE_VERSION(GLFW_VERSION_MAJOR, \
                                                GLFW_VERSION_MINOR, \
                                                GLFW_VERSION_REVISION);

version (Windows) {
// test
} else {
// no test
}

version (linux) {
// test
} else version (OSX) {
// no test
}

version (none) {
static assert(0, "error message");
} else version (OSX) {
// whoo
}

static if (!HasVersion!"Windows") {
	enum CUTE_TIME_PLATFORM = CUTE_TIME_WINDOWS;
}

