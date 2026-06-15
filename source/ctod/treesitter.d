/**
D port of the tree-sitter runtime (parser + node API) used by ctod.

This replaces the C library in lib/tree-sitter/src. Only the subset that ctod
needs is implemented: parsing a single contiguous UTF-8 buffer and walking the
resulting syntax tree. The following upstream features are intentionally
dropped because ctod never uses them:

  - incremental reparsing (old_tree is always null), reusable nodes, tree edits
  - external scanners (the C grammar has EXTERNAL_TOKEN_COUNT == 0)
  - queries, tree cursors, changed-range computation
  - parse timeouts / cancellation
  - multiple included ranges (always the full document)

Memory model: everything is allocated from a single Arena owned by the parser
and freed wholesale when the parser is destroyed. There is therefore no
reference counting; `retain`/`release` are no-ops, `make_mut` always clones, and
tree balancing (a cursor-performance optimization) is skipped. The returned tree
points into the parser's arena and is valid as long as the parser lives.
*/
module ctod.treesitter;

// This is a low-level port of C pointer code, so it is @system throughout.
// ctod calls into it through the @trusted wrappers in ctod.tree_sitter.

import ctod.arena : Allocator, Arena;
import std.algorithm.comparison : min, max;
import std.algorithm.mutation : swap, move;

// Raw mem routines, used for the faithful array port.
import core.stdc.string : memcpy, memmove, memset, memcmp;

/********************/
/* Section - Types  */
/********************/

alias TSSymbol = ushort;
alias TSStateId = ushort;
alias TSFieldId = ushort;

enum TSSymbol tsBuiltinSymError = cast(TSSymbol) -1;
enum TSSymbol tsBuiltinSymEnd = 0;
enum TSSymbol tsBuiltinSymErrorRepeat = cast(TSSymbol)(tsBuiltinSymError - 1);

enum uint TREE_SITTER_LANGUAGE_VERSION = 14;
enum uint TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION = 13;

enum uint TS_TREE_STATE_NONE = ushort.max;

// error_costs.h
enum ERROR_STATE = 0;
enum ERROR_COST_PER_RECOVERY = 500;
enum ERROR_COST_PER_MISSING_TREE = 110;
enum ERROR_COST_PER_SKIPPED_TREE = 100;
enum ERROR_COST_PER_SKIPPED_LINE = 30;
enum ERROR_COST_PER_SKIPPED_CHAR = 1;

enum TSInputEncoding
{
	utf8 = 0,
	utf16 = 1,
}

enum TSSymbolType
{
	regular = 0,
	anonymous = 1,
	auxiliary = 2,
}

struct TSPoint
{
	uint row;
	uint column;
}

struct TSRange
{
	TSPoint startPoint;
	TSPoint endPoint;
	uint startByte;
	uint endByte;
}

/// Public node handle. Layout matches the C TSNode that ctod's bindings expect.
struct TSNode
{
	uint[4] context;
	const(void)* id;
	const(TSTree)* tree;

	private TSSymbol aliasSymbol() const => cast(TSSymbol) context[3];

	private NodeChildIterator iterateChildren() const @trusted
	{
		Subtree subtree = ts_node__subtree(this);
		if (tsSubtreeChildCount(subtree) == 0)
		{
			return NodeChildIterator(NULL_SUBTREE, tree, lengthZero(), 0, 0, null);
		}
		const(TSSymbol)* aliasSequence = tree.language.aliasSequence(subtree.ptr.productionId);
		NodeChildIterator it;
		it.tree = tree;
		it.parent = subtree;
		it.position = Length(tsNodeStartByte(this), tsNodeStartPoint(this));
		it.childIndex = 0;
		it.structuralChildIndex = 0;
		it.aliasSequence = aliasSequence;
		return it;
	}
}

// parser.h ABI types ------------------------------------------------------

struct TSFieldMapEntry
{
	TSFieldId fieldId;
	ubyte childIndex;
	bool inherited;
}

struct TSFieldMapSlice
{
	ushort index;
	ushort length;
}

struct TSSymbolMetadata
{
	bool visible;
	bool named;
	bool supertype;
}

enum TSParseActionType : ubyte
{
	shift,
	reduce,
	accept,
	recover,
}

union TSParseAction
{
	struct Shift
	{
		ubyte type;
		TSStateId state;
		bool extra;
		bool repetition;
	}

	struct Reduce
	{
		ubyte type;
		ubyte childCount;
		TSSymbol symbol;
		short dynamicPrecedence;
		ushort productionId;
	}

	Shift shift;
	Reduce reduce;
	ubyte type;
}

struct TSLexMode
{
	ushort lexState;
	ushort externalLexState;
}

union TSParseActionEntry
{
	TSParseAction action;
	struct Entry
	{
		ubyte count;
		bool reusable;
	}

	Entry entry;
}

/// Function pointer types for the generated grammar's lex functions.
alias LexFn = extern (C) bool function(scope TSLexer* lexer, TSStateId state);

/// The compiled grammar definition. Built by the generated `tree_sitter_c()`.
/// Only the fields used by this runtime are kept (external scanner is omitted).
struct TSLanguage
{
	uint version_;
	uint symbolCount;
	uint aliasCount;
	uint tokenCount;
	uint externalTokenCount;
	uint stateCount;
	uint largeStateCount;
	uint productionIdCount;
	uint fieldCount;
	ushort maxAliasSequenceLength;
	const(ushort)* parseTable;
	const(ushort)* smallParseTable;
	const(uint)* smallParseTableMap;
	const(TSParseActionEntry)* parseActions;
	const(char*)* symbolNames;
	const(char*)* fieldNames;
	const(TSFieldMapSlice)* fieldMapSlices;
	const(TSFieldMapEntry)* fieldMapEntries;
	const(TSSymbolMetadata)* symbolMetadata_;
	const(TSSymbol)* publicSymbolMap;
	const(ushort)* aliasMap;
	const(TSSymbol)* aliasSequences;
	const(TSLexMode)* lexModes;
	LexFn lexFn;
	LexFn keywordLexFn;
	TSSymbol keywordCaptureToken;
	const(TSStateId)* primaryStateIds;

	// The C grammar has no external scanner, so no states are ever enabled.
	const(bool)* enabledExternalTokens(uint externalScannerState) const => null;

	bool isSymbolExternal(TSSymbol symbol) const
	{
		return 0 < symbol && symbol < externalTokenCount + 1;
	}

	// Lookup the table value for a given symbol and state.
	ushort lookup(TSStateId state, TSSymbol symbol) const @trusted
	{
		if (state >= largeStateCount)
		{
			uint index = smallParseTableMap[state - largeStateCount];
			const(ushort)* data = &smallParseTable[index];
			ushort groupCount = *(data++);
			foreach (i; 0 .. groupCount)
			{
				ushort sectionValue = *(data++);
				ushort symbolCount = *(data++);
				foreach (j; 0 .. symbolCount)
				{
					if (*(data++) == symbol)
						return sectionValue;
				}
			}
			return 0;
		}
		else
		{
			return parseTable[state * symbolCount + symbol];
		}
	}

	void tableEntry(TSStateId state, TSSymbol symbol, ref TableEntry result) const @trusted
	{
		if (symbol == tsBuiltinSymError || symbol == tsBuiltinSymErrorRepeat)
		{
			result.actionCount = 0;
			result.isReusable = false;
			result.actions = null;
		}
		else
		{
			assert(symbol < tokenCount);
			uint actionIndex = this.lookup(state, symbol);
			const(TSParseActionEntry)* entry = &parseActions[actionIndex];
			result.actionCount = entry.entry.count;
			result.isReusable = entry.entry.reusable;
			result.actions = (cast(const(TSParseAction)*)(entry + 1))[0 .. entry.entry.count];
		}
	}

	const(TSParseAction)[] actions(TSStateId state, TSSymbol symbol) const
	{
		TableEntry entry;
		this.tableEntry(state, symbol, entry);
		return entry.actions;
	}

	bool hasReduceAction(TSStateId state, TSSymbol symbol) const
	{
		TableEntry entry;
		this.tableEntry(state, symbol, entry);
		return entry.actionCount > 0 && entry.actions[0].type == TSParseActionType.reduce;
	}

	bool hasActions(TSStateId state, TSSymbol symbol) const
	{
		return this.lookup(state, symbol) != 0;
	}

	TSSymbolMetadata symbolMetadata(TSSymbol symbol) const @trusted
	{
		if (symbol == tsBuiltinSymError)
			return TSSymbolMetadata(true, true, false);
		else if (symbol == tsBuiltinSymErrorRepeat)
			return TSSymbolMetadata(false, false, false);
		else
			return symbolMetadata_[symbol];
	}

	TSSymbol publicSymbol(TSSymbol symbol) const @trusted
	{
		if (symbol == tsBuiltinSymError)
			return symbol;
		return publicSymbolMap[symbol];
	}

	TSStateId nextState(TSStateId state, TSSymbol symbol) const
	{
		if (symbol == tsBuiltinSymError || symbol == tsBuiltinSymErrorRepeat)
		{
			return 0;
		}
		else if (symbol < tokenCount)
		{
			const(TSParseAction)[] actions = this.actions(state, symbol);
			if (actions.length > 0)
			{
				TSParseAction action = actions[$ - 1];
				if (action.type == TSParseActionType.shift)
					return action.shift.extra ? state : action.shift.state;
			}
			return 0;
		}
		else
		{
			return this.lookup(state, symbol);
		}
	}

	const(TSSymbol)* aliasSequence(uint productionId) const @trusted
	{
		return productionId ?
			&aliasSequences[productionId * maxAliasSequenceLength] : null;
	}

	TSSymbol aliasAt(uint productionId, uint childIndex) const @trusted
	{
		return productionId ?
			aliasSequences[productionId * maxAliasSequenceLength + childIndex] : 0;
	}

	void fieldMap(uint productionId, ref const(TSFieldMapEntry)* start, ref const(TSFieldMapEntry)* end) const @trusted
	{
		if (fieldCount == 0)
		{
			start = null;
			end = null;
			return;
		}
		TSFieldMapSlice slice = fieldMapSlices[productionId];
		start = &fieldMapEntries[slice.index];
		end = &fieldMapEntries[slice.index] + slice.length;
	}

	const(char)* symbolName(TSSymbol symbol) const @trusted
	{
		if (symbol == tsBuiltinSymError)
			return "ERROR".ptr;
		else if (symbol == tsBuiltinSymErrorRepeat)
			return "_ERROR".ptr;
		else if (symbol < symbolCount + aliasCount)
			return symbolNames[symbol];
		else
			return null;
	}

	TSSymbol symbolForName(const(char)* str, uint length, bool isNamed) const @trusted
	{
		if (cstrncmp(str, "ERROR".ptr, length) == 0)
			return tsBuiltinSymError;
		const ushort count = cast(ushort)(symbolCount + aliasCount);
		foreach (TSSymbol i; 0 .. count)
		{
			TSSymbolMetadata metadata = this.symbolMetadata(i);
			if ((!metadata.visible && !metadata.supertype) || metadata.named != isNamed)
				continue;
			const(char)* symbolName = symbolNames[i];
			if (cstrncmp(symbolName, str, length) == 0 && symbolName[length] == 0)
				return publicSymbolMap[i];
		}
		return 0;
	}

	TSSymbolType symbolType(TSSymbol symbol) const
	{
		TSSymbolMetadata metadata = this.symbolMetadata(symbol);
		if (metadata.named && metadata.visible)
			return TSSymbolType.regular;
		else if (metadata.visible)
			return TSSymbolType.anonymous;
		else
			return TSSymbolType.auxiliary;
	}

	const(char)* fieldNameForId(TSFieldId id) const @trusted
	{
		const count = fieldCount;
		if (count && id <= count)
			return fieldNames[id];
		else
			return null;
	}

	TSFieldId fieldIdForName(const(char)* name, uint nameLength) const @trusted
	{
		const ushort count = cast(ushort) fieldCount;
		foreach (TSSymbol i; 1 .. count + 1)
		{
			switch (cstrncmp(name, fieldNames[i], nameLength))
			{
				case 0:
					if (fieldNames[i][nameLength] == 0)
						return i;
					break;
				case -1:
					return 0;
				default:
					break;
			}
		}
		return 0;
	}
}

/// Lexer interface passed to the generated lex functions. The function pointers
/// let generated code drive the lexer without linking against this module.
struct TSLexer
{
	int lookahead;
	TSSymbol resultSymbol;
	extern (C) void function(scope TSLexer*, bool) advance;
	extern (C) void function(scope TSLexer*) markEnd;
	extern (C) uint function(scope TSLexer*) getColumn;
	extern (C) bool function(const scope TSLexer*) isAtIncludedRangeStart;
	extern (C) bool function(const scope TSLexer*) eof;
}

/***************************/
/* Section - Point/Length  */
/***************************/

TSPoint point__new(uint row, uint column) => TSPoint(row, column);

TSPoint pointAdd(TSPoint a, TSPoint b)
{
	if (b.row > 0)
		return point__new(a.row + b.row, b.column);
	else
		return point__new(a.row, a.column + b.column);
}

TSPoint pointSub(TSPoint a, TSPoint b)
{
	if (a.row > b.row)
		return point__new(a.row - b.row, a.column);
	else
		return point__new(0, a.column - b.column);
}

bool pointLte(TSPoint a, TSPoint b) => (a.row < b.row) || (a.row == b.row && a.column <= b.column);
bool pointLt(TSPoint a, TSPoint b) => (a.row < b.row) || (a.row == b.row && a.column < b.column);

struct Length
{
	uint bytes;
	TSPoint extent;
}

enum Length LENGTH_UNDEFINED = Length(0, TSPoint(0, 1));

bool lengthIsUndefined(Length length) => length.bytes == 0 && length.extent.column != 0;

Length lengthMin(Length a, Length b) => (a.bytes < b.bytes) ? a : b;

Length lengthAdd(Length a, Length b)
{
	return Length(a.bytes + b.bytes, pointAdd(a.extent, b.extent));
}

Length lengthSub(Length a, Length b)
{
	return Length(a.bytes - b.bytes, pointSub(a.extent, b.extent));
}

Length lengthZero() => Length(0, TSPoint(0, 0));

Length lengthSaturatingSub(Length a, Length b)
{
	return (a.bytes > b.bytes) ? lengthSub(a, b) : lengthZero();
}

