
struct S {
	int in;
	unsigned char out[2];
};

struct {
	unsigned short x : 12;
    unsigned short y : sizeof(int);
} bitfields;

union U {
	char tag;

	union
	{
		int x[2];
		enum {one, two} y;
	} overlapped;
};

typedef struct S S;
typedef union U U;
typedef struct S0 S1;
typedef union U0 U1;
typedef int intArr[3], intScalar;
struct OpaqueS;
union OpaqueU;

typedef struct T {
	S *ptr;
	int arr[3];
} T;

typedef enum AnEnum
{
	one = 1000123000,
	two = 0x7FFFFFFF
} AnEnum;

unsigned int x0;
long x1;
unsigned long x2;
long long x3;
unsigned long long x4;
unsigned long x5;
float x6;
double x7;
long double x8;
struct S x9;
S xA;

const char *p0 = "con" "cat" "enated";
char const *p1;
char *const p2;
wchar_t p3;

int a0[1];
int *a1[2];
int (*a2)[3];
int a3[4][5];
int *a4[6][7];
int *(*a5)[8][9];
int **a6[8][9];

void (*f0)(int x, float, char*, char[], char*[], char***);
int (*f1[4])(void);
int (*f2)(enum {a} param0, struct {int x;} param1);

extern inline int e0;

static float x[8] = {1.f, 2.5};
double z[4][3];

int main(void) {
	static int xx;
	static int x = (int) 3.5;
	static int x = (void(*)()) NULL;
	//int so0 = sizeof short;
	int so1 = sizeof(int);
	int so2 = sizeof 4lu;
	int so2 = sizeof (4);
	int so3 = sizeof((short) 3 + 4l);
	int a[2];
	foo(a, main);
	return 0;
}

unsigned long *bar(long y, ...) {
	while(x) {
	}
	for(;;);
	switch (0) {
		case 1: break;
	}
	T *t;
	return t->ptr;
}

inline static void foo(int x[], int (*y)(void));

inline static void foo(int x[], int (*y)(void)) {
	int *z, y;
	float x = 1.f;
}
