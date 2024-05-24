/**
Helper functions / dependencies
*/
module ctod.util;

@safe:

version(none)
{
	public import bops.ds.hashtable: Map = HashTable;
	public import bops.ascii: isWhite;
	public import bops.outbuffer;
	public import bops.string: startsWith, stripWhite;
	public import bops.stdio;
	public import bops.test: assertEq;

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
	void assertEq(T, U)(T l, U r) { assert(l == r); }
	public import std.algorithm.searching: startsWith;
	public import std.ascii: isWhite;
	public import std.string: stripWhite = strip;
	import std.array;
	alias OutBuffer = Appender!string;

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
}
