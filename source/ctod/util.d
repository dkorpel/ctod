/**
Helper functions / dependencies
*/
module ctod.util;

version(none)
{
	public import bops.ds.hashtable: Map = HashTable;
	public import bops.ascii: isWhite;
	public import bops.string: startsWith, stripWhite;
}
else
{
	void assertEq(T, U)(T l, U r) { assert(l == r); }
	public import std.algorithm.searching: startsWith;
	public import std.ascii: isWhite;
	public import std.string: stripWhite = strip;
	// Enable switching to custom Associative Array type
	alias Map(K, V) = V[K];
}
