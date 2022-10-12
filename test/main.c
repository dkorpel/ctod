
#define _GLFW_CONCAT_VERSION(m, n, r) #m "." #n "." #r
#define _GLFW_MAKE_VERSION(m, n, r) _GLFW_CONCAT_VERSION(m, n, r)
#define _GLFW_VERSION_NUMBER _GLFW_MAKE_VERSION(GLFW_VERSION_MAJOR, \
                                                GLFW_VERSION_MINOR, \
                                                GLFW_VERSION_REVISION)



#endif

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

typedef struct T {
	S *ptr;
	int arr[3];
	int32_t capacity;
	__u8 type;
} T;

char * const(*(* const bar)[5])(int);

int (*f2)(enum {a} param0, struct {int x;} param1);

extern inline int e0;

static float x[8] = {1.f, 2.5};
double z[4][3];

int main(void) {
	static int xx;
	static int x = (int) 3.5;
	static int x = (void(*)()) NULL;
	int so6 = ((size_t) _glfw.monitorCount - 1) * sizeof(_GLFWmonitor*);
	int a[2], (*b)[2];
	foo(a, b, bar);
	int* a = malloc(4);
	a = calloc(4);
	return 0;
}

inline static void foo(int x[], int (*y)(void)) {
	int *z, y;
	float x = 1.f;
}
