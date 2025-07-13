# CTOD tests

This is a list of C markdown blocks followed by a D markdown block containing the expected translation of the C code.
Anything outside the markdown blocks is ignored.

## Types
```C
unsigned x0;
```
```D
uint x0;
```

---
```C
unsigned int x0;
```
```D
uint x0;
```

---
```C
unsigned char c;
```
```D
ubyte c;
```

---
```C
long long x3;
long long int x4;
```
```D
long x3;
long x4;
```

---
```C
unsigned long long x4;
```
```D
ulong x4;
```

---
```C
float x6;
```
```D
float x6 = 0;
```

---
```C
double x7;
```
```D
double x7 = 0;
```

---
```C
long double x8;
```
```D
real x8 = 0;
```

---
```C
long x1;
long int y1;
```
```D
import core.stdc.config: c_long, c_ulong;
c_long x1;
c_long y1;
```

---
```C
unsigned long x5;
```
```D
import core.stdc.config: c_long, c_ulong;
c_ulong x5;
```

---
```C
S xA;
```
```D
S xA;
```

---
```C
unsigned x[10];
```
```D
uint[10] x;
```

---
```C
struct S { unsigned x; };
```
```D
struct S { uint x; }
```
---
## Multiple declarators
```C
int x = 1, y = 2, *z = null, w = 0;
```
```D
int x = 1, y = 2; int* z = null; int w = 0;
```

---
```C
unsigned *in = i, *out = o;
```
```D
uint* in_ = i, out_ = o;
```

---
```C
unsigned *in = i, *out = o;
```
```D
uint* in_ = i, out_ = o;
```

---
```C
void f() {for (int i = 1, j = 2; i < 5; ++i);}
```
```D
void f() {for (int i = 1, j = 2; i < 5; ++i){}}
```
---
## Inline types
```C
void foo(struct {int x;} t);
```
```D
struct _T {int x;}void foo(_T t);
```

---
```C
void foo(struct T t);
```
```D
void foo(T t);
```

---
```C
void foo(struct T *t);
```
```D
void foo(T* t);
```

---
```C
void foo(enum E *e);
```
```D
void foo(E* e);
```
---
Note: not actually valid C, "types may not be defined in parameter types"
```C
void foo(struct S {int x;} s, struct T {int y;} t);
```
```D
struct S {int x;}struct T {int y;}void foo(S s, T t);
```
---
## Arrays
```C
int a0[1];
```
```D
int[1] a0;
```

---
```C
int *a1[2];
```
```D
int*[2] a1;
```

---
```C
int (*a2)[3];
```
```D
int[3]* a2;
```

---
```C
int a3[4][5];
```
```D
int[5][4] a3;
```

---
```C
int *a4[6][7];
```
```D
int*[7][6] a4;
```

---
```C
int *(*a5)[8][9];
```
```D
int*[9][8]* a5;
```

---
```C
int **a6[8][9];
```
```D
int**[9][8] a6;
```

---
```C
int a[2], (*b)[2];
```
```D
int[2] a; int[2]* b;
```

---
```C
double z[4][3];
```
```D
double[3][4] z = 0;
```

---
```C
void (*f0)(int x, float, char*, char[], char*[], char***);
```
```D
void function(int x, float, char*, char, char*, char***) f0;
```

---
```C
typedef __uint128_t tb_uint128_t;
typedef __int128_t tb_int128_t;
```
```D
import core.int128;
alias tb_uint128_t = Cent;
alias tb_int128_t = Cent;
```
---
TODO: add missing const in D translation
```C
char * const(*(* const bar)[5])(int);
```
```D
char* function(int)[5]* bar;
```

---
```C
struct S
{
	char x[10];
	float y;
	int z;
};
```
```D
struct S
{
	char[10] x = 0;
	float y = 0;
	int z;
}
```

---
```C
typedef union
{
	uint u;
	float f;
} FP32;
```
```D
union FP32 {
	uint_ u;
	float f;
}
```

---
```C
union U { float f, x; };
```
```D
union U { float f = 0, x; }
```

