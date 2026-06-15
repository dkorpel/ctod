/**
Helper functions / dependencies
*/
module ctod.util;
@safe:

version (none)
{
	public import bops.ds.hashtable : Map = HashTable;
	public import bops.ascii : isWhite;
	public import bops.outbuffer;
	public import bops.string : startsWith, stripWhite;
	public import bops.stdio;
	public import bops.range : splitter, front, back;
	public import bops.test : assertEq;

	version (WebAssembly)
	{
	}
	else
	{
		public import bops.file : fileReadText;
	}

	void mapClear(T)(ref T map)
	{
		map.clear();
	}

	auto extractOutBuffer(ref OutBuffer o) @trusted
	{
		return cast(string) o[];
	}
}
else
{
	void assertEq(T, U)(T l, U r)
	{
		assert(l == r);
	}

	void assertTrue(T)(T v)
	{
		assert(v);
	}

	void assertFalse(T)(T v)
	{
		assert(!v);
	}

	public import std.algorithm.searching : startsWith;
	public import std.ascii : isWhite, toUpper;
	public import std.string : stripWhite = strip;
	public import std.algorithm.iteration : splitter;
	public import std.stdio : stderr, writeln;
	public import std.range : front, back;
	public import ctod.arena : Allocator, Arena, Array, gc, dup;
	import std.array;
	import std.file : read;
	static import std.format;

	alias OutBuffer = Appender!string;

	// The monorepo names this `extractString`; here it just reads the Appender.
	alias extractString = extractOutBuffer;

	// `format(fmt, args)` builds a string; `buf.format(fmt, args)` appends into
	// an OutBuffer (the monorepo's OutBuffer has a `format` member).
	string format(Args...)(string fmt, Args args) => std.format.format(fmt, args);

	void format(Args...)(ref OutBuffer o, string fmt, Args args)
	{
		std.format.formattedWrite(o, fmt, args);
	}

	// Enable switching to custom Associative Array type
	alias Map(K, V) = V[K];

	// Workaround for older compiler versions where `aa.clear` wasn't `@safe`
	void mapClear(T)(ref T map) @trusted if (is(T == K[V], K, V))
	{
		map.clear();
	}

	auto extractOutBuffer(ref OutBuffer o)
	{
		return o.data();
	}

	string fileReadText(string path) @trusted
	{
		version(Windows)
		{
			import std.string;
			return (cast(string) read(path)).replace("\r", "");
		}
		else
			return cast(string) read(path);
	}
}