/***********************************/
/* Section - TsArray (array.h port) */
/***********************************/

/// Dynamic array mirroring tree-sitter's `Array(T)`. Backed by an Allocator;
/// growth reallocates and abandons the old buffer into the arena (parse-once).
struct TsArray(T)
{
	T* contents;
	uint size;
	uint capacity;
	private Allocator alloc;

	this(return scope Allocator alloc) scope
	{
		this.alloc = alloc;
	}

	T[] slice() return scope @trusted => contents[0 .. size];

	ref T opIndex(size_t i) return scope @trusted
	{
		assert(i < size);
		return contents[i];
	}

	void clear() scope
	{
		size = 0;
	}

	ref T front() return scope => this[0];
	ref T back() return scope => this[size - 1];

	void reserve(uint newCapacity) scope @trusted
	{
		if (newCapacity > capacity)
		{
			T[] mem = alloc.newArray!T(newCapacity);
			if (contents && size > 0)
				memcpy(mem.ptr, contents, size * T.sizeof);
			contents = mem.ptr;
			capacity = newCapacity;
		}
	}

	private void grow(uint count) scope
	{
		const newSize = size + count;
		if (newSize > capacity)
		{
			uint newCapacity = capacity * 2;
			if (newCapacity < 8)
				newCapacity = 8;
			if (newCapacity < newSize)
				newCapacity = newSize;
			reserve(newCapacity);
		}
	}

	void push(T element) scope @trusted
	{
		grow(1);
		contents[size++] = element;
	}

	void growBy(uint count) scope @trusted
	{
		if (count == 0)
			return;
		grow(count);
		memset(contents + size, 0, count * T.sizeof);
		size += count;
	}

	T pop() scope @trusted
	{
		assert(size > 0);
		return contents[--size];
	}

	void erase(uint index) scope @trusted
	{
		assert(index < size);
		memmove(contents + index, contents + index + 1, (size - index - 1) * T.sizeof);
		size--;
	}

	/// Remove old_count elements at index, insert new_count from `elements`.
	void splice(uint index, uint oldCount, uint newCount, const(T)* elements) scope @trusted
	{
		const newSize = size + newCount - oldCount;
		const oldEnd = index + oldCount;
		const newEnd = index + newCount;
		assert(oldEnd <= size);
		reserve(newSize);
		if (size > oldEnd)
			memmove(contents + newEnd, contents + oldEnd, (size - oldEnd) * T.sizeof);
		if (newCount > 0)
		{
			if (elements)
				memcpy(contents + index, elements, newCount * T.sizeof);
			else
				memset(contents + index, 0, newCount * T.sizeof);
		}
		size += newCount - oldCount;
	}

	void insert(uint index, T element) scope @trusted
	{
		splice(index, 0, 1, &element);
	}

	void assign(ref const TsArray!T other) scope @trusted
	{
		reserve(other.size);
		size = other.size;
		if (size > 0)
			memcpy(contents, other.contents, size * T.sizeof);
	}

	void swap(ref TsArray!T other) scope
	{
		auto tmp = this;
		this = other;
		other = tmp;
	}
}

/********************/
/* Section - Subtree */
/********************/

struct FirstLeaf
{
	TSSymbol symbol;
	TSStateId parseState;
}

/// Heap representation of a syntax subtree. Always heap-allocated (the inline
/// optimization is dropped) and never reference counted (arena-owned).
struct SubtreeData
{
	Length padding;
	Length size;
	uint lookaheadBytes;
	uint errorCost;
	uint childCount;
	TSSymbol symbol;
	TSStateId parseState;

	bool visible;
	bool named;
	bool extra;
	bool fragileLeft;
	bool fragileRight;
	bool hasChanges;
	bool dependsOnColumn;
	bool isMissing;
	bool isKeyword;

	// Non-terminal subtrees (child_count > 0)
	uint visibleChildCount;
	uint namedChildCount;
	uint visibleDescendantCount;
	int dynamicPrecedence;
	ushort repeatDepth;
	ushort productionId;
	FirstLeaf firstLeaf;

	// Error terminal subtrees (child_count == 0 && symbol == error)
	int lookaheadChar;

	// Children, allocated as a separate arena slice (the C version stores them
	// immediately before the header; here a plain slice is clearer).
	Subtree[] children;
}

/// The fundamental building block of a syntax tree. A thin pointer wrapper.
struct Subtree
{
	SubtreeData* ptr;
}

enum Subtree NULL_SUBTREE = Subtree(null);

// Subtree accessors -------------------------------------------------------

TSSymbol tsSubtreeSymbol(Subtree self) => self.ptr.symbol;
bool tsSubtreeVisible(Subtree self) => self.ptr.visible;
bool tsSubtreeNamed(Subtree self) => self.ptr.named;
bool tsSubtreeExtra(Subtree self) => self.ptr.extra;
bool tsSubtreeHasChanges(Subtree self) => self.ptr.hasChanges;
bool tsSubtreeMissing(Subtree self) => self.ptr.isMissing;
bool tsSubtreeIsKeyword(Subtree self) => self.ptr.isKeyword;
TSStateId tsSubtreeParseState(Subtree self) => self.ptr.parseState;
uint tsSubtreeLookaheadBytes(Subtree self) => self.ptr.lookaheadBytes;

Subtree[] tsSubtreeChildren(Subtree self) => self.ptr.children;

void tsSubtreeSetExtra(Subtree self, bool isExtra)
{
	self.ptr.extra = isExtra;
}

TSSymbol tsSubtreeLeafSymbol(Subtree self)
{
	if (self.ptr.childCount == 0)
		return self.ptr.symbol;
	return self.ptr.firstLeaf.symbol;
}

TSStateId tsSubtreeLeafParseState(Subtree self)
{
	if (self.ptr.childCount == 0)
		return self.ptr.parseState;
	return self.ptr.firstLeaf.parseState;
}

Length tsSubtreePadding(Subtree self) => self.ptr.padding;
Length tsSubtreeSize(Subtree self) => self.ptr.size;
Length tsSubtreeTotalSize(Subtree self) => lengthAdd(tsSubtreePadding(self), tsSubtreeSize(self));
uint tsSubtreeTotalBytes(Subtree self) => tsSubtreeTotalSize(self).bytes;
uint tsSubtreeChildCount(Subtree self) => self.ptr.childCount;
uint tsSubtreeRepeatDepth(Subtree self) => self.ptr.repeatDepth;

uint tsSubtreeVisibleDescendantCount(Subtree self)
{
	return (self.ptr.childCount == 0) ? 0 : self.ptr.visibleDescendantCount;
}

uint tsSubtreeVisibleChildCount(Subtree self)
{
	return (tsSubtreeChildCount(self) > 0) ? self.ptr.visibleChildCount : 0;
}

uint tsSubtreeErrorCost(Subtree self)
{
	if (tsSubtreeMissing(self))
		return ERROR_COST_PER_MISSING_TREE + ERROR_COST_PER_RECOVERY;
	else
		return self.ptr.errorCost;
}

int tsSubtreeDynamicPrecedence(Subtree self)
{
	return (self.ptr.childCount == 0) ? 0 : self.ptr.dynamicPrecedence;
}

ushort tsSubtreeProductionId(Subtree self)
{
	return (tsSubtreeChildCount(self) > 0) ? self.ptr.productionId : 0;
}

bool tsSubtreeFragileLeft(Subtree self) => self.ptr.fragileLeft;
bool tsSubtreeFragileRight(Subtree self) => self.ptr.fragileRight;
bool tsSubtreeHasExternalTokens(Subtree self) => false;
bool tsSubtreeDependsOnColumn(Subtree self) => self.ptr.dependsOnColumn;
bool tsSubtreeIsFragile(Subtree self) => self.ptr.fragileLeft || self.ptr.fragileRight;
bool tsSubtreeIsError(Subtree self) => tsSubtreeSymbol(self) == tsBuiltinSymError;
bool tsSubtreeIsEof(Subtree self) => tsSubtreeSymbol(self) == tsBuiltinSymEnd;

// External-scanner state: the C grammar has none, so every subtree's state is
// the empty state, which always compares equal.
bool tsSubtreeExternalScannerStateEq(Subtree a, Subtree b) => true;

// retain/release are no-ops: all subtrees live in the parser's arena.
void tsSubtreeRetain(Subtree self) {}

// SubtreeArray helpers ----------------------------------------------------

alias SubtreeArray = TsArray!Subtree;

void tsSubtreeArrayRemoveTrailingExtras(ref SubtreeArray self, ref SubtreeArray destination)
{
	destination.clear();
	while (self.size > 0)
	{
		Subtree last = self[self.size - 1];
		if (tsSubtreeExtra(last))
		{
			self.size--;
			destination.push(last);
		}
		else
			break;
	}
	tsSubtreeArrayReverse(destination);
}

void tsSubtreeArrayReverse(ref SubtreeArray self)
{
	foreach (i; 0 .. self.size / 2)
	{
		const reverseIndex = self.size - 1 - i;
		Subtree swap = self[i];
		self[i] = self[reverseIndex];
		self[reverseIndex] = swap;
	}
}

// Subtree constructors ----------------------------------------------------

private SubtreeData* allocSubtree(return scope Allocator alloc) @trusted
{
	return alloc.newItem!SubtreeData();
}

Subtree tsSubtreeNewLeaf(
	return scope Allocator alloc, TSSymbol symbol, Length padding, Length size,
	uint lookaheadBytes, TSStateId parseState, bool dependsOnColumn,
	bool isKeyword, ref const TSLanguage language)
{
	TSSymbolMetadata metadata = language.symbolMetadata(symbol);
	SubtreeData* data = allocSubtree(alloc);
	data.padding = padding;
	data.size = size;
	data.lookaheadBytes = lookaheadBytes;
	data.symbol = symbol;
	data.parseState = parseState;
	data.visible = metadata.visible;
	data.named = metadata.named;
	data.extra = symbol == tsBuiltinSymEnd;
	data.dependsOnColumn = dependsOnColumn;
	data.isKeyword = isKeyword;
	return Subtree(data);
}

void tsSubtreeSetSymbol(Subtree self, TSSymbol symbol, ref const TSLanguage language)
{
	TSSymbolMetadata metadata = language.symbolMetadata(symbol);
	self.ptr.symbol = symbol;
	self.ptr.named = metadata.named;
	self.ptr.visible = metadata.visible;
}

Subtree tsSubtreeNewError(
	return scope Allocator alloc, int lookaheadChar, Length padding, Length size,
	uint bytesScanned, TSStateId parseState, ref const TSLanguage language)
{
	Subtree result = tsSubtreeNewLeaf(
		alloc, tsBuiltinSymError, padding, size, bytesScanned,
		parseState, false, false, language);
	result.ptr.fragileLeft = true;
	result.ptr.fragileRight = true;
	result.ptr.lookaheadChar = lookaheadChar;
	return result;
}

/// Clone a subtree (deep-copies the header and a fresh children slice). Used in
/// place of the C ref-counted `make_mut` so shared trees are never mutated.
Subtree tsSubtreeClone(return scope Allocator alloc, Subtree self) @trusted
{
	SubtreeData* result = allocSubtree(alloc);
	*result = *self.ptr;
	if (self.ptr.childCount > 0)
	{
		Subtree[] newChildren = alloc.newArray!Subtree(self.ptr.childCount);
		newChildren[] = self.ptr.children[0 .. self.ptr.childCount];
		result.children = newChildren;
	}
	return Subtree(result);
}

Subtree tsSubtreeMakeMut(return scope Allocator alloc, Subtree self)
{
	return tsSubtreeClone(alloc, self);
}

/// Assign all properties that depend on a node's children.
void tsSubtreeSummarizeChildren(Subtree self, ref const TSLanguage language)
{
	self.ptr.namedChildCount = 0;
	self.ptr.visibleChildCount = 0;
	self.ptr.errorCost = 0;
	self.ptr.repeatDepth = 0;
	self.ptr.visibleDescendantCount = 0;
	self.ptr.dependsOnColumn = false;
	self.ptr.dynamicPrecedence = 0;

	uint structuralIndex = 0;
	uint lookaheadEndByte = 0;

	Subtree[] children = self.ptr.children;
	foreach (i; 0 .. self.ptr.childCount)
	{
		Subtree child = children[i];

		if (self.ptr.size.extent.row == 0 && tsSubtreeDependsOnColumn(child))
			self.ptr.dependsOnColumn = true;

		if (i == 0)
		{
			self.ptr.padding = tsSubtreePadding(child);
			self.ptr.size = tsSubtreeSize(child);
		}
		else
		{
			self.ptr.size = lengthAdd(self.ptr.size, tsSubtreeTotalSize(child));
		}

		const childLookaheadEndByte =
			self.ptr.padding.bytes + self.ptr.size.bytes + tsSubtreeLookaheadBytes(child);
		if (childLookaheadEndByte > lookaheadEndByte)
			lookaheadEndByte = childLookaheadEndByte;

		if (tsSubtreeSymbol(child) != tsBuiltinSymErrorRepeat)
			self.ptr.errorCost += tsSubtreeErrorCost(child);

		const grandchildCount = tsSubtreeChildCount(child);
		if (self.ptr.symbol == tsBuiltinSymError || self.ptr.symbol == tsBuiltinSymErrorRepeat)
		{
			if (!tsSubtreeExtra(child) && !(tsSubtreeIsError(child) && grandchildCount == 0))
			{
				if (tsSubtreeVisible(child))
					self.ptr.errorCost += ERROR_COST_PER_SKIPPED_TREE;
				else if (grandchildCount > 0)
					self.ptr.errorCost += ERROR_COST_PER_SKIPPED_TREE * child.ptr.visibleChildCount;
			}
		}

		self.ptr.dynamicPrecedence += tsSubtreeDynamicPrecedence(child);
		self.ptr.visibleDescendantCount += tsSubtreeVisibleDescendantCount(child);

		const aliasSymbol = language.aliasAt(self.ptr.productionId, structuralIndex);
		if (aliasSymbol != 0 && !tsSubtreeExtra(child))
		{
			self.ptr.visibleDescendantCount++;
			self.ptr.visibleChildCount++;
			if (language.symbolMetadata(aliasSymbol).named)
				self.ptr.namedChildCount++;
		}
		else if (tsSubtreeVisible(child))
		{
			self.ptr.visibleDescendantCount++;
			self.ptr.visibleChildCount++;
			if (tsSubtreeNamed(child))
				self.ptr.namedChildCount++;
		}
		else if (grandchildCount > 0)
		{
			self.ptr.visibleChildCount += child.ptr.visibleChildCount;
			self.ptr.namedChildCount += child.ptr.namedChildCount;
		}

		if (tsSubtreeIsError(child))
		{
			self.ptr.fragileLeft = self.ptr.fragileRight = true;
			self.ptr.parseState = TS_TREE_STATE_NONE;
		}

		if (!tsSubtreeExtra(child))
			structuralIndex++;
	}

	self.ptr.lookaheadBytes = lookaheadEndByte - self.ptr.size.bytes - self.ptr.padding.bytes;

	if (self.ptr.symbol == tsBuiltinSymError || self.ptr.symbol == tsBuiltinSymErrorRepeat)
	{
		self.ptr.errorCost +=
			ERROR_COST_PER_RECOVERY +
			ERROR_COST_PER_SKIPPED_CHAR * self.ptr.size.bytes +
			ERROR_COST_PER_SKIPPED_LINE * self.ptr.size.extent.row;
	}

	if (self.ptr.childCount > 0)
	{
		Subtree firstChild = children[0];
		Subtree lastChild = children[self.ptr.childCount - 1];

		self.ptr.firstLeaf.symbol = tsSubtreeLeafSymbol(firstChild);
		self.ptr.firstLeaf.parseState = tsSubtreeLeafParseState(firstChild);

		if (tsSubtreeFragileLeft(firstChild))
			self.ptr.fragileLeft = true;
		if (tsSubtreeFragileRight(lastChild))
			self.ptr.fragileRight = true;

		if (self.ptr.childCount >= 2 && !self.ptr.visible && !self.ptr.named &&
			tsSubtreeSymbol(firstChild) == self.ptr.symbol)
		{
			if (tsSubtreeRepeatDepth(firstChild) > tsSubtreeRepeatDepth(lastChild))
				self.ptr.repeatDepth = cast(ushort)(tsSubtreeRepeatDepth(firstChild) + 1);
			else
				self.ptr.repeatDepth = cast(ushort)(tsSubtreeRepeatDepth(lastChild) + 1);
		}
	}
}

