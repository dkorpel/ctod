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

@("time complexity") unittest {
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

	// float in union
	test("
typedef union
{
    uint u;
    float f;
} FP32;
", "
union _FP32 {
    uint_ u;
    float f;
}alias FP32 = _FP32;
");

	test("union U { float f, x; };", "union U { float f = 0, x; }");

	// Nested scopes
	test("
union U {
	float x;
	struct {
		float y;
		union { float z; float a; };
		float b;
	};
	float c;
};", "
union U {
	float x = 0;
	struct  {
		float y = 0;
		union  { float z = 0; float a; };
		float b = 0;
	};
	float c;
}");

	test(
		"int (*f1[4])(void);",
		"int function()[4] f1;"
	);

	test(
		"int (*f2)(enum {a} param0, struct {int x;} param1);",
		"enum _Param0 {a}struct _Param1 {int x;}int function(_Param0 param0, _Param1 param1) f2;"
	);

	test("inline static void foo(int x);", "pragma(inline, true) private void foo(int x);");

	// Test API macro before function definition
	test("WINAPI int** Whoa(void);", "WINAPI int** Whoa();");
	// Unfortunately, tree-sitter sees this as 2 declarations with a missing ';',
	// so there's no translation unsigned int => uint, but it should be clear what happened
	test("MYAPI unsigned int f(void);", "MYAPI unsigned; int f();");

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
	int* z = void; int y = void;
}
");

	// array parameters
	test(`void farrays(int x[1], int y[][4], int z[3][5], int *w[5], int (*v)[5]);`,
		`void farrays(int* x, int[4]* y, int[5]* z, int** w, int[5]* v);`);

	// TODO: qualifiers in array parameter
	// "void fquals(int x[const static 5]) {}"

	// Add `cast(int*)` to return value of malloc
	test("
void main() {
	int *x = malloc(4);
	x = calloc(5);
	x = realloc(x, 6);
	void *y = malloc(7);
	void *z = x;
	x = z;
	x = NULL;
}
", "
void main() {
	int* x = cast(int*) malloc(4);
	x = cast(int*) calloc(5);
	x = cast(int*) realloc(x, 6);
	void* y = malloc(7);
	void* z = x;
	x = cast(int*) z;
	x = null;
}
");

	// convert 0 to `null`
	test(`void f() { FILE *f = 0; f = 0; f = 1; }`, `void f() { FILE* f = null; f = null; f = cast(FILE*) 1; }`);

	test("typedef int intArr[3], intScalar;", "alias intArr = int[3];\nalias intScalar = int;");

	test("typedef struct X X;", "");

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
void foo() // comment
{
	int *y = x + 1;
	int *z = (1 + (x));
	pp(x);
}
", "
int[4] x;
void pp(int* p);
void foo() // comment
{
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
	int[10] buf = void;
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
	test("int soB = sizeof(int*) * 5;", "int soB = (int*).sizeof * 5;");
	test("int soC = sizeof(struct mg_dns_header);", "int soC = mg_dns_header.sizeof;");
	test("int soD = sizeof(struct {int x; int y;});", "int soD = .sizeof;"); // TODO

	test("int of = offsetof(S, f);", "int of = S.f.offsetof;");
	test("int of = offsetof(S, f, g);", "int of = offsetof(S, f, g);");
	test("int of = offsetof(struct S, f);", "int of = offsetof(struct S, f);");

}

@("numbers") unittest {
	test("float x = 1.f;", "float x = 1.0f;");
	test("float x = FLT_MAX;", "float x = float.max;");
	test("int x = DBL_MAX_10_EXP + DBL_MAX_EXP;", "int x = double.max_10_exp + double.max_exp;");
}

@("cast") unittest {
	test("int x = (int) 3.5;", "int x = cast(int) 3.5;");
	test("int x = (void(*)()) NULL;", "int x = cast(void function()) null;");

	test(`
typedef unsigned char X;
int c = (X)(5);
void main(void) {
	int d = (X)(6);
	int e = (*Y)(7);
	int f = (Y*)(7);
}
	`, `
alias X = ubyte;
int c = cast(X)(5);
void main() {
	int d = cast(X)(6);
	int e = (*Y)(7);
	int f = cast(Y*)(7);
}
	`);
}

@("function") unittest {
	test("
int *bar(int y, ...) {
	while (x) {
	}
	for (;;);
	for (unsigned short x = 0;;);
	for (int x = 0, *y = NULL;;);

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
	for ({int x = 0; int* y = null;};){}

	switch(0) {
		case 1: break;
	default: break;}
	switch(0) {
		default: break;
	}
	T* t = void;
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
const char p3[] = "abc", p4[] = "";
const char p5[] = "\nab" "\x22" "";
char p6[] = MACRO;
`, `
const(char)* p0 = "con" ~ "cat" ~ "enated";
const(char)* p1;
char* p2;
const(char)[4] p3 = "abc"; const(char)[1] p4 = "";
const(char)[5] p5 = "\nab" ~ "\x22" ~ "";
char[$] p6 = MACRO;
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
int b[4] = { 0, 1 };
", "
int[4] x = 0;
int[4] y = [ 1 ];
void main() {
	int[4] z = 0;
	float[4] w = 0;
}
int[4] b = [ 0, 1 ];
");

	test(
		"Rectangle r = (Rectangle){0l, y, width, height};",
		"Rectangle r = Rectangle(0L, y, width, height);"
	);

	test("
int x[] = { 0, 3, 5 /*comment*/ , 9 };
double y[];
void main() {
	int z[] = {10};
}
", "
int[4] x = [ 0, 3, 5 /*comment*/ , 9 ];
double[1] y = 0;
void main() {
	int[1] z = [10];
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
#include <winuser.h>
#include <linux/limits.h>
#include <sys/inotify.h>
#include <sys/timerfd.h>
#include <sys/ioctl.h>
#include \"my/lib.h\"
#include <pthread.h>
#include <cfile.c>
#include <x>
", "
public import core.stdc.assert_;
public import core.stdc.string;
public import core.stdc.stdio;
public import small;
public import core.sys.windows.winuser;
public import core.stdc.limits;
public import core.sys.linux.sys.inotify;
public import core.sys.linux.sys.timerfd;
public import core.sys.posix.sys.ioctl;
public import my.lib;
public import core.sys.posix.pthread;
public import cfile;
public import x;
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
enum NO_HEADER_GUARD = 3;

");

	test("
#ifndef CONDITION
#define NOT_THE_IFNDEF_CONDITION 99
#endif
", "
version (CONDITION) {} else {
enum NOT_THE_IFNDEF_CONDITION = 99;
}
");

	test("
#define TEST
#define PI 3.14159265
#define LOL(x)
", "
version = TEST;
enum PI = 3.14159265;
//#define LOL(x)
");

	test("
#define SQR(x) (x*x)
int x = SQR(3);
#define MIN(a,b) (((a)<(b))?(a):(b))
int y = MIN(1,2);
", "
enum string SQR(string x) = `(` ~ x ~ `*` ~ x ~ `)`;
int x = mixin(SQR!(`3`));
enum string MIN(string a,string b) = `(((` ~ a ~ `)<(` ~ b ~ `))?(` ~ a ~ `):(` ~ b ~ `))`;
int y = mixin(MIN!(`1`,`2`));
");

	test("
#define WITHCOMMENT//c
#define WITHCOMMENT1 '@'// c
#define WITHCOMMENTS /*a*/ '@' /*b*/ // c
", "
version = WITHCOMMENT;//c
enum WITHCOMMENT1 = '@';// c
enum WITHCOMMENTS /*a*/ = '@' /*b*/; // c
");


	test(`
#define _CONCAT_VERSION(m, n, r) #m "." #n "." #r
#define _MAKE_VERSION(m, n, r) _CONCAT_VERSION(m, n, r)
`, "
enum string _CONCAT_VERSION(string m, string n, string r) = `#m \".\" #n \".\" #r`;
enum string _MAKE_VERSION(string m, string n, string r) = `` ~ _CONCAT_VERSION!(` ~ `m` ~ `, ` ~ `n` ~ `, ` ~ `r` ~ `) ~ ``;
"
);

	test(`
#define _VERSION_NUMBER _MAKE_VERSION(VERSION_MAJOR, \
	VERSION_MINOR, \
	VERSION_REVISION)
`, "
enum _VERSION_NUMBER = _MAKE_VERSION(VERSION_MAJOR, \\
	VERSION_MINOR, \\
	VERSION_REVISION);
"
);

	test("
#define MIN(a,b) (((a)<(b))?(a):(b))
pixels[y*image->width + x+1].r = MIN((int)pixels[y*image->width + x+1].r + (int)((float)rError*7.0f/16), 0xff);
", "
enum string MIN(string a,string b) = `(((` ~ a ~ `)<(` ~ b ~ `))?(` ~ a ~ `):(` ~ b ~ `))`;
pixels[y*image.width + x+1].r = mixin(MIN!(`cast(int)pixels[y*image.width + x+1].r + cast(int)(cast(float)rError*7.0f/16)`, `0xff`));
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

	// va_arg (has failures currently because tree-sitter doesn't parse types in calls)
	test(`
double f(int count, ...)
{
	va_list args;
	va_start(args, count);
	int a0 = va_arg(args, int);
	double a1 = va_arg(args, double);
	unsigned int a2 = va_arg(args, unsigned int);
	char a3 = va_arg(args, char);
	va_end(args);
	return 0.0;
}
`, `
double f(int count, ...)
{
	va_list args = void;
	va_start(args, count);
	int a0 = va_arg!int(args);
	double a1 = va_arg!double(args);
	uint a2 = va_arg(args, unsigned int);
	char a3 = va_arg!char(args);
	va_end(args);
	return 0.0;
}
`);

	// TODO: prevent disappearing source code
	test(`void main(void) {
	if (1) {}
#if defined(SUPPORT_XXX)
	else if (cmp(n, "XXX")) x = LoadX(n, 0);
#endif
}`, `void main() {
	if (1) {}
version (SUPPORT_XXX) {
	else if = LoadX(n, 0);
}
}`);

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

@("misc") unittest {
	// strip backslash before newline
	test("int x = 3\\\n*4;", "int x = 3\n*4;");
}
