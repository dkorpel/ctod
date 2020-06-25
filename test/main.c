#include <assert.h>
#include <string.h>
#include <stdio.h>

#define TEST
#define PI 3.14159265
#define SQR(x) (x*x)

#ifdef TEST
// whoo
#else
// whoo
#endif

#if 0
// whoo
#elif defined(TEST)
// whoo
#endif

unsigned int x;

struct S {
	int in;
	int out;
};

static float x[8] = {0.5, 2.5};
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