/// Create a new parent node with the given children (takes ownership of the
/// children array's current slice).
Subtree tsSubtreeNewNode(
	return scope Allocator alloc, TSSymbol symbol, ref SubtreeArray children,
	uint productionId, ref const TSLanguage language) @trusted
{
	TSSymbolMetadata metadata = language.symbolMetadata(symbol);
	const fragile = symbol == tsBuiltinSymError || symbol == tsBuiltinSymErrorRepeat;

	SubtreeData* data = allocSubtree(alloc);
	data.symbol = symbol;
	data.childCount = children.size;
	data.children = children.contents[0 .. children.size];
	data.visible = metadata.visible;
	data.named = metadata.named;
	data.fragileLeft = fragile;
	data.fragileRight = fragile;
	data.productionId = cast(ushort) productionId;

	Subtree result = Subtree(data);
	tsSubtreeSummarizeChildren(result, language);
	return result;
}

Subtree tsSubtreeNewErrorNode(
	return scope Allocator alloc, ref SubtreeArray children, bool extra, ref const TSLanguage language)
{
	Subtree result = tsSubtreeNewNode(alloc, tsBuiltinSymError, children, 0, language);
	result.ptr.extra = extra;
	return result;
}

Subtree tsSubtreeNewMissingLeaf(
	return scope Allocator alloc, TSSymbol symbol, Length padding,
	uint lookaheadBytes, ref const TSLanguage language)
{
	Subtree result = tsSubtreeNewLeaf(
		alloc, symbol, padding, lengthZero(), lookaheadBytes, 0, false, false, language);
	result.ptr.isMissing = true;
	return result;
}

int tsSubtreeCompare(Subtree left, Subtree right)
{
	if (tsSubtreeSymbol(left) < tsSubtreeSymbol(right))
		return -1;
	if (tsSubtreeSymbol(right) < tsSubtreeSymbol(left))
		return 1;
	if (tsSubtreeChildCount(left) < tsSubtreeChildCount(right))
		return -1;
	if (tsSubtreeChildCount(right) < tsSubtreeChildCount(left))
		return 1;
	foreach (i; 0 .. tsSubtreeChildCount(left))
	{
		Subtree leftChild = tsSubtreeChildren(left)[i];
		Subtree rightChild = tsSubtreeChildren(right)[i];
		switch (tsSubtreeCompare(leftChild, rightChild))
		{
			case -1: return -1;
			case 1: return 1;
			default: break;
		}
	}
	return 0;
}

/*********************/
/* Section - Language */
/*********************/

struct TableEntry
{
	const(TSParseAction)[] actions;
	uint actionCount;
	bool isReusable;
}

private size_t cstrlen(const(char)* s) @trusted
{
	size_t n = 0;
	while (s[n] != 0)
		n++;
	return n;
}

// Compares the first `n` bytes of cstring `s` against `str`, like strncmp.
private int cstrncmp(const(char)* a, const(char)* b, size_t n) @trusted
{
	foreach (i; 0 .. n)
	{
		const int d = cast(int)(cast(ubyte) a[i]) - cast(int)(cast(ubyte) b[i]);
		if (d != 0)
			return d < 0 ? -1 : 1;
		if (a[i] == 0)
			break;
	}
	return 0;
}

/*******************/
/* Section - Lexer  */
/*******************/

enum int TS_DECODE_ERROR = -1;
enum int BYTE_ORDER_MARK = 0xFEFF;

/// Decode one UTF-8 code point. Returns bytes consumed; writes the code point
/// (or TS_DECODE_ERROR on malformed input) to `codePoint`.
uint tsDecodeUtf8(const(ubyte)* str, uint length, ref int codePoint) @trusted
{
	if (length == 0)
	{
		codePoint = TS_DECODE_ERROR;
		return 0;
	}
	const ubyte b0 = str[0];
	if (b0 < 0x80)
	{
		codePoint = b0;
		return 1;
	}

	uint extra;
	int cp;
	if ((b0 & 0xE0) == 0xC0)
	{
		extra = 1;
		cp = b0 & 0x1F;
	}
	else if ((b0 & 0xF0) == 0xE0)
	{
		extra = 2;
		cp = b0 & 0x0F;
	}
	else if ((b0 & 0xF8) == 0xF0)
	{
		extra = 3;
		cp = b0 & 0x07;
	}
	else
	{
		codePoint = TS_DECODE_ERROR;
		return 1;
	}

	if (length < 1 + extra)
	{
		codePoint = TS_DECODE_ERROR;
		return 1;
	}
	foreach (i; 0 .. extra)
	{
		const ubyte b = str[1 + i];
		if ((b & 0xC0) != 0x80)
		{
			codePoint = TS_DECODE_ERROR;
			return 1;
		}
		cp = (cp << 6) | (b & 0x3F);
	}

	// Reject overlong encodings and surrogate code points.
	static immutable int[4] minCp = [0, 0x80, 0x800, 0x10000];
	if (cp < minCp[extra] || (cp >= 0xD800 && cp <= 0xDFFF) || cp > 0x10FFFF)
	{
		codePoint = TS_DECODE_ERROR;
		return 1;
	}

	codePoint = cp;
	return 1 + extra;
}

/// Lexer over a single contiguous UTF-8 buffer. `data` must be the first field
/// so the generated lex functions can recover the Lexer from a TSLexer*.
struct Lexer
{
	TSLexer data;
	Length currentPosition;
	Length tokenStartPosition;
	Length tokenEndPosition;
	const(ubyte)[] input;
	uint lookaheadSize;

	void init() scope @trusted
	{
		data.advance = &lexerAdvanceCb;
		data.markEnd = &lexerMarkEndCb;
		data.getColumn = &lexerGetColumnCb;
		data.isAtIncludedRangeStart = &lexerIsAtRangeStartCb;
		data.eof = &lexerEofCb;
		data.lookahead = 0;
		data.resultSymbol = 0;
		currentPosition = lengthZero();
		input = null;
		lookaheadSize = 0;
	}

	bool atEof() const scope => currentPosition.bytes >= input.length;

	private void getLookahead() scope @trusted
	{
		const pos = currentPosition.bytes;
		if (pos >= input.length)
		{
			lookaheadSize = 1;
			data.lookahead = '\0';
			return;
		}
		lookaheadSize = tsDecodeUtf8(input.ptr + pos, cast(uint)(input.length - pos), data.lookahead);
		if (data.lookahead == TS_DECODE_ERROR)
			lookaheadSize = 1;
	}

	void doAdvance(bool skip) scope
	{
		if (lookaheadSize)
		{
			currentPosition.bytes += lookaheadSize;
			if (data.lookahead == '\n')
			{
				currentPosition.extent.row++;
				currentPosition.extent.column = 0;
			}
			else
			{
				currentPosition.extent.column += lookaheadSize;
			}
		}
		if (skip)
			tokenStartPosition = currentPosition;
		getLookahead();
	}

	void markEnd() scope
	{
		tokenEndPosition = currentPosition;
	}

	uint getColumn() scope
	{
		const goalByte = currentPosition.bytes;
		currentPosition.bytes -= currentPosition.extent.column;
		currentPosition.extent.column = 0;
		uint result = 0;
		if (!atEof())
		{
			getLookahead();
			while (currentPosition.bytes < goalByte && currentPosition.bytes < input.length)
			{
				result++;
				doAdvance(false);
				if (atEof())
					break;
			}
		}
		return result;
	}

	void setInput(const(ubyte)[] source) scope
	{
		input = source;
		currentPosition = lengthZero();
		lookaheadSize = 0;
	}

	void reset(Length position) scope
	{
		if (position.bytes != currentPosition.bytes)
		{
			currentPosition = position;
			lookaheadSize = 0;
			data.lookahead = '\0';
		}
	}

	void start() scope
	{
		tokenStartPosition = currentPosition;
		tokenEndPosition = LENGTH_UNDEFINED;
		data.resultSymbol = 0;
		if (!atEof())
		{
			if (lookaheadSize == 0)
				getLookahead();
			if (currentPosition.bytes == 0 && data.lookahead == BYTE_ORDER_MARK)
				doAdvance(true);
		}
	}

	void finish(ref uint lookaheadEndByte) scope
	{
		if (lengthIsUndefined(tokenEndPosition))
			markEnd();
		if (tokenEndPosition.bytes < tokenStartPosition.bytes)
			tokenStartPosition = tokenEndPosition;
		uint currentLookaheadEndByte = currentPosition.bytes + 1;
		if (data.lookahead == TS_DECODE_ERROR)
			currentLookaheadEndByte++;
		if (currentLookaheadEndByte > lookaheadEndByte)
			lookaheadEndByte = currentLookaheadEndByte;
	}

	void markEndPublic() scope
	{
		markEnd();
	}
}

// Callbacks bridging the generated grammar's TSLexer* to our Lexer. The lexer's
// `data` field is at offset 0, so the cast recovers the enclosing Lexer.
private extern (C) void lexerAdvanceCb(scope TSLexer* lexer, bool skip) @trusted //#CLAUDE
{
	// Mirror the C lexer: the public `advance` is a no-op once the chunk is
	// exhausted (EOF), so it does not move the position past the document end.
	Lexer* self = cast(Lexer*) lexer;
	if (self.atEof())
		return;
	self.doAdvance(skip);
}

private extern (C) void lexerMarkEndCb(scope TSLexer* lexer) @trusted //#CLAUDE
{
	(cast(Lexer*) lexer).markEnd();
}

private extern (C) uint lexerGetColumnCb(scope TSLexer* lexer) @trusted //#CLAUDE
{
	return (cast(Lexer*) lexer).getColumn();
}

private extern (C) bool lexerIsAtRangeStartCb(const scope TSLexer* lexer) @trusted //#CLAUDE
{
	return false;
}

private extern (C) bool lexerEofCb(const scope TSLexer* lexer) @trusted //#CLAUDE
{
	return (cast(Lexer*) lexer).atEof();
}

/*******************/
/* Section - Stack  */
/*******************/

alias StackVersion = uint;
enum StackVersion STACK_VERSION_NONE = cast(StackVersion) -1;

enum MAX_LINK_COUNT = 8;
enum MAX_ITERATOR_COUNT = 64;

struct StackLink
{
	StackNode* node;
	Subtree subtree;
	bool isPending;
}

// MAX_LINK_COUNT is a hard algorithmic cap on GLR stack-node fan-out, so a fixed
// inline array (not a growable buffer) is the natural representation here.
struct StackNode
{
	TSStateId state;
	Length position;
	StackLink[MAX_LINK_COUNT] links;
	ushort linkCount;
	uint errorCost;
	uint nodeCount;
	int dynamicPrecedence;
}

struct StackSlice
{
	SubtreeArray subtrees;
	StackVersion version_;
}

alias StackSliceArray = TsArray!StackSlice;

struct StackSummaryEntry
{
	Length position;
	uint depth;
	TSStateId state;
}

alias StackSummary = TsArray!StackSummaryEntry;

struct StackIterator
{
	StackNode* node;
	SubtreeArray subtrees;
	uint subtreeCount;
	bool isPending;
}

enum StackStatus
{
	active,
	paused,
	halted,
}

struct StackHead
{
	StackNode* node;
	StackSummary* summary;
	uint nodeCountAtLastError;
	Subtree lastExternalToken;
	Subtree lookaheadWhenPaused;
	StackStatus status;
}

enum StackAction : uint
{
	none = 0,
	stop = 1,
	pop = 2,
}

alias StackCallback = StackAction delegate(ref const StackIterator);

struct Stack
{
	TsArray!StackHead heads;
	StackSliceArray slices;
	TsArray!StackIterator iterators;
	StackNode* baseNode;
	Allocator alloc;

	private StackVersion addVersion(StackVersion originalVersion, StackNode* node) @trusted
	{
		StackHead head;
		head.node = node;
		head.nodeCountAtLastError = heads[originalVersion].nodeCountAtLastError;
		head.lastExternalToken = heads[originalVersion].lastExternalToken;
		head.status = StackStatus.active;
		head.lookaheadWhenPaused = NULL_SUBTREE;
		heads.push(head);
		return cast(StackVersion)(heads.size - 1);
	}

