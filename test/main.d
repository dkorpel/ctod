/// Translated from C to D
module main;

extern(C): @nogc: nothrow:
public import core.stdc.assert_;
public import core.stdc.string;
public import core.stdc.stdio;

public import ...include.glfw;

version = TEST
enum PI = 3.14159265;
auto SQR(x){return (x*x);}

version (TEST) {
// whoo
} else {
// whoo
}

static if (0) {
// whoo
} else static if (HasVersion!"TEST") {
// whoo
}

static if (HasVersion!"Windows") {
	enum CUTE_TIME_PLATFORM = CUTE_TIME_WINDOWS;
} else static if (HasVersion!"OSX") {
	enum CUTE_TIME_PLATFORM = CUTE_TIME_MAC;
} else {
	enum CUTE_TIME_PLATFORM = CUTE_TIME_UNIX;
}

 int x;

struct S {
	int in_;
	int out_;
};

alias struct S S;

alias struct T {
	S *ptr;
} T;

private float x[8] = [0.5, 2.5];
double z[4][3];

int main(void) {
	private int x = cast(int) 3.5;
	int a[2];
	foo(a, main);
	return 0;
}

void foo(int x[], int (*y)(void)) {
	int *z, y;
}