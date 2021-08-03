module ctod.test;

import bops.string.string: stripWhite;
import ctod.translate;

private void test(string c, string d) {
	import bops.test: assertStringEqual;
	TranslationSettings settings;
	settings.includeHeader = false;
	assertStringEqual(stripWhite(translateFile(c, "testmodule", settings)), stripWhite(d));
}

@("types") unittest {
	test("unsigned int x0;", "uint x0;");
	test("long long x3;", "long x3;");
	test("unsigned long long x4;", "ulong x4;");
	test("float x6;", "float x6;");
	test("double x7;", "double x7;");
	test("long double x8;", "real x8;");
	test("long x1;", "import core.stdc.config: c_long, c_ulong;\nc_long x1;");
	test("unsigned long x5;", "import core.stdc.config: c_long, c_ulong;\nc_ulong x5;");
	test("S xA;", "S xA;");
	//test("struct S x9;", "struct S ;S x9;");

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
	test("int so4 = sizeof(unsigned short);", "int so4 = unsigned short.sizeof;");
	test("int so5 = sizeof(GLFWvidmode);", "int so5 = GLFWvidmode.sizeof;");

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
	while(x) {
	}
	for(;;);
	for(unsigned short x = 0;;);
	switch (0) {
		case 1: break;
	}
	T *t;
	return t->ptr;
}", "
int* bar(int y, ...) {
	while(x) {
	}
	for(;;){}
	for(ushort x = 0;;){}
	switch (0) {
		case 1: break;
	default: break;}
	T* t;
	return t.ptr;
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

}
