/// Translated from C to D
module main;

extern(C): @nogc: nothrow:
import core.stdc.assert_;
import core.stdc.string;
import core.stdc.stdio;

version = TEST;
enum PI= 3.14159265;
auto SQR(T)(x){return  (x*x);}

version( TEST) {
// whoo
} else {
// whoo
}

static if ( 0
// whoo
} else static if ( defined(TEST)
// whoo
}

 int x;

struct S {
	int in_;
	int out_;
};

static float x[8] = [0.5, 2.5];
double z[4][3];

int main(void) {
	static int x;
	int a[2];
	foo(a, main);
	return 0;
}

void foo(int x[], int (*y)(void)) {
	int *z, y;
}