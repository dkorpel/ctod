module ctod.translate;

nothrow @safe:

import ctod.tree_sitter;
import ctod.ctype;
import ctod.cdeclaration;
import ctod.cexpr;
import ctod.cpreproc;

// Enable switching to custom Associative Array type
version(none) {
	import bops.ds.hashtable: Map = HashTable;
} else {
	alias Map(K, V) = V[K];
}

import tree_sitter.api;

private immutable hasVersion = `
private template HasVersion(string versionId) {
	mixin("version("~versionId~") {enum HasVersion = true;} else {enum HasVersion = false;}");
}
`;

struct TranslationSettings {
	bool includeHeader = true;
	bool stripComments = false;
}

///
string translateFile(string source, string moduleName, ref TranslationSettings settings) {
	Node* root = parseCtree(source);
	assert(root);
	auto ctx = CtodCtx("foo.c", source);
	ctx.stripComments = settings.stripComments;
	translateNode(ctx, *root);

	string result = "";

	if (settings.includeHeader) {
		if (moduleName.length > 0) {
			result ~= "module "~moduleName~";\n";
		}
		result ~= "@nogc nothrow:
extern(C): __gshared:\n";
	}

	if (ctx.needsHasVersion) {
		result ~= hasVersion;
	}
	if (ctx.needsClong) {
		result ~= "import core.stdc.config: c_long, c_ulong;\n";
	}
	if (ctx.needsWchar) {
		result ~= "import core.stdc.stddef: wchar_t;\n";
	}
	if (ctx.needsCbool) {
		result ~= "alias c_bool = int;\n";
	}
	// white space leading up to the first AST element is not included in the AST, so add it
	result ~= source[0..root.start];
	result ~= root.output();
	return result;
}

/// What the C macro is for
enum MacroType {
	none, // und
	manifestConstant, // #define three 3
	inlineFunc, // #define SQR(x) (x*x)
	versionId, // #ifdef _WIN32_
	staticIf,
}

/// Variables for a `struct` / `union` / `enum` declaration
struct TypeScope {
	Sym sym; // Sym.union_specifier, Sym.struct_specifier, Sym.enum_specifier
	int fieldIndex = 0; // counts up every declaration
}
/// Translation context, all 'global' state
package
struct CtodCtx {

	string fileName;
	string source;
	string moduleName;

	/// HasVersion(string) template is needed
	bool needsHasVersion = false;
	/// needs c_long types (long has no consistent .sizeof, 4 on 64-bit Windows, 8 on 64-bit Linux)
	bool needsClong = false;
	/// needs wchar_t type (wchar on Windows, dchar on Linux)
	bool needsWchar = false;
	/// needs `alias c_bool = int;`
	bool needsCbool = false;

	bool stripComments = false;

	/// global variables and function declarations
	Map!(string, Decl) symbolTable;
	Map!(string, Decl) localSymbolTable;
	Map!(string, MacroType) macroTable;
	Map!(ulong, CType) nodeTypes;
	InlineType[] inlineTypes; // collect structs, unions and enums definitions that were defined in expressions
	string inFunction = null; // name of the function we're currently in
	CType inDeclType = CType.none; // type of the declaration we're currently in
	int inParameterList = 0; // If we're in a parameter list (function types can be nested, so not a bool)
	private TypeScope[] typeScope = null; // stack of "struct" "enum" "union"

nothrow:

	this(string fileName, string source) {
		this.fileName = fileName;
		this.source = source;
		this.typeScope = [TypeScope(Sym.null_)];
	}

	void enterFunction(string functionName) {
		this.inFunction = functionName;
	}

	void leaveFunction() @trusted {
		this.inFunction = null;
		this.localSymbolTable.clear();
	}

	void pushTypeScope(Sym sym) {
		this.typeScope ~= TypeScope(sym);
	}

	void popTypeScope() {
		this.typeScope.length--;
	}

	/// Gives info what struct / union we're in
	ref TypeScope currentTypeScope() { return this.typeScope[$-1]; }

	bool inUnion() {
		return currentTypeScope().sym == Sym.union_specifier;
	}

	CType expType(ref Node node) {
		if (auto type = node.id in nodeTypes) {
			return *type;
		}
		return CType.none;
	}

	void setExpType(ref Node node, CType type) {
		nodeTypes[node.id] = type;
	}

	Decl lookupDecl(string id) {
		if (auto local = id in localSymbolTable) {
			return *local;
		} else if (auto global = id in symbolTable) {
			return *global;
		} else {
			return Decl.none;
		}
	}

