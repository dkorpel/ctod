/// Translated from C to D
module cute_time;

extern(C): @nogc: nothrow:
/*
	------------------------------------------------------------------------------
		Licensing information can be found at the end of the file.
	------------------------------------------------------------------------------
	cute_time.h - v1.00
	To create implementation (the function definitions)
		#define CUTE_TIME_IMPLEMENTATION
	in *one* C/CPP file (translation unit) that includes this file
*/
static if (!defined(CUTE_TIME_H)) {

import core.stdc.stdint;

alias  ct_timer_t ct_timer_t;

// quick and dirty elapsed time since last call
float ct_time();

// high precision timer functions found below

// Call once to setup this timer on this thread
// does a cs_record call
void ct_init_timer(ct_timer_t* timer);

// returns raw ticks in platform-specific units between now-time and last cs_record call
long ct_elapsed(ct_timer_t* timer);

// ticks to seconds conversion
long ct_seconds(ct_timer_t* timer, long ticks);

// ticks to milliseconds conversion
long ct_milliseconds(ct_timer_t* timer, long ticks);

// ticks to microseconds conversion
long ct_microseconds(ct_timer_t* timer, long ticks);

// records the now-time in raw platform-specific units
void cs_record(ct_timer_t* timer);

enum CUTE_TIME_WINDOWS	1
enum CUTE_TIME_MAC		2
enum CUTE_TIME_UNIX		3

static if (defined(_WIN32)) {
	enum CUTE_TIME_PLATFORM CUTE_TIME_WINDOWS
else static if defined(__APPLE__)
	enum CUTE_TIME_PLATFORM CUTE_TIME_MAC
else
	enum CUTE_TIME_PLATFORM CUTE_TIME_UNIX
}

static if (CUTE_TIME_PLATFORM == CUTE_TIME_WINDOWS) {

	struct ct_timer_t
	{
		LARGE_INTEGER freq;
		LARGE_INTEGER prev;
	};

else static if CUTE_TIME_PLATFORM == CUTE_TIME_MAC
else
}

enum CUTE_TIME_H
}

#ifdef CUTE_TIME_IMPLEMENTATION
#ifndef CUTE_TIME_IMPLEMENTATION_ONCE
enum CUTE_TIME_IMPLEMENTATION_ONCE

// These functions are intended be called from a single thread only. In a
// multi-threaded environment make sure to call Time from the main thread only.
// Also try to set a thread affinity for the main thread to avoid core swaps.
// This can help prevent annoying bios bugs etc. from giving weird time-warp
// effects as the main thread gets passed from one core to another. This shouldn't
// be a problem, but it's a good practice to setup the affinity. Calling these
// functions on multiple threads multiple times will grant a heft performance
// loss in the form of false sharing due to CPU cache synchronization across
// multiple cores.
// More info: https://msdn.microsoft.com/en-us/library/windows/desktop/ee417693(v=vs.85).aspx

static if (CUTE_TIME_PLATFORM == CUTE_TIME_WINDOWS) {

	float ct_time()
	{
		static int first = 1;
		static LARGE_INTEGER prev;
		static double factor;

		LARGE_INTEGER now;
		QueryPerformanceCounter(&now);

		if (first)
		{
			first = 0;
			prev = now;
			LARGE_INTEGER freq;
			QueryPerformanceFrequency(&freq);
			factor = 1.0 / cast(double)freq.QuadPart;
			return 0;
		}

		float elapsed = cast(float)(cast(double)(now.QuadPart - prev.QuadPart) * factor);
		prev = now;
		return elapsed;
	}

	void ct_init_timer(ct_timer_t* timer)
	{
		QueryPerformanceCounter(&timer.prev);
		QueryPerformanceFrequency(&timer.freq);
	}

	long ct_elapsed(ct_timer_t* timer)
	{
		LARGE_INTEGER now;
		QueryPerformanceCounter(&now);
		return cast(long)(now.QuadPart - timer.prev.QuadPart);
	}

	long ct_seconds(ct_timer_t* timer, long ticks)
	{
		return ticks / timer.freq.QuadPart;
	}

	long ct_milliseconds(ct_timer_t* timer, long ticks)
	{
		return ticks / (timer.freq.QuadPart / 1000);
	}

	long ct_microseconds(ct_timer_t* timer, long ticks)
	{
		return ticks / (timer.freq.QuadPart / 1000000);
	}

	void cs_record(ct_timer_t* timer)
	{
		QueryPerformanceCounter(&timer.prev);
	}

else static if CUTE_TIME_PLATFORM == CUTE_TIME_MAC

	import <mach/mach_time.h>

	float ct_time()
	{
		static int first = 1;
		static ulong prev = 0;
		static double factor;

		if (first)
		{
			first = 0;
			mach_timebase_info_data_t info;
			mach_timebase_info(&info);
			factor = cast(double)info.numer / (cast(double)info.denom * 1.0e9);
			prev = mach_absolute_time();
			return 0;
		}

		ulong now = mach_absolute_time();
		float elapsed = cast(float)(cast(double)(now - prev) * factor);
		prev = now;
		return elapsed;
	}

else

	import core.stdc.time;

	float ct_time()
	{
		static int first = 1;
		static  timespec prev;

		if (first)
		{
			first = 0;
			clock_gettime(CLOCK_MONOTONIC, &prev);
			return 0;
		}

		 timespec now;
		clock_gettime(CLOCK_MONOTONIC, &now);
		float elapsed = cast(float)(cast(double)(now.tv_sec - prev.tv_sec) + (cast(double)(now.tv_nsec - prev.tv_nsec) * 1.0e-9));
		prev = now;
		return elapsed;
	}

}

} // CUTE_TIME_IMPLEMENTATION_ONCE
} // CUTE_TIME_IMPLEMENTATION