	private void addSlice(StackVersion originalVersion, StackNode* node, ref SubtreeArray subtrees) @trusted
	{
		foreach_reverse (i; 0 .. slices.size)
		{
			StackVersion ver = slices[i].version_;
			if (heads[ver].node is node)
			{
				StackSlice slice = StackSlice(subtrees, ver);
				slices.insert(i + 1, slice);
				return;
			}
		}

		StackVersion ver = this.addVersion(originalVersion, node);
		StackSlice slice = StackSlice(subtrees, ver);
		slices.push(slice);
	}

	private StackSliceArray iter(StackVersion ver, scope StackCallback callback, int goalSubtreeCount) @trusted
	{
		slices.clear();
		iterators.clear();

		StackHead* head = &heads[ver];
		StackIterator newIterator;
		newIterator.node = head.node;
		newIterator.subtrees = SubtreeArray(alloc);
		newIterator.subtreeCount = 0;
		newIterator.isPending = true;

		bool includeSubtrees = false;
		if (goalSubtreeCount >= 0)
		{
			includeSubtrees = true;
			newIterator.subtrees.reserve(cast(uint) goalSubtreeCount);
		}

		iterators.push(newIterator);

		while (iterators.size > 0)
		{
			for (uint i = 0, size = iterators.size; i < size; i++)
			{
				StackIterator* iterator = &iterators[i];
				StackNode* node = iterator.node;

				StackAction action = callback(*iterator);
				bool shouldPop = (action & StackAction.pop) != 0;
				bool shouldStop = (action & StackAction.stop) != 0 || node.linkCount == 0;

				if (shouldPop)
				{
					SubtreeArray subtrees = iterator.subtrees;
					if (!shouldStop)
						tsSubtreeArrayCopy(subtrees, subtrees);
					tsSubtreeArrayReverse(subtrees);
					this.addSlice(ver, node, subtrees);
				}

				if (shouldStop)
				{
					iterators.erase(i);
					i--;
					size--;
					continue;
				}

				foreach (j; 1 .. node.linkCount + 1)
				{
					StackIterator* nextIterator;
					StackLink link;
					if (j == node.linkCount)
					{
						link = node.links[0];
						nextIterator = &iterators[i];
					}
					else
					{
						if (iterators.size >= MAX_ITERATOR_COUNT)
							continue;
						link = node.links[j];
						StackIterator currentIterator = iterators[i];
						iterators.push(currentIterator);
						nextIterator = &iterators[iterators.size - 1];
						tsSubtreeArrayCopy(nextIterator.subtrees, nextIterator.subtrees);
					}

					nextIterator.node = link.node;
					if (link.subtree.ptr)
					{
						if (includeSubtrees)
							nextIterator.subtrees.push(link.subtree);

						if (!tsSubtreeExtra(link.subtree))
						{
							nextIterator.subtreeCount++;
							if (!link.isPending)
								nextIterator.isPending = false;
						}
					}
					else
					{
						nextIterator.subtreeCount++;
						nextIterator.isPending = false;
					}
				}
			}
		}

		return slices;
	}

	uint versionCount() const => heads.size;

	TSStateId state(StackVersion ver) const @trusted
	{
		return (cast(Stack*) &this).heads[ver].node.state;
	}

	Length position(StackVersion ver) const @trusted
	{
		return (cast(Stack*) &this).heads[ver].node.position;
	}

	Subtree lastExternalToken(StackVersion ver) const @trusted
	{
		return (cast(Stack*) &this).heads[ver].lastExternalToken;
	}

	void setLastExternalToken(StackVersion ver, Subtree token) @trusted
	{
		heads[ver].lastExternalToken = token;
	}

	uint errorCost(StackVersion ver) const @trusted
	{
		StackHead* head = &(cast(Stack*) &this).heads[ver];
		uint result = head.node.errorCost;
		if (head.status == StackStatus.paused ||
			(head.node.state == ERROR_STATE && !head.node.links[0].subtree.ptr))
		{
			result += ERROR_COST_PER_RECOVERY;
		}
		return result;
	}

	uint nodeCountSinceError(StackVersion ver) const @trusted
	{
		StackHead* head = &(cast(Stack*) &this).heads[ver];
		if (head.node.nodeCount < head.nodeCountAtLastError)
			head.nodeCountAtLastError = head.node.nodeCount;
		return head.node.nodeCount - head.nodeCountAtLastError;
	}

	void push(StackVersion ver, Subtree subtree, bool pending, TSStateId state) @trusted
	{
		StackHead* head = &heads[ver];
		StackNode* newNode = stackNodeNew(alloc, head.node, subtree, pending, state);
		if (!subtree.ptr)
			head.nodeCountAtLastError = newNode.nodeCount;
		head.node = newNode;
	}

	StackSliceArray popCount(StackVersion ver, uint count) @trusted
	{
		StackAction cb(ref const StackIterator iterator)
		{
			if (iterator.subtreeCount == count)
				return StackAction.pop | StackAction.stop;
			return StackAction.none;
		}
		return this.iter(ver, &cb, cast(int) count);
	}

	StackSliceArray popPending(StackVersion ver) @trusted
	{
		StackAction cb(ref const StackIterator iterator)
		{
			if (iterator.subtreeCount >= 1)
				return iterator.isPending ? (StackAction.pop | StackAction.stop) : StackAction.stop;
			return StackAction.none;
		}
		StackSliceArray pop = this.iter(ver, &cb, 0);
		if (pop.size > 0)
		{
			this.renumberVersion(pop[0].version_, ver);
			pop[0].version_ = ver;
		}
		return pop;
	}

	SubtreeArray popError(StackVersion ver) @trusted
	{
		StackNode* node = heads[ver].node;
		foreach (i; 0 .. node.linkCount)
		{
			if (node.links[i].subtree.ptr && tsSubtreeIsError(node.links[i].subtree))
			{
				bool foundError = false;
				StackAction cb(ref const StackIterator iterator)
				{
					if (iterator.subtrees.size > 0)
					{
						if (!foundError && tsSubtreeIsError((cast(SubtreeArray) iterator.subtrees)[0]))
						{
							foundError = true;
							return StackAction.pop | StackAction.stop;
						}
						return StackAction.stop;
					}
					return StackAction.none;
				}
				StackSliceArray pop = this.iter(ver, &cb, 1);
				if (pop.size > 0)
				{
					assert(pop.size == 1);
					this.renumberVersion(pop[0].version_, ver);
					return pop[0].subtrees;
				}
				break;
			}
		}
		SubtreeArray empty;
		return empty;
	}

	StackSliceArray popAll(StackVersion ver) @trusted
	{
		StackAction cb(ref const StackIterator iterator)
		{
			return iterator.node.linkCount == 0 ? StackAction.pop : StackAction.none;
		}
		return this.iter(ver, &cb, 0);
	}

	void recordSummary(StackVersion ver, uint maxDepth) @trusted
	{
		StackSummary* summary = alloc.newItem!StackSummary();
		*summary = StackSummary(alloc);
		StackAction cb(ref const StackIterator iterator)
		{
			TSStateId state = iterator.node.state;
			uint depth = iterator.subtreeCount;
			if (depth > maxDepth)
				return StackAction.stop;
			foreach_reverse (i; 0 .. summary.size)
			{
				StackSummaryEntry entry = (*summary)[i];
				if (entry.depth < depth)
					break;
				if (entry.depth == depth && entry.state == state)
					return StackAction.none;
			}
			summary.push(StackSummaryEntry(iterator.node.position, depth, state));
			return StackAction.none;
		}
		this.iter(ver, &cb, -1);
		StackHead* head = &heads[ver];
		head.summary = summary;
	}

	StackSummary* getSummary(StackVersion ver) @trusted
	{
		return heads[ver].summary;
	}

	int dynamicPrecedence(StackVersion ver) @trusted
	{
		return heads[ver].node.dynamicPrecedence;
	}

	bool hasAdvancedSinceError(StackVersion ver) const @trusted
	{
		StackHead* head = &(cast(Stack*) &this).heads[ver];
		StackNode* node = head.node;
		if (node.errorCost == 0)
			return true;
		while (node)
		{
			if (node.linkCount > 0)
			{
				Subtree subtree = node.links[0].subtree;
				if (subtree.ptr)
				{
					if (tsSubtreeTotalBytes(subtree) > 0)
						return true;
					else if (node.nodeCount > head.nodeCountAtLastError && tsSubtreeErrorCost(subtree) == 0)
					{
						node = node.links[0].node;
						continue;
					}
				}
			}
			break;
		}
		return false;
	}

	void removeVersion(StackVersion ver) @trusted
	{
		heads.erase(ver);
	}

	void renumberVersion(StackVersion v1, StackVersion v2) @trusted
	{
		if (v1 == v2)
			return;
		assert(v2 < v1);
		assert(v1 < heads.size);
		StackHead* sourceHead = &heads[v1];
		StackHead* targetHead = &heads[v2];
		if (targetHead.summary && !sourceHead.summary)
		{
			sourceHead.summary = targetHead.summary;
			targetHead.summary = null;
		}
		*targetHead = *sourceHead;
		heads.erase(v1);
	}

	void swapVersions(StackVersion v1, StackVersion v2) @trusted
	{
		StackHead tmp = heads[v1];
		heads[v1] = heads[v2];
		heads[v2] = tmp;
	}

	StackVersion copyVersion(StackVersion ver) @trusted
	{
		assert(ver < heads.size);
		heads.push(heads[ver]);
		StackHead* head = &heads[heads.size - 1];
		head.summary = null;
		return heads.size - 1;
	}

	bool merge(StackVersion version1, StackVersion version2) @trusted
	{
		if (!this.canMerge(version1, version2))
			return false;
		StackHead* head1 = &heads[version1];
		StackHead* head2 = &heads[version2];
		foreach (i; 0 .. head2.node.linkCount)
			stackNodeAddLink(head1.node, head2.node.links[i]);
		if (head1.node.state == ERROR_STATE)
			head1.nodeCountAtLastError = head1.node.nodeCount;
		this.removeVersion(version2);
		return true;
	}

	bool canMerge(StackVersion version1, StackVersion version2) @trusted
	{
		StackHead* head1 = &heads[version1];
		StackHead* head2 = &heads[version2];
		return
			head1.status == StackStatus.active &&
			head2.status == StackStatus.active &&
			head1.node.state == head2.node.state &&
			head1.node.position.bytes == head2.node.position.bytes &&
			head1.node.errorCost == head2.node.errorCost &&
			tsSubtreeExternalScannerStateEq(head1.lastExternalToken, head2.lastExternalToken);
	}

	void halt(StackVersion ver) @trusted
	{
		heads[ver].status = StackStatus.halted;
	}

	void pause(StackVersion ver, Subtree lookahead) @trusted
	{
		StackHead* head = &heads[ver];
		head.status = StackStatus.paused;
		head.lookaheadWhenPaused = lookahead;
		head.nodeCountAtLastError = head.node.nodeCount;
	}

	bool isActive(StackVersion ver) const @trusted
	{
		return (cast(Stack*) &this).heads[ver].status == StackStatus.active;
	}

	bool isHalted(StackVersion ver) const @trusted
	{
		return (cast(Stack*) &this).heads[ver].status == StackStatus.halted;
	}

	bool isPaused(StackVersion ver) const @trusted
	{
		return (cast(Stack*) &this).heads[ver].status == StackStatus.paused;
	}

	Subtree resume(StackVersion ver) @trusted
	{
		StackHead* head = &heads[ver];
		assert(head.status == StackStatus.paused);
		Subtree result = head.lookaheadWhenPaused;
		head.status = StackStatus.active;
		head.lookaheadWhenPaused = NULL_SUBTREE;
		return result;
	}

	void clear() @trusted
	{
		heads.clear();
		StackHead head;
		head.node = baseNode;
		head.status = StackStatus.active;
		head.lastExternalToken = NULL_SUBTREE;
		head.lookaheadWhenPaused = NULL_SUBTREE;
		heads.push(head);
	}
}

// SubtreeArray copy: produces `dest` as an independent shallow copy of `self`'s
// elements (subtrees are arena-shared pointers, so no per-element duplication).
void tsSubtreeArrayCopy(SubtreeArray self, ref SubtreeArray dest) @trusted
{
	dest.size = self.size;
	dest.capacity = self.capacity;
	if (self.capacity > 0)
	{
		Subtree[] mem = self.alloc.newArray!Subtree(self.capacity);
		if (self.size > 0)
			memcpy(mem.ptr, self.contents, self.size * Subtree.sizeof);
		dest.contents = mem.ptr;
		dest.alloc = self.alloc;
	}
}

private uint stack__subtree_node_count(Subtree subtree)
{
	uint count = tsSubtreeVisibleDescendantCount(subtree);
	if (tsSubtreeVisible(subtree))
		count++;
	if (tsSubtreeSymbol(subtree) == tsBuiltinSymErrorRepeat)
		count++;
	return count;
}

private StackNode* stackNodeNew(
	return scope Allocator alloc, StackNode* previousNode, Subtree subtree,
	bool isPending, TSStateId state) @trusted
{
	StackNode* node = alloc.newItem!StackNode();
	node.state = state;
	node.linkCount = 0;

	if (previousNode)
	{
		node.linkCount = 1;
		node.links[0] = StackLink(previousNode, subtree, isPending);
		node.position = previousNode.position;
		node.errorCost = previousNode.errorCost;
		node.dynamicPrecedence = previousNode.dynamicPrecedence;
		node.nodeCount = previousNode.nodeCount;

		if (subtree.ptr)
		{
			node.errorCost += tsSubtreeErrorCost(subtree);
			node.position = lengthAdd(node.position, tsSubtreeTotalSize(subtree));
			node.nodeCount += stack__subtree_node_count(subtree);
			node.dynamicPrecedence += tsSubtreeDynamicPrecedence(subtree);
		}
	}
	else
	{
		node.position = lengthZero();
		node.errorCost = 0;
	}
	return node;
}

