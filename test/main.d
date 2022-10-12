module main;
@nogc nothrow:
extern(C): __gshared:


enum string _GLFW_CONCAT_VERSION(string m, string n, string r) = ` #m "." #n "." #r`;
enum string _GLFW_MAKE_VERSION(string m, string n, string r) = ` _GLFW_CONCAT_VERSION(m, n, r)`;
enum _GLFW_VERSION_NUMBER = _GLFW_MAKE_VERSION(GLFW_VERSION_MAJOR, \
                                                GLFW_VERSION_MINOR, \
                                                GLFW_VERSION_REVISION);



//! #endif

union U {
	char tag;

	union _Overlapped {
		int[2] x;
		enum _Y {one, two}_Y y;
	}_Overlapped overlapped;
}



alias S0 S1;
alias U0 U1;
alias int[3] intArr;alias int intScalar;

struct T {
	S* ptr;
	int[3] arr;
	int capacity;
	ubyte type;
}

char* function(int)[5]* bar;

enum _Param0 {a}struct _Param1 {int x;}int function(_Param0 param0, _Param1 param1) f2;

pragma(inline, true) extern int e0;

private float[8] x = [1.0f, 2.5];
double[3][4] z;

int main() {
	static int xx;
	static int x = cast(int) 3.5;
	static int x = cast(void function()) null;
	int so6 = (cast(size_t) _glfw.monitorCount - 1) * _GLFWmonitor*.sizeof;
	int[2] a;int[2]* b;
	foo(a.ptr, b, bar);
	int* a = malloc(4);
	a = calloc(4);
	return 0;
}

pragma(inline, true) private void foo(int* x, int function() y) {
	int* z;int y;
	float x = 1.0f;
}
