module main;
extern(C): @nogc: nothrow: __gshared:
import core.stdc.config: c_long, c_ulong;
import core.stdc.stddef: wchar_t;
struct S {
	int in_;
	ubyte[2] out_;
}

struct _Bitfields {
	ushort x;/+: 12 !!+/
    ushort y;/+: int.sizeof !!+/
}_Bitfields bitfields;

union U {
	char tag;

	union _Overlapped {
		int[2] x;
		enum _Y {one, two}_Y y;
	}_Overlapped overlapped;
}

struct S ;
union U ;
struct S0 ;alias S0 S1;
union U0 ;alias U0 U1;
alias int[3] intArr;alias int intScalar;
struct OpaqueS;
union OpaqueU;

struct T {
	S* ptr;
	int[3] arr;
	int capacity;
	ubyte type;
}

enum AnEnum {
	one = 1000123000,
	two = 0x7FFFFFFF
}

uint x0;
c_long x1;
c_ulong x2;
long x3;
ulong x4;
c_ulong x5;
float x6;
double x7;
real x8;
struct S ;S x9;
S xA;

const(char)* p0 = "con" ~ "cat" ~ "enated";
const(char)* p1;
char* p2;
wchar_t p3;

char* function(int)[5]* bar;

int[1] a0;
int*[2] a1;
int[3]* a2;
int[5][4] a3;
int*[7][6] a4;
int*[9][8]* a5;
int**[9][8] a6;

void function(int x, float, char*, char, char*, char***) f0;
int function()[4] f1;
enum _Param0 {a}struct _Param1 {int x;}int function(_Param0 param0, _Param1 param1) f2;

pragma(inline, true) extern int e0;

private float[8] x = [1.0f, 2.5];
double[3][4] z;

c_ulong* bar(c_long y, ...) {
	while(x) {
	}
	for(;;){}
	for(ushort x = 0;;){}
	switch (0) {
		case 1: break;
	default: break;}
	T* t;
	return t.ptr;
}

int main() {
	static int xx;
	static int x = cast(int) 3.5;
	static int x = cast(void function()) null;
	//int so0 = sizeof short;
	int so1 = int.sizeof;
	int so2 = sizeof 4Lu;
	int so2 = typeof(4).sizeof;
	int so3 = typeof(cast(short) 3 + 4L).sizeof;
	int so4 = unsigned short.sizeof;
	int so5 = GLFWvidmode.sizeof;
	int so6 = (cast(size_t) _glfw.monitorCount - 1) * _GLFWmonitor*.sizeof;
	int[2] a;int[2]* b;
	foo(a.ptr, b, &bar);
	int* a = malloc(4);
	a = calloc(4);
	return 0;
}


pragma(inline, true) private void foo(int* x, int function() y);

pragma(inline, true) private void foo(int* x, int function() y) {
	int* z;int y;
	float x = 1.0f;
}