private bool stack__subtree_is_equivalent(Subtree left, Subtree right)
{
	if (left.ptr is right.ptr)
		return true;
	if (!left.ptr || !right.ptr)
		return false;
	if (tsSubtreeSymbol(left) != tsSubtreeSymbol(right))
		return false;
	if (tsSubtreeErrorCost(left) > 0 && tsSubtreeErrorCost(right) > 0)
		return true;
	return
		tsSubtreePadding(left).bytes == tsSubtreePadding(right).bytes &&
		tsSubtreeSize(left).bytes == tsSubtreeSize(right).bytes &&
		tsSubtreeChildCount(left) == tsSubtreeChildCount(right) &&
		tsSubtreeExtra(left) == tsSubtreeExtra(right) &&
		tsSubtreeExternalScannerStateEq(left, right);
}

private void stackNodeAddLink(StackNode* self, StackLink link) @trusted
{
	if (link.node is self)
		return;

	foreach (i; 0 .. self.linkCount)
	{
		StackLink* existingLink = &self.links[i];
		if (stack__subtree_is_equivalent(existingLink.subtree, link.subtree))
		{
			if (existingLink.node is link.node)
			{
				if (tsSubtreeDynamicPrecedence(link.subtree) > tsSubtreeDynamicPrecedence(existingLink.subtree))
				{
					existingLink.subtree = link.subtree;
					self.dynamicPrecedence =
						link.node.dynamicPrecedence + tsSubtreeDynamicPrecedence(link.subtree);
				}
				return;
			}

			if (existingLink.node.state == link.node.state &&
				existingLink.node.position.bytes == link.node.position.bytes)
			{
				foreach (j; 0 .. link.node.linkCount)
					stackNodeAddLink(existingLink.node, link.node.links[j]);
				int dynamicPrecedence = link.node.dynamicPrecedence;
				if (link.subtree.ptr)
					dynamicPrecedence += tsSubtreeDynamicPrecedence(link.subtree);
				if (dynamicPrecedence > self.dynamicPrecedence)
					self.dynamicPrecedence = dynamicPrecedence;
				return;
			}
		}
	}

	if (self.linkCount == MAX_LINK_COUNT)
		return;

	uint nodeCount = link.node.nodeCount;
	int dynamicPrecedence = link.node.dynamicPrecedence;
	self.links[self.linkCount++] = link;

	if (link.subtree.ptr)
	{
		nodeCount += stack__subtree_node_count(link.subtree);
		dynamicPrecedence += tsSubtreeDynamicPrecedence(link.subtree);
	}

	if (nodeCount > self.nodeCount)
		self.nodeCount = nodeCount;
	if (dynamicPrecedence > self.dynamicPrecedence)
		self.dynamicPrecedence = dynamicPrecedence;
}

Stack* tsStackNew(return scope Allocator alloc) @trusted
{
	Stack* self = alloc.newItem!Stack();
	self.alloc = alloc;
	self.heads = TsArray!StackHead(alloc);
	self.slices = StackSliceArray(alloc);
	self.iterators = TsArray!StackIterator(alloc);
	self.heads.reserve(4);
	self.slices.reserve(4);
	self.iterators.reserve(4);
	self.baseNode = stackNodeNew(alloc, null, NULL_SUBTREE, false, 1);
	self.clear();
	return self;
}

/*******************/
/* Section - Tree   */
/*******************/

struct TSTree
{
	Subtree root;
	const(TSLanguage)* language;
}

TSTree* tsTreeNew(return scope Allocator alloc, Subtree root, const(TSLanguage)* language) @trusted
{
	TSTree* result = alloc.newItem!TSTree();
	result.root = root;
	result.language = language;
	return result;
}

TSNode tsTreeRootNode(const(TSTree)* self) @trusted
{
	return tsNodeNew(self, &self.root, tsSubtreePadding(cast(Subtree) self.root), 0);
}

const(TSLanguage)* tsTreeLanguage(const(TSTree)* self) => self.language;

// Trees live in the parser's arena, so deletion is a no-op.
void tsTreeDelete(TSTree* self) {}

/*******************/
/* Section - Node   */
/*******************/

struct NodeChildIterator
{
	Subtree parent;
	const(TSTree)* tree;
	Length position;
	uint childIndex;
	uint structuralChildIndex;
	const(TSSymbol)* aliasSequence;

	private bool done()
	{
		return childIndex == parent.ptr.childCount;
	}

	private bool next(ref TSNode result) @trusted
	{
		if (!parent.ptr || this.done())
			return false;
		Subtree* child = &tsSubtreeChildren(parent)[childIndex];
		TSSymbol aliasSymbol = 0;
		if (!tsSubtreeExtra(*child))
		{
			if (aliasSequence)
				aliasSymbol = aliasSequence[structuralChildIndex];
			structuralChildIndex++;
		}
		if (childIndex > 0)
			position = lengthAdd(position, tsSubtreePadding(*child));
		result = tsNodeNew(tree, child, position, aliasSymbol);
		position = lengthAdd(position, tsSubtreeSize(*child));
		childIndex++;
		return true;
	}
}

TSNode tsNodeNew(const(TSTree)* tree, const(Subtree)* subtree, Length position, TSSymbol aliasSym) @trusted
{
	TSNode node;
	node.context[0] = position.bytes;
	node.context[1] = position.extent.row;
	node.context[2] = position.extent.column;
	node.context[3] = aliasSym;
	node.id = subtree;
	node.tree = tree;
	return node;
}

private TSNode ts_node__null() => tsNodeNew(null, null, lengthZero(), 0);

uint tsNodeStartByte(TSNode self) => self.context[0];
TSPoint tsNodeStartPoint(TSNode self) => TSPoint(self.context[1], self.context[2]);

private Subtree ts_node__subtree(TSNode self) @trusted => *(cast(Subtree*) self.id);

private bool ts_node__is_relevant(TSNode self, bool includeAnonymous) @trusted
{
	Subtree tree = ts_node__subtree(self);
	if (includeAnonymous)
	{
		return tsSubtreeVisible(tree) || self.aliasSymbol() != 0;
	}
	else
	{
		TSSymbol aliasSym = self.aliasSymbol();
		if (aliasSym)
			return self.tree.language.symbolMetadata(aliasSym).named;
		else
			return tsSubtreeVisible(tree) && tsSubtreeNamed(tree);
	}
}

private uint ts_node__relevant_child_count(TSNode self, bool includeAnonymous) @trusted
{
	Subtree tree = ts_node__subtree(self);
	if (tsSubtreeChildCount(tree) > 0)
		return includeAnonymous ? tree.ptr.visibleChildCount : tree.ptr.namedChildCount;
	else
		return 0;
}

private TSNode ts_node__child(TSNode self, uint childIndex, bool includeAnonymous) @trusted
{
	TSNode result = self;
	bool didDescend = true;
	while (didDescend)
	{
		didDescend = false;
		TSNode child;
		uint index = 0;
		NodeChildIterator iterator = result.iterateChildren();
		while (iterator.next(child))
		{
			if (ts_node__is_relevant(child, includeAnonymous))
			{
				if (index == childIndex)
					return child;
				index++;
			}
			else
			{
				uint grandchildIndex = childIndex - index;
				uint grandchildCount = ts_node__relevant_child_count(child, includeAnonymous);
				if (grandchildIndex < grandchildCount)
				{
					didDescend = true;
					result = child;
					childIndex = grandchildIndex;
					break;
				}
				index += grandchildCount;
			}
		}
	}
	return ts_node__null();
}

private bool tsSubtreeHasTrailingEmptyDescendant(Subtree self, Subtree other) @trusted
{
	foreach_reverse (i; 0 .. tsSubtreeChildCount(self))
	{
		Subtree child = tsSubtreeChildren(self)[i];
		if (tsSubtreeTotalBytes(child) > 0)
			break;
		if (child.ptr is other.ptr || tsSubtreeHasTrailingEmptyDescendant(child, other))
			return true;
	}
	return false;
}

private TSNode ts_node__prev_sibling(TSNode self, bool includeAnonymous) @trusted
{
	Subtree selfSubtree = ts_node__subtree(self);
	bool selfIsEmpty = tsSubtreeTotalBytes(selfSubtree) == 0;
	uint targetEndByte = tsNodeEndByte(self);

	TSNode node = tsNodeParent(self);
	TSNode earlierNode = ts_node__null();
	bool earlierNodeIsRelevant = false;

	while (!tsNodeIsNull(node))
	{
		TSNode earlierChild = ts_node__null();
		bool earlierChildIsRelevant = false;
		bool foundChildContainingTarget = false;

		TSNode child;
		NodeChildIterator iterator = node.iterateChildren();
		while (iterator.next(child))
		{
			if (child.id is self.id)
				break;
			if (iterator.position.bytes > targetEndByte)
			{
				foundChildContainingTarget = true;
				break;
			}
			if (iterator.position.bytes == targetEndByte &&
				(!selfIsEmpty ||
				 tsSubtreeHasTrailingEmptyDescendant(ts_node__subtree(child), selfSubtree)))
			{
				foundChildContainingTarget = true;
				break;
			}
			if (ts_node__is_relevant(child, includeAnonymous))
			{
				earlierChild = child;
				earlierChildIsRelevant = true;
			}
			else if (ts_node__relevant_child_count(child, includeAnonymous) > 0)
			{
				earlierChild = child;
				earlierChildIsRelevant = false;
			}
		}

		if (foundChildContainingTarget)
		{
			if (!tsNodeIsNull(earlierChild))
			{
				earlierNode = earlierChild;
				earlierNodeIsRelevant = earlierChildIsRelevant;
			}
			node = child;
		}
		else if (earlierChildIsRelevant)
			return earlierChild;
		else if (!tsNodeIsNull(earlierChild))
			node = earlierChild;
		else if (earlierNodeIsRelevant)
			return earlierNode;
		else
		{
			node = earlierNode;
			earlierNode = ts_node__null();
			earlierNodeIsRelevant = false;
		}
	}
	return ts_node__null();
}

private TSNode ts_node__next_sibling(TSNode self, bool includeAnonymous) @trusted
{
	uint targetEndByte = tsNodeEndByte(self);
	TSNode node = tsNodeParent(self);
	TSNode laterNode = ts_node__null();
	bool laterNodeIsRelevant = false;

	while (!tsNodeIsNull(node))
	{
		TSNode laterChild = ts_node__null();
		bool laterChildIsRelevant = false;
		TSNode childContainingTarget = ts_node__null();

		TSNode child;
		NodeChildIterator iterator = node.iterateChildren();
		while (iterator.next(child))
		{
			if (iterator.position.bytes < targetEndByte)
				continue;
			if (tsNodeStartByte(child) <= tsNodeStartByte(self))
			{
				if (ts_node__subtree(child).ptr !is ts_node__subtree(self).ptr)
					childContainingTarget = child;
			}
			else if (ts_node__is_relevant(child, includeAnonymous))
			{
				laterChild = child;
				laterChildIsRelevant = true;
				break;
			}
			else if (ts_node__relevant_child_count(child, includeAnonymous) > 0)
			{
				laterChild = child;
				laterChildIsRelevant = false;
				break;
			}
		}

		if (!tsNodeIsNull(childContainingTarget))
		{
			if (!tsNodeIsNull(laterChild))
			{
				laterNode = laterChild;
				laterNodeIsRelevant = laterChildIsRelevant;
			}
			node = childContainingTarget;
		}
		else if (laterChildIsRelevant)
			return laterChild;
		else if (!tsNodeIsNull(laterChild))
			node = laterChild;
		else if (laterNodeIsRelevant)
			return laterNode;
		else
			node = laterNode;
	}
	return ts_node__null();
}

private TSNode ts_node__first_child_for_byte(TSNode self, uint goal, bool includeAnonymous) @trusted
{
	TSNode node = self;
	bool didDescend = true;
	while (didDescend)
	{
		didDescend = false;
		TSNode child;
		NodeChildIterator iterator = node.iterateChildren();
		while (iterator.next(child))
		{
			if (tsNodeEndByte(child) > goal)
			{
				if (ts_node__is_relevant(child, includeAnonymous))
					return child;
				else if (tsNodeChildCount(child) > 0)
				{
					didDescend = true;
					node = child;
					break;
				}
			}
		}
	}
	return ts_node__null();
}

private TSNode ts_node__descendant_for_byte_range(TSNode self, uint rangeStart, uint rangeEnd, bool includeAnonymous) @trusted
{
	TSNode node = self;
	TSNode lastVisibleNode = self;
	bool didDescend = true;
	while (didDescend)
	{
		didDescend = false;
		TSNode child;
		NodeChildIterator iterator = node.iterateChildren();
		while (iterator.next(child))
		{
			uint nodeEnd = iterator.position.bytes;
			if (nodeEnd < rangeEnd)
				continue;
			if (nodeEnd <= rangeStart)
				continue;
			if (rangeStart < tsNodeStartByte(child))
				break;
			node = child;
			if (ts_node__is_relevant(node, includeAnonymous))
				lastVisibleNode = node;
			didDescend = true;
			break;
		}
	}
	return lastVisibleNode;
}

private TSNode ts_node__descendant_for_point_range(TSNode self, TSPoint rangeStart, TSPoint rangeEnd, bool includeAnonymous) @trusted
{
	TSNode node = self;
	TSNode lastVisibleNode = self;
	bool didDescend = true;
	while (didDescend)
	{
		didDescend = false;
		TSNode child;
		NodeChildIterator iterator = node.iterateChildren();
		while (iterator.next(child))
		{
			TSPoint nodeEnd = iterator.position.extent;
			if (pointLt(nodeEnd, rangeEnd))
				continue;
			if (pointLte(nodeEnd, rangeStart))
				continue;
			if (pointLt(rangeStart, tsNodeStartPoint(child)))
				break;
			node = child;
			if (ts_node__is_relevant(node, includeAnonymous))
				lastVisibleNode = node;
			didDescend = true;
			break;
		}
	}
	return lastVisibleNode;
}

uint tsNodeEndByte(TSNode self) => tsNodeStartByte(self) + tsSubtreeSize(ts_node__subtree(self)).bytes;

TSPoint tsNodeEndPoint(TSNode self)
{
	return pointAdd(tsNodeStartPoint(self), tsSubtreeSize(ts_node__subtree(self)).extent);
}

TSSymbol tsNodeSymbol(TSNode self) @trusted
{
	TSSymbol symbol = self.aliasSymbol();
	if (!symbol)
		symbol = tsSubtreeSymbol(ts_node__subtree(self));
	return self.tree.language.publicSymbol(symbol);
}

