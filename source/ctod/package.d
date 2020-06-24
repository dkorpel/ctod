module ctod;

/// Returns: C language parser for tree-sitter
import tree_sitter.api;
extern(C) TSLanguage* tree_sitter_c();

public {
	import ctod.cfunction;
	import ctod.cmacro;
	import ctod.cinclude;
	import ctod.ctype;
}

version(none):

immutable source = `

int sqr(int x) {
	return SQR(x);
}
`;

immutable sourceAlt = `
#include <stdio.h>
#include "mymodule.h"

typedef char *test;

#define X 3
#define SQR(x) (x * x)

#ifdef 0

#endif

// My nice struct
struct Test {
	unsigned int x;
	int *y;
};

int main(void) {
	while(x) {
		foo();
	}
	Test *t;
	t->x = 3;
	return 0;
}
`;