	void registerDecl(Decl decl) {
		if (decl.identifier) {
			if (inFunction) {
				localSymbolTable[decl.identifier] = decl;
			} else {
				symbolTable[decl.identifier] = decl;
			}
		}
		currentTypeScope().fieldIndex++;
	}

	int uniqueIdCounter = 0;
	string uniqueIdentifier(string suggestion) {
		static toUpper(char c) {return cast(char) (c - (c >= 'a' && c <= 'z') * ('a' - 'A'));}
		if (suggestion.length > 0) {
			return "_" ~ toUpper(suggestion[0]) ~ suggestion[1..$];
		} else {
			assert(0);
		}
	}
}

///
void translateNode(ref CtodCtx ctx, ref Node node) {
	if (node.isTranslated) {
		return;
	}
	scope(exit) node.isTranslated = true;

	if (ctodTryPreprocessor(ctx, node)) {
		return;
	}
	if (ctodTryDeclaration(ctx, node)) {
		return;
	}
	if (ctodExpression(ctx, node)) {
		return;
	}
	if (ctodMisc(ctx, node)) {
		return;
	}

	// This comes up in sizeof(unsigned short), or possibly a macro if tree-sitter can parse it
	// TODO: better inlineTypes handling, in case of sizeof(struct {int x; int y;})

	InlineType[] inlineTypes;
	if (auto s = parseTypeNode(ctx, node, inlineTypes, /*keepOpaque*/ true)) {
		// #twab: it was translating global struct definitions as inline types
		if (inlineTypes.length == 0)
		{
			node.replace(s);
			return;
		}
	}

	foreach(ref c; node.children) {
		translateNode(ctx, c);
	}
}

/// Returns: whether the body of a switch statement `node` contains a default statement
bool hasDefaultStatement(ref Node node) {
	foreach(ref c; node.children) {
		if (c.typeEnum == Sym.anon_default) {
			return true;
		}
		if (c.typeEnum == Sym.switch_statement) {
			// any default statement we find in here doesn't belong to the original switch anymore
			continue;
		}
		if (hasDefaultStatement(c)) {
			return true;
		}
	}
	return false;
}

package bool ctodMisc(ref CtodCtx ctx, ref Node node) {
	switch(node.typeEnum) {
		case Sym.comment:
			// TODO: maybe convert doxygen to Ddoc?
			if (ctx.stripComments) {
				node.replace("");
			}
			return true;
		case Sym.if_statement:
		case Sym.while_statement:
		case Sym.for_statement:
			// Assignment may not be used in if / loop conditions in D
			// if (x = 3)    => if ((x = 3) != 0)
			// if (!(x = 3)) => if ((x = 3) == 0)
			if (auto a = node.childField(Field.condition)) {
				if (a.typeEnum == Sym.parenthesized_expression) {
					a = getParenContent(a);
				}
				if (a.typeEnum == Sym.assignment_expression) {
					a.prepend("(");
					a.append(") != 0");
				}
			}
			break;
		case Sym.switch_statement:
			// D mandates `default` case in `switch`
			// note: switch statements can have `case` statements in the weirdest places
			// we can be a bit conservative here and only check the common switch pattern
			if (auto bodyNode = node.childField(Field.body_)) {
				if (bodyNode.typeEnum != Sym.compound_statement)
					break;

				if (hasDefaultStatement(*bodyNode)) {
					break;
				}

				bodyNode.children[$-1].prepend("default: break;");
			}
			break;
		case Sym.primitive_type:
			if (string s = ctodPrimitiveType(node.source)) {
				node.replace(s);
				return true;
			}
			return false;

		case Sym.anon_DASH_GT:
			return node.replace("."); // s->field => s.field
		case Sym.expression_statement:
			// ; as empty statement not allowed in D, for (;;); => for (;;) {}
			if (node.source == ";") {
				return node.replace("{}");
			}
			break;
		case Sym.struct_specifier:
		case Sym.union_specifier:
			// Trailing ; are children of the translation unit, and they are removed
			// However, opaque structs/unions still need them
			if (auto bodyNode = node.childField(Field.body_)) {
				//
			} else {
				node.append(";");
			}
			break;
		case Sym.translation_unit:
			removeSemicolons(node);
			break;
		default: break;
	}
	return false;
}

/// In C there are trailing ; after union and struct definitions.
/// We don't want them in D
/// This should be called on a translation_unit or preproc_if(def) node
package void removeSemicolons(ref Node node) {
	foreach(ref c; node.children) {
		if (c.typeEnum == Sym.anon_SEMI) {
			c.replace("");
		}
	}
}

