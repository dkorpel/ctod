#include <assert.h>
#include <string.h>
#include <stdio.h>

unsigned int x;

struct S {
	int in;
	int out;
};

static float x[8] = {0.5, 2.5};

int main(void) {
	int a[2];
	foo(a, main);
	return 0;
}

void foo(int x[], int (*y)(void)) {

}