const(char)* tsNodeType(TSNode self) @trusted
{
	TSSymbol symbol = self.aliasSymbol();
	if (!symbol)
		symbol = tsSubtreeSymbol(ts_node__subtree(self));
	return self.tree.language.symbolName(symbol);
}

const(TSLanguage)* tsNodeLanguage(TSNode self) => self.tree.language;

TSSymbol tsNodeGrammarSymbol(TSNode self) => tsSubtreeSymbol(ts_node__subtree(self));

bool tsNodeEq(TSNode self, TSNode other) => self.tree is other.tree && self.id is other.id;

bool tsNodeIsNull(TSNode self) => self.id is null;

bool tsNodeIsExtra(TSNode self) => tsSubtreeExtra(ts_node__subtree(self));

bool tsNodeIsNamed(TSNode self) @trusted
{
	TSSymbol aliasSym = self.aliasSymbol();
	return aliasSym
		? self.tree.language.symbolMetadata(aliasSym).named
		: tsSubtreeNamed(ts_node__subtree(self));
}

bool tsNodeIsMissing(TSNode self) => tsSubtreeMissing(ts_node__subtree(self));

bool tsNodeHasChanges(TSNode self) => tsSubtreeHasChanges(ts_node__subtree(self));

bool tsNodeHasError(TSNode self) => tsSubtreeErrorCost(ts_node__subtree(self)) > 0;

bool tsNodeIsError(TSNode self) => tsNodeSymbol(self) == tsBuiltinSymError;

uint tsNodeDescendantCount(TSNode self) => tsSubtreeVisibleDescendantCount(ts_node__subtree(self)) + 1;

TSStateId tsNodeParseState(TSNode self) => tsSubtreeParseState(ts_node__subtree(self));

TSNode tsNodeParent(TSNode self) @trusted
{
	TSNode node = tsTreeRootNode(self.tree);
	uint endByte = tsNodeEndByte(self);
	if (node.id is self.id)
		return ts_node__null();

	TSNode lastVisibleNode = node;
	bool didDescend = true;
	while (didDescend)
	{
		didDescend = false;
		TSNode child;
		NodeChildIterator iterator = node.iterateChildren();
		while (iterator.next(child))
		{
			if (tsNodeStartByte(child) > tsNodeStartByte(self) || child.id is self.id)
				break;
			if (iterator.position.bytes >= endByte)
			{
				node = child;
				if (ts_node__is_relevant(child, true))
					lastVisibleNode = node;
				didDescend = true;
				break;
			}
		}
	}
	return lastVisibleNode;
}

TSNode tsNodeChild(TSNode self, uint childIndex) => ts_node__child(self, childIndex, true);
TSNode tsNodeNamedChild(TSNode self, uint childIndex) => ts_node__child(self, childIndex, false);

TSNode tsNodeChildByFieldId(TSNode self, TSFieldId fieldId) @trusted
{
	recur:
	if (!fieldId || tsNodeChildCount(self) == 0)
		return ts_node__null();

	const(TSFieldMapEntry)* fieldMap, fieldMapEnd;
	self.tree.language.fieldMap(ts_node__subtree(self).ptr.productionId, fieldMap, fieldMapEnd);
	if (fieldMap == fieldMapEnd)
		return ts_node__null();

	while (fieldMap.fieldId < fieldId)
	{
		fieldMap++;
		if (fieldMap == fieldMapEnd)
			return ts_node__null();
	}
	while (fieldMapEnd[-1].fieldId > fieldId)
	{
		fieldMapEnd--;
		if (fieldMap == fieldMapEnd)
			return ts_node__null();
	}

	TSNode child;
	NodeChildIterator iterator = self.iterateChildren();
	while (iterator.next(child))
	{
		if (!tsSubtreeExtra(ts_node__subtree(child)))
		{
			uint index = iterator.structuralChildIndex - 1;
			if (index < fieldMap.childIndex)
				continue;

			if (fieldMap.inherited)
			{
				if (fieldMap + 1 == fieldMapEnd)
				{
					self = child;
					goto recur;
				}
				else
				{
					TSNode result = tsNodeChildByFieldId(child, fieldId);
					if (result.id)
						return result;
					fieldMap++;
					if (fieldMap == fieldMapEnd)
						return ts_node__null();
				}
			}
			else if (ts_node__is_relevant(child, true))
			{
				return child;
			}
			else if (tsNodeChildCount(child) > 0)
			{
				return tsNodeChild(child, 0);
			}
			else
			{
				fieldMap++;
				if (fieldMap == fieldMapEnd)
					return ts_node__null();
			}
		}
	}
	return ts_node__null();
}

private const(char)* ts_node__field_name_from_language(TSNode self, uint structuralChildIndex) @trusted
{
	const(TSFieldMapEntry)* fieldMap, fieldMapEnd;
	self.tree.language.fieldMap(ts_node__subtree(self).ptr.productionId, fieldMap, fieldMapEnd);
	for (; fieldMap != fieldMapEnd; fieldMap++)
	{
		if (!fieldMap.inherited && fieldMap.childIndex == structuralChildIndex)
			return self.tree.language.fieldNames[fieldMap.fieldId];
	}
	return null;
}

const(char)* tsNodeFieldNameForChild(TSNode self, uint childIndex) @trusted
{
	TSNode result = self;
	bool didDescend = true;
	const(char)* inheritedFieldName = null;
	while (didDescend)
	{
		didDescend = false;
		TSNode child;
		uint index = 0;
		NodeChildIterator iterator = result.iterateChildren();
		while (iterator.next(child))
		{
			if (ts_node__is_relevant(child, true))
			{
				if (index == childIndex)
				{
					const(char)* fieldName = ts_node__field_name_from_language(result, iterator.structuralChildIndex - 1);
					if (fieldName)
						return fieldName;
					return inheritedFieldName;
				}
				index++;
			}
			else
			{
				uint grandchildIndex = childIndex - index;
				uint grandchildCount = ts_node__relevant_child_count(child, true);
				if (grandchildIndex < grandchildCount)
				{
					const(char)* fieldName = ts_node__field_name_from_language(result, iterator.structuralChildIndex - 1);
					if (fieldName)
						inheritedFieldName = fieldName;
					didDescend = true;
					result = child;
					childIndex = grandchildIndex;
					break;
				}
				index += grandchildCount;
			}
		}
	}
	return null;
}

TSNode tsNodeChildByFieldName(TSNode self, const(char)* name, uint nameLength) @trusted
{
	TSFieldId fieldId = self.tree.language.fieldIdForName(name, nameLength);
	return tsNodeChildByFieldId(self, fieldId);
}

uint tsNodeChildCount(TSNode self) @trusted
{
	Subtree tree = ts_node__subtree(self);
	return (tsSubtreeChildCount(tree) > 0) ? tree.ptr.visibleChildCount : 0;
}

uint tsNodeNamedChildCount(TSNode self) @trusted
{
	Subtree tree = ts_node__subtree(self);
	return (tsSubtreeChildCount(tree) > 0) ? tree.ptr.namedChildCount : 0;
}

TSNode tsNodeNextSibling(TSNode self) => ts_node__next_sibling(self, true);
TSNode tsNodeNextNamedSibling(TSNode self) => ts_node__next_sibling(self, false);
TSNode tsNodePrevSibling(TSNode self) => ts_node__prev_sibling(self, true);
TSNode tsNodePrevNamedSibling(TSNode self) => ts_node__prev_sibling(self, false);

TSNode tsNodeFirstChildForByte(TSNode self, uint byte_) => ts_node__first_child_for_byte(self, byte_, true);
TSNode tsNodeFirstNamedChildForByte(TSNode self, uint byte_) => ts_node__first_child_for_byte(self, byte_, false);

TSNode tsNodeDescendantForByteRange(TSNode self, uint start, uint end) => ts_node__descendant_for_byte_range(self, start, end, true);
TSNode tsNodeNamedDescendantForByteRange(TSNode self, uint start, uint end) => ts_node__descendant_for_byte_range(self, start, end, false);
TSNode tsNodeDescendantForPointRange(TSNode self, TSPoint start, TSPoint end) => ts_node__descendant_for_point_range(self, start, end, true);
TSNode tsNodeNamedDescendantForPointRange(TSNode self, TSPoint start, TSPoint end) => ts_node__descendant_for_point_range(self, start, end, false);

/*******************/
/* Section - Parser */
/*******************/

enum uint MAX_VERSION_COUNT = 6;
enum uint MAX_VERSION_COUNT_OVERFLOW = 4;
enum uint MAX_SUMMARY_DEPTH = 16;
enum uint MAX_COST_DIFFERENCE = 16 * ERROR_COST_PER_SKIPPED_TREE;

struct ReduceAction
{
	uint count;
	TSSymbol symbol;
	int dynamicPrecedence;
	ushort productionId;
}

alias ReduceActionSet = TsArray!ReduceAction;

void tsReduceActionSetAdd(ref ReduceActionSet self, ReduceAction newAction)
{
	foreach (i; 0 .. self.size)
	{
		ReduceAction action = self[i];
		if (action.symbol == newAction.symbol && action.count == newAction.count)
			return;
	}
	self.push(newAction);
}

struct TokenCache
{
	Subtree token;
	Subtree lastExternalToken;
	uint byteIndex;
}

struct TSParser
{
	Lexer lexer;
	Stack* stack;
	const(TSLanguage)* language;
	ReduceActionSet reduceActions;
	Subtree finishedTree;
	SubtreeArray trailingExtras;
	SubtreeArray trailingExtras2;
	SubtreeArray scratchTrees;
	TokenCache tokenCache;
	uint acceptCount;
	Arena* arena;
	Allocator alloc;

	private ErrorComparison compareVersions(ErrorStatus a, ErrorStatus b)
	{
		if (!a.isInError && b.isInError)
			return a.cost < b.cost ? ErrorComparison.takeLeft : ErrorComparison.preferLeft;
		if (a.isInError && !b.isInError)
			return b.cost < a.cost ? ErrorComparison.takeRight : ErrorComparison.preferRight;
		if (a.cost < b.cost)
		{
			return ((b.cost - a.cost) * (1 + a.nodeCount) > MAX_COST_DIFFERENCE)
				? ErrorComparison.takeLeft : ErrorComparison.preferLeft;
		}
		if (b.cost < a.cost)
		{
			return ((a.cost - b.cost) * (1 + b.nodeCount) > MAX_COST_DIFFERENCE)
				? ErrorComparison.takeRight : ErrorComparison.preferRight;
		}
		if (a.dynamicPrecedence > b.dynamicPrecedence)
			return ErrorComparison.preferLeft;
		if (b.dynamicPrecedence > a.dynamicPrecedence)
			return ErrorComparison.preferRight;
		return ErrorComparison.none;
	}

	private ErrorStatus versionStatus(StackVersion ver)
	{
		uint cost = stack.errorCost(ver);
		bool isPaused = stack.isPaused(ver);
		if (isPaused)
			cost += ERROR_COST_PER_SKIPPED_TREE;
		ErrorStatus result;
		result.cost = cost;
		result.nodeCount = stack.nodeCountSinceError(ver);
		result.dynamicPrecedence = stack.dynamicPrecedence(ver);
		result.isInError = isPaused || stack.state(ver) == ERROR_STATE;
		return result;
	}

	private bool betterVersionExists(StackVersion ver, bool isInError, uint cost)
	{
		if (finishedTree.ptr && tsSubtreeErrorCost(finishedTree) <= cost)
			return true;

		Length position = stack.position(ver);
		ErrorStatus status;
		status.cost = cost;
		status.isInError = isInError;
		status.dynamicPrecedence = stack.dynamicPrecedence(ver);
		status.nodeCount = stack.nodeCountSinceError(ver);

		foreach (StackVersion i; 0 .. stack.versionCount())
		{
			if (i == ver || !stack.isActive(i) ||
				stack.position(i).bytes < position.bytes)
				continue;
			ErrorStatus statusI = this.versionStatus(i);
			final switch (this.compareVersions(status, statusI))
			{
				case ErrorComparison.takeRight:
					return true;
				case ErrorComparison.preferRight:
					if (stack.canMerge(i, ver))
						return true;
					break;
				case ErrorComparison.takeLeft:
				case ErrorComparison.preferLeft:
				case ErrorComparison.none:
					break;
			}
		}
		return false;
	}

	private bool canReuseFirstLeaf(TSStateId state, Subtree tree, ref TableEntry tableEntry) @trusted
	{
		TSLexMode currentLexMode = language.lexModes[state];
		TSSymbol leafSymbol = tsSubtreeLeafSymbol(tree);
		TSStateId leafState = tsSubtreeLeafParseState(tree);
		TSLexMode leafLexMode = language.lexModes[leafState];

		if (currentLexMode.lexState == cast(ushort)(-1))
			return false;

		if (tableEntry.actionCount > 0 &&
			leafLexMode == currentLexMode &&
			(leafSymbol != language.keywordCaptureToken ||
			 (!tsSubtreeIsKeyword(tree) && tsSubtreeParseState(tree) == state)))
			return true;

		if (tsSubtreeSize(tree).bytes == 0 && leafSymbol != tsBuiltinSymEnd)
			return false;

		return currentLexMode.externalLexState == 0 && tableEntry.isReusable;
	}