---
```C
union U {
	float x;
	struct {
		float y;
		union { float z; float a; };
		float b;
	};
	float c;
};
```
```D
union U {
	float x = 0;
	struct  {
		float y = 0;
		union  { float z = 0; float a; };
		float b = 0;
	};
	float c;
}
```

---
```C
int (*f1[4])(void);
```
```D
int function()[4] f1;
```

---
```C
int (*f2)(enum {a} param0, struct {int x;} param1);
```
```D
enum _Param0 {a}struct _Param1 {int x;}int function(_Param0 param0, _Param1 param1) f2;
```

---
```C
inline static void foo(int x);
```
```D
pragma(inline, true) private void foo(int x);
```

---
Test API macro before function definition
```C
WINAPI int** Whoa(void);
```
```D
WINAPI int** Whoa();
```

---
Unfortunately, tree-sitter sees this as 2 declarations with a missing ';',
so there's no translation unsigned int => uint, but it should be clear what happened
```C
MYAPI unsigned int f(void);
```
```D
MYAPI unsigned; int f();
```

---
```C
int main(void) {
	static int xx;
}
```
```D
int main() {
	static int xx;
}
```

---
```C
union U {
	char tag;
	union
	{
		int x[2];
		enum {one, two} y;
	} overlapped;
};
```
```D
union U {
	char tag = 0;
	union _Overlapped {
		int[2] x;
		enum _Y {one, two}_Y y;
	}_Overlapped overlapped;
}
```

---
```C
extern inline int e0;
```
```D
pragma(inline, true) extern int e0;
```

---
```C
inline static void foo(int x[], int (*y)(void)) {
	int *z, y;
}
```
```D
pragma(inline, true) private void foo(int* x, int function() y) {
	int* z = void; int y = void;
}
```
---
TODO: qualifiers in array parameter
"void fquals(int x[const static 5]) {}"
```C
void farrays(int x[1], int y[][4], int z[3][5], int *w[5], int (*v)[5]);
```
```D
void farrays(int* x, int[4]* y, int[5]* z, int** w, int[5]* v);
```
---
Add `cast(int*)` to return value of malloc
```C
void main() {
	int *x = malloc(4);
	x = calloc(5);
	x = realloc(x, 6);
	void *y = malloc(7);
	void *z = x;
	x = z;
	x = NULL;
}
```
```D
void main() {
	int* x = cast(int*) malloc(4);
	x = cast(int*) calloc(5);
	x = cast(int*) realloc(x, 6);
	void* y = malloc(7);
	void* z = x;
	x = cast(int*) z;
	x = null;
}
```
---
Don't cast pointer math to pointer types https://github.com/dkorpel/ctod/issues/42
```C
void f(void) {
	const char* ptr = "hello";
	ptr += 1;
}
```
```D
void f() {
	const(char)* ptr = "hello";
	ptr += 1;
}
```

---
Convert 0 to `null`
```C
void f() { FILE *f = 0; f = 0; f = 1; }
```
```D
void f() { FILE* f = null; f = null; f = cast(FILE*) 1; }
```

---
```C
typedef int intArr[3], intScalar;
```
```D
alias intArr = int[3];
alias intScalar = int;
```

---
```C
typedef struct X X;
```
```D

```
---
## Opaque types
```C
struct OpaqueS;
```
```D
struct OpaqueS;
```

---
```C
union OpaqueU;
```
```D
union OpaqueU;
```

---
```C
enum OpaqueE;
```
```D
enum OpaqueE;
```
---
Reserved identifiers
```C
struct S
{
	int in;
	unsigned char out[2];
};

```
```D
struct S
{
	int in_;
	ubyte[2] out_;
}

```
---
Bitfields
```C
struct {
unsigned short x : 12;
unsigned short y : sizeof(int);
} bitfields;
```
```D
struct _Bitfields {
ushort x;/*: 12 !!*/
ushort y;/*: int.sizeof !!*/
}_Bitfields bitfields;
```

