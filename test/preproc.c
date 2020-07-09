#pragma once

#include <assert.h>
#include <string.h>
# include <stdio.h>
#include "small.c"

#define TEST
#define PI 3.14159265
#define LOL(x)
#define SQR(x) (x*x)

#define _GLFW_CONCAT_VERSION(m, n, r) #m "." #n "." #r
#define _GLFW_MAKE_VERSION(m, n, r) _GLFW_CONCAT_VERSION(m, n, r)
#define _GLFW_VERSION_NUMBER _GLFW_MAKE_VERSION(GLFW_VERSION_MAJOR, \
                                                GLFW_VERSION_MINOR, \
                                                GLFW_VERSION_REVISION)

#ifdef _WIN32
// test
#else
// no test
#endif

#if 0
#error "error message"
#elif defined(__APPLE__)
// whoo
#endif

#if !defined(_WIN32)
	#define CUTE_TIME_PLATFORM CUTE_TIME_WINDOWS
#endif

#undef X