	private Subtree lex(StackVersion ver, TSStateId parseState) @trusted
	{
		TSLexMode lexMode = language.lexModes[parseState];
		if (lexMode.lexState == cast(ushort)-1)
			return NULL_SUBTREE;

		const Length startPosition = stack.position(ver);

		bool errorMode = parseState == ERROR_STATE;
		bool skippedError = false;
		int firstErrorCharacter = 0;
		Length errorStartPosition = lengthZero();
		Length errorEndPosition = lengthZero();
		uint lookaheadEndByte = 0;
		lexer.reset(startPosition);

		for (;;)
		{
			Length currentPosition = lexer.currentPosition;
			lexer.start();
			bool foundToken = language.lexFn(&lexer.data, lexMode.lexState);
			lexer.finish(lookaheadEndByte);
			if (foundToken)
				break;

			if (!errorMode)
			{
				errorMode = true;
				lexMode = language.lexModes[ERROR_STATE];
				lexer.reset(startPosition);
				continue;
			}

			if (!skippedError)
			{
				skippedError = true;
				errorStartPosition = lexer.tokenStartPosition;
				errorEndPosition = lexer.tokenStartPosition;
				firstErrorCharacter = lexer.data.lookahead;
			}

			if (lexer.currentPosition.bytes == errorEndPosition.bytes)
			{
				if (lexer.data.eof(&lexer.data))
				{
					lexer.data.resultSymbol = tsBuiltinSymError;
					break;
				}
				lexer.data.advance(&lexer.data, false);
			}

			errorEndPosition = lexer.currentPosition;
		}

		Subtree result;
		if (skippedError)
		{
			Length padding = lengthSub(errorStartPosition, startPosition);
			Length size = lengthSub(errorEndPosition, errorStartPosition);
			uint lookaheadBytes = lookaheadEndByte - errorEndPosition.bytes;
			result = tsSubtreeNewError(
				alloc, firstErrorCharacter, padding, size, lookaheadBytes, parseState, *language);
		}
		else
		{
			bool isKeyword = false;
			TSSymbol symbol = lexer.data.resultSymbol;
			Length padding = lengthSub(lexer.tokenStartPosition, startPosition);
			Length size = lengthSub(lexer.tokenEndPosition, lexer.tokenStartPosition);
			uint lookaheadBytes = lookaheadEndByte - lexer.tokenEndPosition.bytes;

			if (symbol == language.keywordCaptureToken && symbol != 0)
			{
				uint endByte = lexer.tokenEndPosition.bytes;
				lexer.reset(lexer.tokenStartPosition);
				lexer.start();
				if (language.keywordLexFn(&lexer.data, 0) &&
					lexer.tokenEndPosition.bytes == endByte &&
					language.hasActions(parseState, lexer.data.resultSymbol))
				{
					isKeyword = true;
					symbol = lexer.data.resultSymbol;
				}
			}

			result = tsSubtreeNewLeaf(
				alloc, symbol, padding, size, lookaheadBytes, parseState, false, isKeyword, *language);
		}
		return result;
	}

	private Subtree getCachedToken(TSStateId state, size_t position, Subtree lastExternalToken, ref TableEntry tableEntry)
	{
		TokenCache* cache = &tokenCache;
		if (cache.token.ptr && cache.byteIndex == position &&
			tsSubtreeExternalScannerStateEq(cache.lastExternalToken, lastExternalToken))
		{
			language.tableEntry(state, tsSubtreeSymbol(cache.token), tableEntry);
			if (this.canReuseFirstLeaf(state, cache.token, tableEntry))
				return cache.token;
		}
		return NULL_SUBTREE;
	}

	private void setCachedToken(uint byteIndex, Subtree lastExternalToken, Subtree token)
	{
		TokenCache* cache = &tokenCache;
		cache.token = token;
		cache.byteIndex = byteIndex;
		cache.lastExternalToken = lastExternalToken;
	}

	// If the previous subtree at the top of the stack was a pending (multi-child)
	// node, break it down into its children. Inert in non-incremental parses, but
	// kept for fidelity.
	private bool breakdownTopOfStack(StackVersion ver) @trusted
	{
		bool didBreakDown = false;
		bool pending = false;
		do
		{
			StackSliceArray pop = stack.popPending(ver);
			if (!pop.size)
				break;

			didBreakDown = true;
			pending = false;
			foreach (i; 0 .. pop.size)
			{
				StackSlice slice = pop[i];
				TSStateId state = stack.state(slice.version_);
				Subtree parent = slice.subtrees[0];

				foreach (j; 0 .. tsSubtreeChildCount(parent))
				{
					Subtree child = tsSubtreeChildren(parent)[j];
					pending = tsSubtreeChildCount(child) > 0;

					if (tsSubtreeIsError(child))
						state = ERROR_STATE;
					else if (!tsSubtreeExtra(child))
						state = language.nextState(state, tsSubtreeSymbol(child));

					stack.push(slice.version_, child, pending, state);
				}

				foreach (j; 1 .. slice.subtrees.size)
				{
					Subtree tree = slice.subtrees[j];
					stack.push(slice.version_, tree, false, state);
				}
			}
		}
		while (pending);

		return didBreakDown;
	}

	private bool selectTree(Subtree left, Subtree right)
	{
		if (!left.ptr)
			return true;
		if (!right.ptr)
			return false;
		if (tsSubtreeErrorCost(right) < tsSubtreeErrorCost(left))
			return true;
		if (tsSubtreeErrorCost(left) < tsSubtreeErrorCost(right))
			return false;
		if (tsSubtreeDynamicPrecedence(right) > tsSubtreeDynamicPrecedence(left))
			return true;
		if (tsSubtreeDynamicPrecedence(left) > tsSubtreeDynamicPrecedence(right))
			return false;
		if (tsSubtreeErrorCost(left) > 0)
			return true;
		int comparison = tsSubtreeCompare(left, right);
		switch (comparison)
		{
			case -1: return false;
			case 1: return true;
			default: return false;
		}
	}

	private bool selectChildren(Subtree left, ref const SubtreeArray children)
	{
		scratchTrees.assign(children);
		Subtree scratchTree = tsSubtreeNewNode(
			alloc, tsSubtreeSymbol(left), scratchTrees, 0, *language);
		return this.selectTree(left, scratchTree);
	}

	private void shift(StackVersion ver, TSStateId state, Subtree lookahead, bool extra)
	{
		bool isLeaf = tsSubtreeChildCount(lookahead) == 0;
		Subtree subtreeToPush = lookahead;
		if (extra != tsSubtreeExtra(lookahead) && isLeaf)
		{
			Subtree result = tsSubtreeMakeMut(alloc, lookahead);
			tsSubtreeSetExtra(result, extra);
			subtreeToPush = result;
		}
		stack.push(ver, subtreeToPush, !isLeaf, state);
	}

	private StackVersion reduce(StackVersion ver, TSSymbol symbol, uint count, int dynamicPrecedence, ushort productionId, bool isFragile, bool endOfNonTerminalExtra) @trusted
	{
		uint initialVersionCount = stack.versionCount();

		StackSliceArray pop = stack.popCount(ver, count);
		uint removedVersionCount = 0;
		for (uint i = 0; i < pop.size; i++)
		{
			StackSlice slice = pop[i];
			StackVersion sliceVersion = slice.version_ - removedVersionCount;

			if (sliceVersion > MAX_VERSION_COUNT + MAX_VERSION_COUNT_OVERFLOW)
			{
				stack.removeVersion(sliceVersion);
				removedVersionCount++;
				while (i + 1 < pop.size)
				{
					StackSlice nextSlice = pop[i + 1];
					if (nextSlice.version_ != slice.version_)
						break;
					i++;
				}
				continue;
			}

			SubtreeArray children = slice.subtrees;
			tsSubtreeArrayRemoveTrailingExtras(children, trailingExtras);

			Subtree parent = tsSubtreeNewNode(alloc, symbol, children, productionId, *language);

			while (i + 1 < pop.size)
			{
				StackSlice nextSlice = pop[i + 1];
				if (nextSlice.version_ != slice.version_)
					break;
				i++;

				SubtreeArray nextSliceChildren = nextSlice.subtrees;
				tsSubtreeArrayRemoveTrailingExtras(nextSliceChildren, trailingExtras2);

				if (this.selectChildren(parent, nextSliceChildren))
				{
					trailingExtras.clear();
					trailingExtras.swap(trailingExtras2);
					parent = tsSubtreeNewNode(alloc, symbol, nextSliceChildren, productionId, *language);
				}
				else
				{
					trailingExtras2.clear();
				}
			}

			TSStateId state = stack.state(sliceVersion);
			TSStateId nextState = language.nextState(state, symbol);
			if (endOfNonTerminalExtra && nextState == state)
				parent.ptr.extra = true;
			if (isFragile || pop.size > 1 || initialVersionCount > 1)
			{
				parent.ptr.fragileLeft = true;
				parent.ptr.fragileRight = true;
				parent.ptr.parseState = TS_TREE_STATE_NONE;
			}
			else
			{
				parent.ptr.parseState = state;
			}
			parent.ptr.dynamicPrecedence += dynamicPrecedence;

			stack.push(sliceVersion, parent, false, nextState);
			foreach (j; 0 .. trailingExtras.size)
				stack.push(sliceVersion, trailingExtras[j], false, nextState);

			foreach (StackVersion j; 0 .. sliceVersion)
			{
				if (j == ver)
					continue;
				if (stack.merge(j, sliceVersion))
				{
					removedVersionCount++;
					break;
				}
			}
		}

		return stack.versionCount() > initialVersionCount ? initialVersionCount : STACK_VERSION_NONE;
	}

	private void accept(StackVersion ver, Subtree lookahead) @trusted
	{
		assert(tsSubtreeIsEof(lookahead));
		stack.push(ver, lookahead, false, 1);

		StackSliceArray pop = stack.popAll(ver);
		foreach (i; 0 .. pop.size)
		{
			SubtreeArray trees = pop[i].subtrees;
			Subtree root = NULL_SUBTREE;
			foreach_reverse (j; 0 .. trees.size)
			{
				Subtree tree = trees[j];
				if (!tsSubtreeExtra(tree))
				{
					uint childCount = tsSubtreeChildCount(tree);
					Subtree[] children = tsSubtreeChildren(tree);
					trees.splice(j, 1, childCount, children.ptr);
					root = tsSubtreeNewNode(
						alloc, tsSubtreeSymbol(tree), trees, tree.ptr.productionId, *language);
					break;
				}
			}

			assert(root.ptr);
			acceptCount++;

			if (finishedTree.ptr)
			{
				if (this.selectTree(finishedTree, root))
					finishedTree = root;
			}
			else
			{
				finishedTree = root;
			}
		}

		stack.removeVersion(pop[0].version_);
		stack.halt(ver);
	}

	private bool doAllPotentialReductions(StackVersion startingVersion, TSSymbol lookaheadSymbol) @trusted
	{
		uint initialVersionCount = stack.versionCount();
		bool canShiftLookaheadSymbol = false;
		StackVersion ver = startingVersion;
		for (uint i = 0;; i++)
		{
			uint versionCount = stack.versionCount();
			if (ver >= versionCount)
				break;

			bool merged = false;
			foreach (StackVersion j; initialVersionCount .. ver)
			{
				if (stack.merge(j, ver))
				{
					merged = true;
					break;
				}
			}
			if (merged)
				continue;

			TSStateId state = stack.state(ver);
			bool hasShiftAction = false;
			reduceActions.clear();

			TSSymbol firstSymbol, endSymbol;
			if (lookaheadSymbol != 0)
			{
				firstSymbol = lookaheadSymbol;
				endSymbol = cast(TSSymbol)(lookaheadSymbol + 1);
			}
			else
			{
				firstSymbol = 1;
				endSymbol = cast(TSSymbol) language.tokenCount;
			}

			foreach (TSSymbol symbol; firstSymbol .. endSymbol)
			{
				TableEntry entry;
				language.tableEntry(state, symbol, entry);
				foreach (j; 0 .. entry.actionCount)
				{
					TSParseAction action = entry.actions[j];
					switch (action.type)
					{
						case TSParseActionType.shift:
						case TSParseActionType.recover:
							if (!action.shift.extra && !action.shift.repetition)
								hasShiftAction = true;
							break;
						case TSParseActionType.reduce:
							if (action.reduce.childCount > 0)
								tsReduceActionSetAdd(reduceActions, ReduceAction(
									action.reduce.childCount, action.reduce.symbol,
									action.reduce.dynamicPrecedence, action.reduce.productionId));
							break;
						default:
							break;
					}
				}
			}

			StackVersion reductionVersion = STACK_VERSION_NONE;
			foreach (j; 0 .. reduceActions.size)
			{
				ReduceAction action = reduceActions[j];
				reductionVersion = this.reduce(ver, action.symbol, action.count, action.dynamicPrecedence, action.productionId, true, false);
			}

			if (hasShiftAction)
				canShiftLookaheadSymbol = true;
			else if (reductionVersion != STACK_VERSION_NONE && i < MAX_VERSION_COUNT)
			{
				stack.renumberVersion(reductionVersion, ver);
				continue;
			}
			else if (lookaheadSymbol != 0)
				stack.removeVersion(ver);

			if (ver == startingVersion)
				ver = versionCount;
			else
				ver++;
		}

		return canShiftLookaheadSymbol;
	}

	private bool recoverToState(StackVersion ver, uint depth, TSStateId goalState) @trusted
	{
		StackSliceArray pop = stack.popCount(ver, depth);
		StackVersion previousVersion = STACK_VERSION_NONE;

		for (uint i = 0; i < pop.size; i++)
		{
			StackSlice slice = pop[i];

			if (slice.version_ == previousVersion)
			{
				pop.erase(i);
				i--;
				continue;
			}

			if (stack.state(slice.version_) != goalState)
			{
				stack.halt(slice.version_);
				pop.erase(i);
				i--;
				continue;
			}

			SubtreeArray errorTrees = stack.popError(slice.version_);
			if (errorTrees.size > 0)
			{
				assert(errorTrees.size == 1);
				Subtree errorTree = errorTrees[0];
				uint errorChildCount = tsSubtreeChildCount(errorTree);
				if (errorChildCount > 0)
				{
					slice.subtrees.splice(0, 0, errorChildCount, tsSubtreeChildren(errorTree).ptr);
				}
			}

			tsSubtreeArrayRemoveTrailingExtras(slice.subtrees, trailingExtras);

			if (slice.subtrees.size > 0)
			{
				Subtree error = tsSubtreeNewErrorNode(alloc, slice.subtrees, true, *language);
				stack.push(slice.version_, error, false, goalState);
			}

			foreach (j; 0 .. trailingExtras.size)
			{
				Subtree tree = trailingExtras[j];
				stack.push(slice.version_, tree, false, goalState);
			}

			previousVersion = slice.version_;
		}

		return previousVersion != STACK_VERSION_NONE;
	}