---
```C
int x[4];
void pp(int *p);
void foo() // comment
{
	int *y = x + 1;
	int *z = (1 + (x));
	pp(x);
}
```
```D
int[4] x;
void pp(int* p);
void foo() // comment
{
	int* y = x.ptr + 1;
	int* z = (1 + (x).ptr);
	pp(x.ptr);
}
```

---
```C
void main() {
	int buf[10];
	int b = buf[0] == 0;
}
```
```D
void main() {
	int[10] buf = void;
	int b = buf[0] == 0;
}
```

---
```C
typedef struct T {
	S *ptr;
	int arr[3];
	int32_t capacity;
	__u8 type;
} T;
```
```D
struct T {
	S* ptr;
	int[3] arr;
	int capacity;
	ubyte type;
}
```

---
```C
typedef struct S S;
typedef union U U;
typedef struct S0 S1;
typedef union U0 U1;
```
```D


alias S1 = S0;
alias U1 = U0;
```

---
```C
typedef enum AnEnum
{
	one = 1000123000,
	two = 0x7FFFFFFF
} AnEnum;
```
```D
enum AnEnum {
	one = 1000123000,
	two = 0x7FFFFFFF
}
alias one = AnEnum.one;
alias two = AnEnum.two;

```

---
```C
typedef enum { a, b } Foo;
```
```D
enum Foo { a, b }
alias a = Foo.a;
alias b = Foo.b;

```

---
```C
typedef enum { a } *Foo;
```
```D
enum _Foo { a }alias Foo = _Foo*;
alias a = _Foo.a;

```
---
Don't create aliases for anonymous enums
```C
enum {A};
```
```D
enum {A}
```

---
```C
enum X
{
	A,
	B
};
```
```D
enum X
{
	A,
	B
}
alias A = X.A;
alias B = X.B;

```
---
## Sizeof

```C
int so1 = sizeof(int);
```
```D
int so1 = int.sizeof;
```

---
```C
int so2 = sizeof (4);
```
```D
int so2 = typeof(4).sizeof;
```

---
```C
int so3 = sizeof((short) 3 + 4l);
```
```D
int so3 = typeof(cast(short) 3 + 4L).sizeof;
```

---
```C
int so4 = sizeof(unsigned short);
```
```D
int so4 = ushort.sizeof;
```

---
```C
int so5 = sizeof(GLFWvidmode);
```
```D
int so5 = GLFWvidmode.sizeof;
```

---
```C
int so6 = sizeof 4lu;
```
```D
int so6 = 4Lu.sizeof;
```

---
```C
int so7 = sizeof "abc";
```
```D
int so7 = ("abc".length + 1);
```

---
```C
int so7 = sizeof("abc");
```
```D
int so7 = ("abc".length + 1);
```

---
```C
int so8 = ((size_t) _glfw.monitorCount - 1) * sizeof(_GLFWmonitor*);
```
```D
int so8 = (cast(size_t) _glfw.monitorCount - 1) * (_GLFWmonitor*).sizeof;
```

---
```C
int so9 = sizeof(int) * 5;
```
```D
int so9 = int.sizeof * 5;
```

---
```C
int soA = sizeof(unsigned char) * 5;
```
```D
int soA = ubyte.sizeof * 5;
```

---
```C
int soB = sizeof(int*) * 5;
```
```D
int soB = (int*).sizeof * 5;
```

---
```C
int soC = sizeof(struct mg_dns_header);
```
```D
int soC = mg_dns_header.sizeof;
```

---
```C
int soD = sizeof(struct {int x; int y;});
```
```D
int soD = .sizeof;
```

---
```C
int soE = sizeof foo.ptr;
```
```D
int soE = foo.ptr.sizeof;
```

---
```C
int soF = sizeof x+y;
```
```D
int soF = (x+y).sizeof;
```

---
```C
int of = offsetof(S, f);
```
```D
int of = S.f.offsetof;
```

---
```C
int of = offsetof(S, f, g);
```
```D
int of = offsetof(S, f, g);
```

