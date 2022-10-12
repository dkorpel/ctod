module ctod.test;

import std.string: strip;
import ctod.translate;

private void test(string c, string d) {
	TranslationSettings settings;
	settings.includeHeader = false;
	assert(strip(translateFile(c, "testmodule", settings)) == strip(d));
}

version(none)
@("known bugs") unittest {
	test(
		"#define CONSTANT ((size_t)1 << (sizeof(size_t) * 2))",
		"enum CONSTANT = (cast(size_t)1 << (size_t.sizeof * 2))"
	);

}

@("types") unittest {
	test("unsigned x0;", "uint x0;");
	test("unsigned int x0;", "uint x0;");
	test("unsigned char c;", "ubyte c;");
	test("long long x3;", "long x3;");
	test("unsigned long long x4;", "ulong x4;");
	test("float x6;", "float x6;");
	test("double x7;", "double x7;");
	test("long double x8;", "real x8;");
	test("long x1;", "import core.stdc.config: c_long, c_ulong;\nc_long x1;");
	test("unsigned long x5;", "import core.stdc.config: c_long, c_ulong;\nc_ulong x5;");
	test("S xA;", "S xA;");
	test("unsigned x[10];", "uint[10] x;");
	test("struct S { unsigned x; };", "struct S { uint x; }");
	//test("struct S x9;", "struct S ;S x9;");

	// inline struct/enum
	test("void foo(struct T t);", "void foo(T t);");

	test("void foo(struct T *t);", "void foo(T* t);");
	test("void foo(enum E *e);", "void foo(E* e);");

	test("void foo(struct S {int x;} s, struct T {int y;} t);", "struct S {int x;}struct T {int y;}void foo(S s, T t);");
	test("void foo(enum E {one, two} t);", "enum E {one, two}void foo(E t);");

	test("int a0[1];", "int[1] a0;");
	test("int *a1[2];", "int*[2] a1;");
	test("int (*a2)[3];", "int[3]* a2;");
	test("int a3[4][5];", "int[5][4] a3;");
	test("int *a4[6][7];", "int*[7][6] a4;");
	test("int *(*a5)[8][9];", "int*[9][8]* a5;");
	test("int **a6[8][9];", "int**[9][8] a6;");
	test("int a[2], (*b)[2];", "int[2] a;int[2]* b;");
	test(
		"void (*f0)(int x, float, char*, char[], char*[], char***);",
		"void function(int x, float, char*, char, char*, char***) f0;"
	);

	test(
		"int (*f1[4])(void);",
		"int function()[4] f1;"
	);

	test("inline static void foo(int x);", "pragma(inline, true) private void foo(int x);");
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
}

@("struct") unittest {
	test("
typedef struct T {
	S *ptr;
	int arr[3];
	int32_t capacity;
	__u8 type;
} T;
", "
struct T {
	S* ptr;
	int[3] arr;
	int capacity;
	ubyte type;
}
");
}

@("enum") unittest {
	test("typedef enum AnEnum
{
	one = 1000123000,
	two = 0x7FFFFFFF
} AnEnum;", "enum AnEnum {
	one = 1000123000,
	two = 0x7FFFFFFF
}");
}

@("sizeof") unittest {
	test("int so1 = sizeof(int);", "int so1 = int.sizeof;");
	test("int so2 = sizeof (4);", "int so2 = typeof(4).sizeof;");
	test("int so3 = sizeof((short) 3 + 4l);", "int so3 = typeof(cast(short) 3 + 4L).sizeof;");
	test("int so4 = sizeof(unsigned short);", "int so4 = ushort.sizeof;");
	test("int so5 = sizeof(GLFWvidmode);", "int so5 = GLFWvidmode.sizeof;");

	test("int so6 = = sizeof(int) * 5;", "int so6 = int.sizeof * 5;");
	test("int so6 = = sizeof(unsigned char) * 5;", "int so6 = ubyte.sizeof * 5;");

	test("int of = offsetof(S, f);", "int of = S.f.offsetof;");
	test("int of = offsetof(S, f, g);", "int of = offsetof(S, f, g);");
	test("int of = offsetof(struct S, f);", "int of = offsetof(struct S, f);");

	// TODO
	// test("int so2 = sizeof 4lu;", "int so2 = (4Lu).sizeof;");
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
	if ((x=30) != false) {}
	while ((x=40) != false) {}
	for (; (x=50) != false; ) {}
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

@("designator list") unittest {
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

	test("
S a = {
	.fieldA = 1,
	.fieldB = 2,
};
", "
S a = [
	fieldA: 1,
	fieldB: 2,
];
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

	test("
#ifndef HEADER_GUARD
// comment here
#define HEADER_GUARD

#pragma once
#endif

", "
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
#endif", "
version (Windows) {} else {
   int x;
} version (Windows) {
   int y;
}
");

	// tree-sitter doesn't parse this right, need to do manual preprocessing
	version(none) test("
#ifdef __cplusplus
extern \"C\" {
#endif

#ifdef __cplusplus
}
#endif
");

}