private immutable string[2][] limitMap = [
	["DBL_DIG", "double.dig"],
	["DBL_EPSILON", "double.epsilon"],
	["DBL_MANT_DIG", "double.mant_dig"],
	["DBL_MAX_10_EXP", "double.max_10_exp"],
	["DBL_MAX_EXP", "double.max_exp"],
	["DBL_MAX", "double.max"],
	["DBL_MIN_10_EXP", "double.min_10_exp"],
	["DBL_MIN_EXP", "double.min_exp"],
	["DBL_MIN", "double.min"],
	["FLT_DIG", "float.dig"],
	["FLT_EPSILON", "float.epsilon"],
	["FLT_MANT_DIG", "float.mant_dig"],
	["FLT_MAX_10_EXP", "float.max_10_exp"],
	["FLT_MAX_EXP", "float.max_exp"],
	["FLT_MAX", "float.max"],
	["FLT_MIN_10_EXP", "float.min_10_exp"],
	["FLT_MIN_EXP", "float.min_exp"],
	["FLT_MIN", "float.min"],
	["LDBL_DIG", "real.dig"],
	["LDBL_EPSILON", "real.epsilon"],
	["LDBL_MANT_DIG", "real.mant_dig"],
	["LDBL_MAX_10_EXP", "real.max_10_exp"],
	["LDBL_MAX_EXP", "real.max_exp"],
	["LDBL_MAX", "real.max"],
	["LDBL_MIN_10_EXP", "real.min_10_exp"],
	["LDBL_MIN_EXP", "real.min_exp"],
	["LDBL_MIN", "real.min"],
	//["FLT_EVAL_METHOD", ""],
	//["FLT_ROUNDS", ""],
	//["FLT_RADIX", ""],
	//["DECIMAL_DIG", ""],
];

package string mapLookup(const string[2][] map, string str, string orElse) {
	// #optimization: binary serach?
	foreach(p; map) {
		if (str == p[0]) {
			return p[1];
		}
	}
	return orElse;
}

/// Params:
///   str = macro from <float.h>
/// Returns: corresponding D type property, or `null` if no match
string ctodLimit(string str) {
	return mapLookup(limitMap, str, str);
}

@("ctodLimit") unittest {
	assert(ctodLimit("FLT_MAX") == "float.max");
}

/// Translate C number literal to D one
///
string ctodNumberLiteral(string str, ref CType type) {

	string typeName = "int";
	if (str.length < 2) {
		type = CType.named("int");
		return str;
	}

	// float must have digits after dot, 1.f => 1.0f
	if ((str[$-1] == 'f' || str[$-1] == 'F')) {
		if (str[$-2] == '.') {
			auto res = new char[str.length+1];
			res[0..str.length] = str[];
			res[$-2] = '0';
			res[$-1] = str[$-1];
			type = CType.named("float");
			return (() @trusted => cast(immutable) res)();
		}
		type = CType.named("float");
		return str;
	}

	// TODO:
	/// long specifier must be capitalized in D, 1llu => 1LLu
	char[] cap = null;
	int longCount = 0;
	bool unsigned = false;
	foreach_reverse(i; 0..str.length) {
		if (str[i] == 'l') {
			if (!cap) {
				cap = str.dup;
			}
			cap[i] = 'L';
			longCount++;
		}
		if (str[i] == 'L') {
			longCount++;
		}
		if (str[i] == 'u' || str[i] == 'U') {
			unsigned = true;
			// unsigned
		}
	}
	if (longCount > 1) {
		typeName = "long";
	}
	if (unsigned) {
		typeName = "u" ~ typeName;
	}
	type = CType.named(typeName);

	if (cap) {
		return (() @trusted => cast(immutable) cap)();
	}
	return str;
}

@("ctodNumberLiteral") unittest {
	CType type;
	assert(ctodNumberLiteral("0", type) == "0");
	assert(type == CType.named("int"));
	assert(ctodNumberLiteral("1.f", type) == "1.0f");
	assert(type == CType.named("float"));
	assert(ctodNumberLiteral("1.F", type) == "1.0F");
	assert(type == CType.named("float"));
	assert(ctodNumberLiteral("4l", type) == "4L");
	assert(type == CType.named("int"));

	assert(ctodNumberLiteral("1llu", type) != "1Lu");
	assert(type == CType.named("ulong"));
}