	private void recover(StackVersion ver, Subtree lookahead) @trusted
	{
		bool didRecover = false;
		uint previousVersionCount = stack.versionCount();
		Length position = stack.position(ver);
		StackSummary* summary = stack.getSummary(ver);
		uint nodeCountSinceError = stack.nodeCountSinceError(ver);
		uint currentErrorCost = stack.errorCost(ver);

		if (summary && !tsSubtreeIsError(lookahead))
		{
			foreach (i; 0 .. summary.size)
			{
				StackSummaryEntry entry = (*summary)[i];
				if (entry.state == ERROR_STATE)
					continue;
				if (entry.position.bytes == position.bytes)
					continue;
				uint depth = entry.depth;
				if (nodeCountSinceError > 0)
					depth++;

				bool wouldMerge = false;
				foreach (j; 0 .. previousVersionCount)
				{
					if (stack.state(j) == entry.state &&
						stack.position(j).bytes == position.bytes)
					{
						wouldMerge = true;
						break;
					}
				}
				if (wouldMerge)
					continue;

				uint newCost =
					currentErrorCost +
					entry.depth * ERROR_COST_PER_SKIPPED_TREE +
					(position.bytes - entry.position.bytes) * ERROR_COST_PER_SKIPPED_CHAR +
					(position.extent.row - entry.position.extent.row) * ERROR_COST_PER_SKIPPED_LINE;
				if (this.betterVersionExists(ver, false, newCost))
					break;

				if (language.hasActions(entry.state, tsSubtreeSymbol(lookahead)))
				{
					if (this.recoverToState(ver, depth, entry.state))
					{
						didRecover = true;
						break;
					}
				}
			}
		}

		for (uint i = previousVersionCount; i < stack.versionCount(); i++)
		{
			if (!stack.isActive(i))
			{
				stack.removeVersion(i);
				i--;
			}
		}

		if (didRecover && stack.versionCount() > MAX_VERSION_COUNT)
		{
			stack.halt(ver);
			return;
		}

		if (tsSubtreeIsEof(lookahead))
		{
			SubtreeArray children = SubtreeArray(alloc);
			Subtree parent = tsSubtreeNewErrorNode(alloc, children, false, *language);
			stack.push(ver, parent, false, 1);
			this.accept(ver, lookahead);
			return;
		}

		uint newCost =
			currentErrorCost + ERROR_COST_PER_SKIPPED_TREE +
			tsSubtreeTotalBytes(lookahead) * ERROR_COST_PER_SKIPPED_CHAR +
			tsSubtreeTotalSize(lookahead).extent.row * ERROR_COST_PER_SKIPPED_LINE;
		if (this.betterVersionExists(ver, false, newCost))
		{
			stack.halt(ver);
			return;
		}

		const(TSParseAction)[] actions = language.actions(1, tsSubtreeSymbol(lookahead));
		if (actions.length > 0 && actions[$ - 1].type == TSParseActionType.shift && actions[$ - 1].shift.extra)
		{
			Subtree mutableLookahead = tsSubtreeMakeMut(alloc, lookahead);
			tsSubtreeSetExtra(mutableLookahead, true);
			lookahead = mutableLookahead;
		}

		SubtreeArray children = SubtreeArray(alloc);
		children.reserve(1);
		children.push(lookahead);
		Subtree errorRepeat = tsSubtreeNewNode(alloc, tsBuiltinSymErrorRepeat, children, 0, *language);

		if (nodeCountSinceError > 0)
		{
			StackSliceArray pop = stack.popCount(ver, 1);
			if (pop.size > 1)
			{
				while (stack.versionCount() > pop[0].version_ + 1)
					stack.removeVersion(pop[0].version_ + 1);
			}
			stack.renumberVersion(pop[0].version_, ver);
			pop[0].subtrees.push(errorRepeat);
			errorRepeat = tsSubtreeNewNode(alloc, tsBuiltinSymErrorRepeat, pop[0].subtrees, 0, *language);
		}

		stack.push(ver, errorRepeat, false, ERROR_STATE);
	}

	private void handleError(StackVersion ver, Subtree lookahead) @trusted
	{
		uint previousVersionCount = stack.versionCount();

		this.doAllPotentialReductions(ver, 0);
		uint versionCount = stack.versionCount();
		Length position = stack.position(ver);

		bool didInsertMissingToken = false;
		for (StackVersion v = ver; v < versionCount;)
		{
			if (!didInsertMissingToken)
			{
				TSStateId state = stack.state(v);
				foreach (TSSymbol missingSymbol; 1 .. cast(ushort) language.tokenCount)
				{
					TSStateId stateAfterMissingSymbol = language.nextState(state, missingSymbol);
					if (stateAfterMissingSymbol == 0 || stateAfterMissingSymbol == state)
						continue;

					if (language.hasReduceAction(stateAfterMissingSymbol, tsSubtreeLeafSymbol(lookahead)))
					{
						lexer.reset(position);
						lexer.markEndPublic();
						Length padding = lengthSub(lexer.tokenEndPosition, position);
						uint lookaheadBytes = tsSubtreeTotalBytes(lookahead) + tsSubtreeLookaheadBytes(lookahead);

						StackVersion versionWithMissingTree = stack.copyVersion(v);
						Subtree missingTree = tsSubtreeNewMissingLeaf(
							alloc, missingSymbol, padding, lookaheadBytes, *language);
						stack.push(versionWithMissingTree, missingTree, false, stateAfterMissingSymbol);

						if (this.doAllPotentialReductions(versionWithMissingTree, tsSubtreeLeafSymbol(lookahead)))
						{
							didInsertMissingToken = true;
							break;
						}
					}
				}
			}

			stack.push(v, NULL_SUBTREE, false, ERROR_STATE);
			v = (v == ver) ? previousVersionCount : v + 1;
		}

		foreach (i; previousVersionCount .. versionCount)
		{
			bool didMerge = stack.merge(ver, previousVersionCount);
			assert(didMerge);
		}

		stack.recordSummary(ver, MAX_SUMMARY_DEPTH);
		this.recover(ver, lookahead);
	}

	private bool advance(StackVersion ver) @trusted
	{
		TSStateId state = stack.state(ver);
		uint position = stack.position(ver).bytes;
		Subtree lastExternalToken = stack.lastExternalToken(ver);

		Subtree lookahead = NULL_SUBTREE;
		TableEntry tableEntry;
		tableEntry.actionCount = 0;

		lookahead = this.getCachedToken(state, position, lastExternalToken, tableEntry);

		bool needsLex = !lookahead.ptr;
		for (;;)
		{
			if (needsLex)
			{
				needsLex = false;
				lookahead = this.lex(ver, state);
				if (lookahead.ptr)
				{
					this.setCachedToken(position, lastExternalToken, lookahead);
					language.tableEntry(state, tsSubtreeSymbol(lookahead), tableEntry);
				}
				else
				{
					language.tableEntry(state, tsBuiltinSymEnd, tableEntry);
				}
			}

			StackVersion lastReductionVersion = STACK_VERSION_NONE;
			foreach (i; 0 .. tableEntry.actionCount)
			{
				TSParseAction action = tableEntry.actions[i];
				switch (action.type)
				{
					case TSParseActionType.shift:
						if (action.shift.repetition)
							break;
						TSStateId nextState = action.shift.extra ? state : action.shift.state;
						this.shift(ver, nextState, lookahead, action.shift.extra);
						return true;

					case TSParseActionType.reduce:
						bool isFragile = tableEntry.actionCount > 1;
						bool endOfNonTerminalExtra = lookahead.ptr is null;
						StackVersion reductionVersion = this.reduce(ver, action.reduce.symbol, action.reduce.childCount, action.reduce.dynamicPrecedence, action.reduce.productionId, isFragile, endOfNonTerminalExtra);
						if (reductionVersion != STACK_VERSION_NONE)
							lastReductionVersion = reductionVersion;
						break;

					case TSParseActionType.accept:
						this.accept(ver, lookahead);
						return true;

					case TSParseActionType.recover:
						this.recover(ver, lookahead);
						return true;

					default:
						break;
				}
			}

			if (lastReductionVersion != STACK_VERSION_NONE)
			{
				stack.renumberVersion(lastReductionVersion, ver);
				state = stack.state(ver);
				if (!lookahead.ptr)
					needsLex = true;
				else
					language.tableEntry(state, tsSubtreeLeafSymbol(lookahead), tableEntry);
				continue;
			}

			if (!lookahead.ptr)
			{
				stack.halt(ver);
				return true;
			}

			if (tsSubtreeIsKeyword(lookahead) && tsSubtreeSymbol(lookahead) != language.keywordCaptureToken)
			{
				language.tableEntry(state, language.keywordCaptureToken, tableEntry);
				if (tableEntry.actionCount > 0)
				{
					Subtree mutableLookahead = tsSubtreeMakeMut(alloc, lookahead);
					tsSubtreeSetSymbol(mutableLookahead, language.keywordCaptureToken, *language);
					lookahead = mutableLookahead;
					continue;
				}
			}

			if (state == ERROR_STATE)
			{
				this.recover(ver, lookahead);
				return true;
			}

			if (this.breakdownTopOfStack(ver))
			{
				state = stack.state(ver);
				needsLex = true;
				continue;
			}

			stack.pause(ver, lookahead);
			return true;
		}
	}

	private uint condenseStack() @trusted
	{
		bool madeChanges = false;
		uint minErrorCost = uint.max;
		for (StackVersion i = 0; i < stack.versionCount(); i++)
		{
			if (stack.isHalted(i))
			{
				stack.removeVersion(i);
				i--;
				continue;
			}

			ErrorStatus statusI = this.versionStatus(i);
			if (!statusI.isInError && statusI.cost < minErrorCost)
				minErrorCost = statusI.cost;

			for (StackVersion j = 0; j < i; j++)
			{
				ErrorStatus statusJ = this.versionStatus(j);
				final switch (this.compareVersions(statusJ, statusI))
				{
					case ErrorComparison.takeLeft:
						madeChanges = true;
						stack.removeVersion(i);
						i--;
						j = i;
						break;

					case ErrorComparison.preferLeft:
					case ErrorComparison.none:
						if (stack.merge(j, i))
						{
							madeChanges = true;
							i--;
							j = i;
						}
						break;

					case ErrorComparison.preferRight:
						madeChanges = true;
						if (stack.merge(j, i))
						{
							i--;
							j = i;
						}
						else
						{
							stack.swapVersions(i, j);
						}
						break;

					case ErrorComparison.takeRight:
						madeChanges = true;
						stack.removeVersion(j);
						i--;
						j--;
						break;
				}
			}
		}

		while (stack.versionCount() > MAX_VERSION_COUNT)
		{
			stack.removeVersion(MAX_VERSION_COUNT);
			madeChanges = true;
		}

		if (stack.versionCount() > 0)
		{
			bool hasUnpausedVersion = false;
			for (StackVersion i = 0, n = stack.versionCount(); i < n; i++)
			{
				if (stack.isPaused(i))
				{
					if (!hasUnpausedVersion && acceptCount < MAX_VERSION_COUNT)
					{
						minErrorCost = stack.errorCost(i);
						Subtree lookahead = stack.resume(i);
						this.handleError(i, lookahead);
						hasUnpausedVersion = true;
					}
					else
					{
						stack.removeVersion(i);
						i--;
						n--;
					}
				}
				else
				{
					hasUnpausedVersion = true;
				}
			}
		}

		return minErrorCost;
	}

	private bool hasOutstandingParse()
	{
		return stack.state(0) != 1 || stack.nodeCountSinceError(0) != 0;
	}

	bool setLanguage(const(TSLanguage)* language)
	{
		if (language)
		{
			if (language.version_ > TREE_SITTER_LANGUAGE_VERSION)
				return false;
			if (language.version_ < TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION)
				return false;
		}
		this.language = language;
		this.reset();
		return true;
	}

	void reset()
	{
		lexer.reset(lengthZero());
		stack.clear();
		this.setCachedToken(0, NULL_SUBTREE, NULL_SUBTREE);
		finishedTree = NULL_SUBTREE;
		acceptCount = 0;
	}

	TSTree* parseString(const(TSTree)* oldTree, const(char)* str, uint length) @trusted
	{
		if (!language)
			return null;

		lexer.setInput((cast(const(ubyte)*) str)[0 .. length]);

		uint position = 0, lastPosition = 0, versionCount = 0;
		do
		{
			for (StackVersion ver = 0;; ver++)
			{
				versionCount = stack.versionCount();
				if (ver >= versionCount)
					break;
				while (stack.isActive(ver))
				{
					if (!this.advance(ver))
						return null;

					position = stack.position(ver).bytes;
					if (position > lastPosition || (ver > 0 && position == lastPosition))
					{
						lastPosition = position;
						break;
					}
				}
			}

			uint minErrorCost = this.condenseStack();

			if (finishedTree.ptr && tsSubtreeErrorCost(finishedTree) < minErrorCost)
			{
				stack.clear();
				break;
			}
		}
		while (versionCount != 0);

		assert(finishedTree.ptr);
		TSTree* result = tsTreeNew(alloc, finishedTree, language);
		finishedTree = NULL_SUBTREE;
		this.reset();
		return result;
	}
}

struct ErrorStatus
{
	uint cost;
	uint nodeCount;
	int dynamicPrecedence;
	bool isInError;
}

enum ErrorComparison
{
	takeLeft,
	preferLeft,
	none,
	preferRight,
	takeRight,
}

// Parser - Public ---------------------------------------------------------

/// Create a parser. All parse memory (including the trees it produces) is
/// allocated from a single arena that lives as long as the parser, so trees
/// remain valid until `ts_parser_delete`.
TSParser* tsParserNew() @trusted
{
	import core.stdc.stdlib : malloc;
	// The arena is malloc'd at a stable address (an Allocator binds to its
	// address). A zeroed Arena is a valid empty arena that mallocs its first
	// page lazily.
	Arena* arena = cast(Arena*) malloc(Arena.sizeof);
	memset(arena, 0, Arena.sizeof);
	Allocator alloc = arena.alloc;

	TSParser* self = alloc.newItem!TSParser();
	self.arena = arena;
	self.alloc = alloc;
	self.lexer.init();
	self.reduceActions = ReduceActionSet(alloc);
	self.reduceActions.reserve(4);
	self.stack = tsStackNew(alloc);
	self.finishedTree = NULL_SUBTREE;
	self.trailingExtras = SubtreeArray(alloc);
	self.trailingExtras2 = SubtreeArray(alloc);
	self.scratchTrees = SubtreeArray(alloc);
	return self;
}

void tsParserDelete(ref TSParser self) @trusted
{
	// Arena pages and the parser itself leak here (matching ctod's existing
	// per-file usage, which never deletes the parser). A short-lived CLI run.
}