---
```C
int of = offsetof(struct S, f);
```
```D
int of = offsetof(struct S, f);
```
---
## Number literals
```C
float x = 1.f;
long long int y = 1ULL;
```
```D
float x = 1.0f;
long y = 1UL;
```

---
```C
float x = FLT_MAX;
```
```D
float x = float.max;
```

---
```C
int x = DBL_MAX_10_EXP + DBL_MAX_EXP;
```
```D
int x = double.max_10_exp + double.max_exp;
```

---
```C
int x = (int) 3.5;
```
```D
int x = cast(int) 3.5;
```

---
```C
int x = (void(*)()) NULL;
```
```D
int x = cast(void function()) null;
```

---
```C
typedef unsigned char X;
int c = (X)(5);
void main(void) {
	int d = (X)(6);
	int e = (*Y)(7);
	int f = (Y*)(7);
}
```
```D
alias X = ubyte;
int c = cast(X)(5);
void main() {
	int d = cast(X)(6);
	int e = (*Y)(7);
	int f = cast(Y*)(7);
}
```
---
## Statements
```C
int *bar(int y, ...) {
	while (x) {
	}
	for (;;);
	for (unsigned short x = 0;;);
	for (int x = 0, *y = NULL;;);

	switch (0) {
		case 1: break;
	}
	switch (0) {
		default: break;
	}
	T *t;
	return t->ptr;
}
```
```D
int* bar(int y, ...) {
	while (x) {
	}
	for (;;){}
	for (ushort x = 0;;){}
	for ({int x = 0; int* y = null;};){}

	switch (0) {
		case 1: break;
	default: break;}
	switch (0) {
		default: break;
	}
	T* t = void;
	return t.ptr;
}
```
---
## Assignments in conditions
```C
void main() {
	if (x=30) {}
	while (x=40) {}
	for (; x=50; ) {}
	if (x==60) {}
}
```
```D
void main() {
	if ((x=30) != 0) {}
	while ((x=40) != 0) {}
	for (; (x=50) != 0; ) {}
	if (x==60) {}
}
```

---
```C
void main() {
	int x = !(y = 3) + 4;
	while (!(x = 5)) { break; }

}
```
```D
void main() {
	int x = ((y = 3) == 0) + 4;
	while (((x = 5) == 0)) { break; }

}
```
---
## Strings
```C
const char *p0 = "con" "cat" "enated";
char const *p1;
char *const p2;
const char p3[] = "abc", p4[] = "";
const char p5[] = "\nab" "\x22" "";
char p6[] = MACRO;
```
```D
const(char)* p0 = "con" ~ "cat" ~ "enated";
const(char)* p1;
char* p2;
const(char)[4] p3 = "abc"; const(char)[1] p4 = "";
const(char)[5] p5 = "\nab" ~ "\x22" ~ "";
char[$] p6 = MACRO;
```

---
```C
wchar_t p3;
```
```D
import core.stdc.stddef: wchar_t;
wchar_t p3;
```
---
## Structured initializers
```C
int x[4] = { 0 };
int y[4] = { 1 };
void main() {
	int z[4] = { 0 };
	float w[4] = {};
}
int b[4] = { 0, 1 };
```
```D
int[4] x = 0;
int[4] y = [ 1 ];
void main() {
	int[4] z = 0;
	float[4] w = 0;
}
int[4] b = [ 0, 1 ];
```

---
```C
Rectangle r = (Rectangle){0l, y, width, height};
```
```D
Rectangle r = Rectangle(0L, y, width, height);
```

---
```C
int x[] = { 0, 3, 5 /*comment*/ , 9 };
double y[];
void main() {
	int z[] = {10};
}
```
```D
int[4] x = [ 0, 3, 5 /*comment*/ , 9 ];
double[1] y = 0;
void main() {
	int[1] z = [10];
}
```

---
```C
int a[2] = {
	[0] = 1,
	[1] = 2,
};
```
```D
int[2] a = [
	0: 1,
	1: 2,
];
```

---
```C
INTARRAY a = {[0] = 1};
```
```D
INTARRAY a = [0: 1];
```

