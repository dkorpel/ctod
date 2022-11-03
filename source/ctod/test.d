module ctod.test;

@safe:

import ctod.translate;

private void test(string c, string d) {
	TranslationSettings settings;
	settings.includeHeader = false;
	const actual = translateFile(c, "testmodule", settings);
	if (actual != d) {
		import std.stdio: writeln;
		writeln("--- EXPECTED: ---");
		writeln(d);
		writeln("--- ACTUAL:   ---");
		writeln(actual);
		writeln("-----------------");
		assert(actual == d);
	}
}

version(none)
@("known bugs") unittest {
	test(
		"#define CONSTANT ((size_t)1 << (sizeof(size_t) * 2))",
		"enum CONSTANT = (cast(size_t)1 << (size_t.sizeof * 2))"
	);
}

@("test time complexity") unittest {
	// Accidental binary recursion when constructing the node tree gave exponential time complexity
	// This test won't finish in a reasonable time if that happens again
	test("int y = (((((((((((((((((((((((((((((((((((((((((((((((((((((x)))))))))))))))))))))))))))))))))))))))))))))))))))));",
		 "int y = (((((((((((((((((((((((((((((((((((((((((((((((((((((x)))))))))))))))))))))))))))))))))))))))))))))))))))));");

}

@("types") unittest {
	test("unsigned x0;", "uint x0;");
	test("unsigned int x0;", "uint x0;");
	test("unsigned char c;", "ubyte c;");
	test("long long x3;", "long x3;");
	test("unsigned long long x4;", "ulong x4;");
	test("float x6;", "float x6 = 0;");
	test("double x7;", "double x7 = 0;");
	test("long double x8;", "real x8 = 0;");
	test("long x1;", "import core.stdc.config: c_long, c_ulong;\nc_long x1;");
	test("unsigned long x5;", "import core.stdc.config: c_long, c_ulong;\nc_ulong x5;");
	test("S xA;", "S xA;");
	test("unsigned x[10];", "uint[10] x;");
	test("struct S { unsigned x; };", "struct S { uint x; }");

	test("int x = 1, y = 2, *z = null, w = 0;", "int x = 1, y = 2; int* z = null; int w = 0;");
	test("unsigned *in = i, *out = o;", "uint* in_ = i, out_ = o;");
	test("unsigned *in = i, *out = o;", "uint* in_ = i, out_ = o;");
	test(
		"void f() {for(int i = 1, j = 2; i < 5; ++i);}",
		"void f() {for(int i = 1, j = 2; i < 5; ++i){}}"
	);

	// inline struct/enum
	test("void foo(struct {int x;} t);", "struct _T {int x;}void foo(_T t);");
	test("void foo(struct T t);", "void foo(T t);");

	test("void foo(struct T *t);", "void foo(T* t);");
	test("void foo(enum E *e);", "void foo(E* e);");

	// Note: not actually valid C, "types may not be defined in parameter types"
	test("void foo(struct S {int x;} s, struct T {int y;} t);", "struct S {int x;}struct T {int y;}void foo(S s, T t);");

	test("int a0[1];", "int[1] a0;");
	test("int *a1[2];", "int*[2] a1;");
	test("int (*a2)[3];", "int[3]* a2;");
	test("int a3[4][5];", "int[5][4] a3;");
	test("int *a4[6][7];", "int*[7][6] a4;");
	test("int *(*a5)[8][9];", "int*[9][8]* a5;");
	test("int **a6[8][9];", "int**[9][8] a6;");
	test("int a[2], (*b)[2];", "int[2] a; int[2]* b;");
	test("double z[4][3];", "double[3][4] z = 0;");
	test(
		"void (*f0)(int x, float, char*, char[], char*[], char***);",
		"void function(int x, float, char*, char, char*, char***) f0;"
	);

	// TODO: add missing const
	test("char * const(*(* const bar)[5])(int);", "char* function(int)[5]* bar;");

	test("
struct S {
	char x[10];
	float y;
	int z;
};
", "
struct S {
	char[10] x = 0;
	float y = 0;
	int z;
}
");

	test(
		"int (*f1[4])(void);",
		"int function()[4] f1;"
	);

	test(
		"int (*f2)(enum {a} param0, struct {int x;} param1);",
		"enum _Param0 {a}struct _Param1 {int x;}int function(_Param0 param0, _Param1 param1) f2;"
	);

	test("inline static void foo(int x);", "pragma(inline, true) private void foo(int x);");
	test("
int main(void) {
    static int xx;
}
", "
int main() {
    static int xx;
}
");

	test("
union U {
	char tag;
	union
	{
		int x[2];
		enum {one, two} y;
	} overlapped;
};
", "
union U {
	char tag = 0;
	union _Overlapped {
		int[2] x;
		enum _Y {one, two}_Y y;
	}_Overlapped overlapped;
}
");

	test("extern inline int e0;", "pragma(inline, true) extern int e0;");

	test("
inline static void foo(int x[], int (*y)(void)) {
	int *z, y;
}
", "
pragma(inline, true) private void foo(int* x, int function() y) {
	int* z; int y;
}
");

	// Future enhancement: add `cast(int*)` to return value of malloc
	test("
void main() {
	int *x = malloc(4);
	x = calloc(4);
}
", "
void main() {
	int* x = malloc(4);
	x = calloc(4);
}
");

	test("typedef int intArr[3], intScalar;", "alias intArr = int[3];\nalias intScalar = int;");

	test("struct OpaqueS;", "struct OpaqueS;");
	test("union OpaqueU;", "union OpaqueU;");

	test("
struct S {
	int in;
	unsigned char out[2];
};
", "
struct S {
	int in_;
	ubyte[2] out_;
}
");

	test("
struct {
unsigned short x : 12;
unsigned short y : sizeof(int);
} bitfields;
", "
struct _Bitfields {
ushort x;/*: 12 !!*/
ushort y;/*: int.sizeof !!*/
}_Bitfields bitfields;
");
}

@("static array .ptr") unittest {
	test("
int x[4];
void pp(int *p);
void foo()
{
	int *y = x + 1;
	int *z = (1 + (x));
	pp(x);
}
", "
int[4] x;
void pp(int* p);
void foo() {
	int* y = x.ptr + 1;
	int* z = (1 + (x).ptr);
	pp(x.ptr);
}
");

	test("
void main() {
	int buf[10];
	int b = buf[0] == 0;
}
", "
void main() {
	int[10] buf;
	int b = buf[0] == 0;
}
"
);

}

@("struct") unittest {
	test("
typedef struct T {
	S *ptr;
	int arr[3];
	int parr[];
	int32_t capacity;
	__u8 type;
} T;
", "
struct T {
	S* ptr;
	int[3] arr;
	int* parr;
	int capacity;
	ubyte type;
}
");

	test("
typedef struct S S;
typedef union U U;
typedef struct S0 S1;
typedef union U0 U1;
", "


alias S1 = S0;
alias U1 = U0;
");
}

@("enum") unittest {
	test("
typedef enum AnEnum
{
	one = 1000123000,
	two = 0x7FFFFFFF
} AnEnum;
", "
enum AnEnum {
	one = 1000123000,
	two = 0x7FFFFFFF
}
alias one = AnEnum.one;
alias two = AnEnum.two;

");

	test("enum {A};", "enum {A}"); // don't create aliases for anonymous enums

	test("
enum X
{
    A,
    B
};
", "
enum X
{
    A,
    B
}
alias A = X.A;
alias B = X.B;

");

}

@("sizeof") unittest {
	test("int so1 = sizeof(int);", "int so1 = int.sizeof;");
	test("int so2 = sizeof (4);", "int so2 = typeof(4).sizeof;");
	test("int so3 = sizeof((short) 3 + 4l);", "int so3 = typeof(cast(short) 3 + 4L).sizeof;");
	test("int so4 = sizeof(unsigned short);", "int so4 = ushort.sizeof;");
	test("int so5 = sizeof(GLFWvidmode);", "int so5 = GLFWvidmode.sizeof;");
	test("int so6 = sizeof 4lu;", "int so6 = 4Lu.sizeof;");
	test("int so7 = sizeof \"abc\";", "int so7 = (\"abc\".length + 1);");
	test("int so7 = sizeof(\"abc\");", "int so7 = (\"abc\".length + 1);");

	test(
		"int so8 = ((size_t) _glfw.monitorCount - 1) * sizeof(_GLFWmonitor*);",
		"int so8 = (cast(size_t) _glfw.monitorCount - 1) * (_GLFWmonitor*).sizeof;"
	);

	test("int so9 = sizeof(int) * 5;", "int so9 = int.sizeof * 5;");
	test("int soA = sizeof(unsigned char) * 5;", "int soA = ubyte.sizeof * 5;");
	test("int soB = = sizeof(int*) * 5;", "int soB = (int*).sizeof * 5;");
	test("int soC = sizeof(struct mg_dns_header);", "int soC = mg_dns_header.sizeof;");

	test("int of = offsetof(S, f);", "int of = S.f.offsetof;");
	test("int of = offsetof(S, f, g);", "int of = offsetof(S, f, g);");
	test("int of = offsetof(struct S, f);", "int of = offsetof(struct S, f);");

}

@("numbers") unittest {
	test("float x = 1.f;", "float x = 1.0f;");
	test("float x = FLT_MAX;", "float x = FLT_MAX;"); // TODO
}

@("cast") unittest {
	test("int x = (int) 3.5;", "int x = cast(int) 3.5;");
	test("int x = (void(*)()) NULL;", "int x = cast(void function()) null;");
}

@("function") unittest {
	test("
int *bar(int y, ...) {
	while (x) {
	}
	for (;;);
	for (unsigned short x = 0;;);
	switch(0) {
		case 1: break;
	}
	switch(0) {
		default: break;
	}
	T *t;
	return t->ptr;
}", "
int* bar(int y, ...) {
	while (x) {
	}
	for (;;){}
	for (ushort x = 0;;){}
	switch(0) {
		case 1: break;
	default: break;}
	switch(0) {
		default: break;
	}
	T* t;
	return t.ptr;
}");

}

@("assignment in if/while/for") unittest {
	test("
void main() {
	if (x=30) {}
	while (x=40) {}
	for (; x=50; ) {}
	if (x==60) {}
}", "
void main() {
	if ((x=30) != 0) {}
	while ((x=40) != 0) {}
	for (; (x=50) != 0; ) {}
	if (x==60) {}
}");

test("
void main() {
	int x = !(y = 3) + 4;
	while(!(x = 5)) { break; }

}", "
void main() {
	int x = ((y = 3) == 0) + 4;
	while(((x = 5) == 0)) { break; }

}");

}

@("strings") unittest {
	test(`
const char *p0 = "con" "cat" "enated";
char const *p1;
char *const p2;
`, `
const(char)* p0 = "con" ~ "cat" ~ "enated";
const(char)* p1;
char* p2;
`);

	test("wchar_t p3;", "import core.stdc.stddef: wchar_t;\nwchar_t p3;");
}

@("initializers") unittest {

	test("
int x[4] = { 0 };
int y[4] = { 1 };
void main() {
	int z[4] = { 0 };
	float w[4] = {};
}
", "
int[4] x = 0;
int[4] y = [ 1 ];
void main() {
	int[4] z = 0;
	float[4] w = 0;
}
");

	test(
		"Rectangle r = (Rectangle){0l, y, width, height};",
		"Rectangle r = Rectangle(0L, y, width, height);"
	);

	test("
int x[] = { 0, 3, 5 /*comment*/ , 9 };
void main() {
	int y[] = {10};
}
", "
int[4] x = [ 0, 3, 5 /*comment*/ , 9 ];
void main() {
	int[1] y = [10];
}
");

	// designator list
	test("
int a[2] = {
	[0] = 1,
	[1] = 2,
};
", "
int[2] a = [
	0: 1,
	1: 2,
];
");

	test("INTARRAY a = {[0] = 1};", "INTARRAY a = [0: 1];");

	test("
S a = {
	.fieldA = 1,
	.fieldB = 2,
};
", "
S a = {
	fieldA: 1,
	fieldB: 2,
};
");
}

@("preprocessor") unittest {
	test("
#include <assert.h>
#include <string.h>
# include <stdio.h>
#include \"small.c\"
", "
public import core.stdc.assert_;
public import core.stdc.string;
public import core.stdc.stdio;
public import small;
");

	test("#undef X", "");

	test("
#ifndef HEADER_GUARD
// comment here
#define HEADER_GUARD

#pragma once
#endif
", "\n \n
//#pragma once

");

	test("
#ifndef NO_HEADER_GUARD
#define NO_HEADER_GUARD 3
#endif
", "
version (NO_HEADER_GUARD) {} else {
enum NO_HEADER_GUARD = 3;
}
");


	test("
#define TEST
#define PI 3.14159265
#define LOL(x)
#define SQR(x) (x*x)
", "
version = TEST;
enum PI = 3.14159265;
//#define LOL(x)
enum string SQR(string x) = ` (x*x)`;
");

	test("
#ifdef _WIN32
// test
#else
// no test
#endif

#ifdef __linux__
// test
#elif defined(__MACH__)
// no test
#endif
", "
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
");

	test("
#if 0
#error \"error message\"
#elif defined(__APPLE__)
// whoo
#endif
", "
version (none) {
static assert(0, \"error message\");
} else version (OSX) {
// whoo
}
");

	test("
#ifndef _WIN32
   int x;
#else
   int y;
#endif
", "
version (Windows) {} else {
   int x;
} version (Windows) {
   int y;
}
");

	test(`
#if !defined(_WIN32)
	#define PLATFORM WINDOWS
#endif
`, `
private template HasVersion(string versionId) {
	mixin("version("~versionId~") {enum HasVersion = true;} else {enum HasVersion = false;}");
}

static if (!HasVersion!"Windows") {
	enum PLATFORM = WINDOWS;
}
`);

	// tree-sitter doesn't parse this right, need to do manual preprocessing
	version(none) test("
#ifdef __cplusplus
extern \"C\" {
#endif

#ifdef __cplusplus
}
#endif
");

	version(none) test(`
#define _GLFW_CONCAT_VERSION(m, n, r) #m "." #n "." #r
#define _GLFW_MAKE_VERSION(m, n, r) _GLFW_CONCAT_VERSION(m, n, r)
#define _GLFW_VERSION_NUMBER _GLFW_MAKE_VERSION(GLFW_VERSION_MAJOR, \
                                                GLFW_VERSION_MINOR, \
                                                GLFW_VERSION_REVISION)
`, "TODO"
);

}
