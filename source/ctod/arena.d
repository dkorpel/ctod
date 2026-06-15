/**
Basic wrappers for manual memory management
*/
module ctod.arena;
@safe:

struct Allocator
{
	T* newItem(T)() => new T;

	T[] newArray(T)(size_t length) => new T[length];
}

struct Arena
{
	Allocator alloc() return => Allocator.init;
}

enum Allocator gc = Allocator.init;

T[] dup(T)(scope const(T)[] s, Allocator)
{
	auto r = new T[s.length];
	r[] = s[];
	return r;
}

struct Array(T)
{
	private T[] items;

	void opOpAssign(string op : "~")(T x) @trusted
	{
		items ~= x;
	}

	void opOpAssign(string op : "~")(scope T[] xs) @trusted
	{
		items ~= xs;
	}

	size_t length() const scope => items.length;
	size_t opDollar() const scope => items.length;

	ref inout(T) opIndex(size_t i) inout @trusted => items[i];
	inout(T)[] opSlice() inout @trusted => items;

	/// Drop the last element.
	void pop() @trusted
	{
		items = items[0 .. $ - 1];
	}

	int opApply(scope int delegate(ref T) @safe dg) @trusted
	{
		foreach (ref x; items)
		{
			if (const r = dg(x))
				return r;
		}
		return 0;
	}
}