---
```C
S a = {
	.fieldA = 1,
	.fieldB = 2,
};
```
```D
S a = {
	fieldA: 1,
	fieldB: 2,
};
```

---
```C
struct S { double x; int y; }
Sarray[2] = {
	{1.5, 2},
	{2.5, 3}
};

struct S1 { struct { int y; }; } Sarray[1][1] = {{ {{2}} }};
```
```D
struct S { double x = 0; int y; }S[2] Sarray = [
	{1.5, 2},
	{2.5, 3}
];

struct S1 { struct  { int y; }; }S1[1][1] Sarray = [[ {{2}} ]];
```
---
## Preprocessor
```C
#include <assert.h>
#include <string.h>
# include <stdio.h>
#include "small.c"
#include <winuser.h>
#include <linux/limits.h>
#include <sys/inotify.h>
#include <sys/timerfd.h>
#include <sys/ioctl.h>
#include "my/lib.h"
#include <pthread.h>
#include <cfile.c>
#include <x>
```
```D
import core.stdc.assert_;
import core.stdc.string;
import core.stdc.stdio;
import small;
import core.sys.windows.winuser;
import core.stdc.limits;
import core.sys.linux.sys.inotify;
import core.sys.linux.sys.timerfd;
import core.sys.posix.sys.ioctl;
import my.lib;
import core.sys.posix.pthread;
import cfile;
import x;
```

---
```C
#undef X
```
```D
```

---
```C
#ifndef NO_HEADER_GUARD
#define NO_HEADER_GUARD 3
#endif
```
```D
enum NO_HEADER_GUARD = 3;

```

---
```C
#ifndef CONDITION
#define NOT_THE_IFNDEF_CONDITION 99
#endif
```
```D
version (CONDITION) {} else {
enum NOT_THE_IFNDEF_CONDITION = 99;
}
```

---
```C
#define TEST
#define PI 3.14159265
#define LOL(x)
```
```D
version = TEST;
enum PI = 3.14159265;
//#define LOL(x)
```

---
```C
#define MY_INT int
```
```D
alias MY_INT = int;
```

---
```C
#define KEY_LENGTH_TYPE uint8_t
```
```D
alias KEY_LENGTH_TYPE = ubyte;
```

---
```C
#define MY_SHORT short
```
```D
enum MY_SHORT = short;
```

---
```C
#define SQR(x) (x*x)
int x = SQR(3);
#define MIN(a,b) (((a)<(b))?(a):(b))
int y = MIN(1,2);
```
```D
enum string SQR(string x) = `(` ~ x ~ `*` ~ x ~ `)`;
int x = mixin(SQR!(`3`));
enum string MIN(string a,string b) = `(((` ~ a ~ `)<(` ~ b ~ `))?(` ~ a ~ `):(` ~ b ~ `))`;
int y = mixin(MIN!(`1`,`2`));
```

---
```C
#define WITHCOMMENT//c
#define WITHCOMMENT1 '@'// c
#define WITHCOMMENTS /*a*/ '@' /*b*/ // c
```
```D
version = WITHCOMMENT;//c
enum WITHCOMMENT1 = '@';// c
enum WITHCOMMENTS /*a*/ = '@' /*b*/; // c
```

---
```C
#define _CONCAT_VERSION(m, n, r) #m "." #n "." #r
#define _MAKE_VERSION(m, n, r) _CONCAT_VERSION(m, n, r)
```
```D
enum string _CONCAT_VERSION(string m, string n, string r) = `#m "." #n "." #r`;
enum string _MAKE_VERSION(string m, string n, string r) = `` ~ _CONCAT_VERSION!(` ~ `m` ~ `, ` ~ `n` ~ `, ` ~ `r` ~ `) ~ ``;
```

---
```C
#define _VERSION_NUMBER _MAKE_VERSION(VERSION_MAJOR, \
	VERSION_MINOR, \
	VERSION_REVISION)
