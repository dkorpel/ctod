#include <assert.h>
#include <string.h>
#include <stdio.h>

#include "../include/glfw.h"

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

#if defined(_WIN32)
	#define CUTE_TIME_PLATFORM CUTE_TIME_WINDOWS
#elif defined(__APPLE__)
	#define CUTE_TIME_PLATFORM CUTE_TIME_MAC
#else
	#define CUTE_TIME_PLATFORM CUTE_TIME_UNIX
#endif

unsigned int x;

struct S {
	int in;
	int out;
};

typedef struct S S;

typedef struct T {
	S *ptr;
} T;

static float x[8] = {0.5, 2.5};
double z[4][3];

int main(void) {
	static int x = cast(int) 3.5;
	int a[2];
	foo(a, main);
	return 0;
}

void foo(int x[], int (*y)(void)) {
	int *z, y;
}