```
```D
enum _VERSION_NUMBER = _MAKE_VERSION(VERSION_MAJOR, \
	VERSION_MINOR, \
	VERSION_REVISION);
```

---
```C
#define MIN(a,b) (((a)<(b))?(a):(b))
pixels[y*image->width + x+1].r = MIN((int)pixels[y*image->width + x+1].r + (int)((float)rError*7.0f/16), 0xff);
```
```D
enum string MIN(string a,string b) = `(((` ~ a ~ `)<(` ~ b ~ `))?(` ~ a ~ `):(` ~ b ~ `))`;
pixels[y*image.width + x+1].r = mixin(MIN!(`cast(int)pixels[y*image.width + x+1].r + cast(int)(cast(float)rError*7.0f/16)`, `0xff`));
```

---
```C
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
```
```D
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
```

---
```C
#if 0
#error "error message"
#elif defined(__APPLE__)
// whoo
#endif
```
```D
version (none) {
static assert(0, "error message");
} else version (OSX) {
// whoo
}
```

---
```C
#ifndef _WIN32
	int x;
#else
	int y;
#endif
```
```D
version (Windows) {} else {
	int x;
} version (Windows) {
	int y;
}
```

---
```C
#if !defined(_WIN32)
	#define PLATFORM WINDOWS
#endif
```
```D

private template HasVersion(string versionId) {
	mixin("version("~versionId~") {enum HasVersion = true;} else {enum HasVersion = false;}");
}
static if (!HasVersion!"Windows") {
	enum PLATFORM = WINDOWS;
}
```
---
Tree-sitter doesn't parse this right, this does manual preprocessing
```C
uint8_t x = 1;
#ifdef __cplusplus
extern "C" {
#endif
uint8_t y = 2;
#ifdef __cplusplus
} // extern "C"
#endif
uint8_t z = 3;
```
```D
ubyte x = 1;
ubyte y = 2;
ubyte z = 3;
```
---
## va_arg

It has failures currently because tree-sitter doesn't parse types in calls
```C
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
```
```D
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
```
---
TODO: prevent disappearing source code
```C
void main(void) {
	if (1) {}
#if defined(SUPPORT_XXX)
	else if (cmp(n, "XXX")) x = LoadX(n, 0);
#endif
}
```
```D
void main() {
	if (1) {}
version (SUPPORT_XXX) {
	else if = LoadX(n, 0);
}
}
```
---
Strip backslash before newline
```C
int x = 3\
*4;
```
```D
int x = 3
*4;
```
---
## Wide characters
```C
wchar_t *x = L"Msg";
```
```D
import core.stdc.stddef: wchar_t;
wchar_t* x = "Msg"w;
```

---
```C
char16_t *x = u"Msg";
```
```D
wchar* x = "Msg"w;
```

---
```C
char32_t *x = U"Msg";
```
```D
dchar* x = "Msg"d;
```

---
```C
wchar_t  b = L'\xFFEF';
```
```D
import core.stdc.stddef: wchar_t;
wchar_t b = wchar('\xFFEF');
```

---
```C
char16_t c = u'\u00F6';
```
```D
wchar c = wchar('\u00F6');
```

---
```C
char32_t d = U'\U0010FFFF';
```
```D
dchar d = dchar('\U0010FFFF');
```
---
Remove forward declaration
```C
void f(void);
void f(void) { }
```
```D

void f() { }
```

---
```C
void f(void), g(float);
```
```D
void f(); void g(float);
```

---
```C
void f(), g();
```
```D
void f(); void g();
```
---
Missing identifier field requires null check to prevent segfault
```C
void () {}
```
```D
void {}
```
---
Time complexity test:
Accidental binary recursion when constructing the node tree gave exponential time complexity
This test won't finish in a reasonable time if that happens again
```C
int y = (((((((((((((((((((((((((((((((((((((((((((((((((((((x)))))))))))))))))))))))))))))))))))))))))))))))))))));
```
```D
int y = (((((((((((((((((((((((((((((((((((((((((((((((((((((x)))))))))))))))))))))))))))))))))))))))))))))))))))));
```
---