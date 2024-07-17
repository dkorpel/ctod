module ctod.translate;

nothrow @safe:

import ctod.tree_sitter;
import ctod.ctype;
import ctod.cdeclaration;
import ctod.cexpr;
import ctod.cpreproc;
import ctod.util;

import tree_sitter.api;

private immutable hasVersion = `
private template HasVersion(string versionId) {
	mixin("version("~versionId~") {enum HasVersion = true;} else {enum HasVersion = false;}");
}
`;

/// Returns: C language parser for tree-sitter
extern (C) void* tree_sitter_c();

/// Returns: tree-sitter C parser
private TSParser* getCParser() @trusted
{
	TSParser* parser = ts_parser_new();
	TSLanguage* language = cast(TSLanguage*) tree_sitter_c();
	const success = ts_parser_set_language(parser, language);
	assert(success);
	return parser;
}

package void headerString(ref OutBuffer result, string moduleName)
{
	if (moduleName.length > 0)
	{
		result ~= "module ";
		result ~= moduleName;
		result ~= ";\n";
	}
	result ~= "@nogc nothrow:\n" ~ "extern(C): __gshared:\n";
}

/// Params:
///   source = C source code
///   moduleName = name for the `module` declaration on the D side
/// Returns: `source` translated from C to D
string translateFile(string source, string moduleName)
{
	auto parser = getCParser();
	// scope(exit) ts_parser_delete(parser);
	// ts_tree_delete(tree);

	source = filterCppBlocks(source);

	auto ctx = CtodCtx(source, parser);
	Node* root = parseCtree(ctx.parser, source);
	assert(root);

	findFuncDecls(ctx, *root);
	translateNode(ctx, *root);

	OutBuffer result;
	headerString(result, moduleName);

	if (ctx.needsHasVersion)
		result ~= hasVersion;

	if (ctx.needsClong)
		result ~= "import core.stdc.config: c_long, c_ulong;\n";

	if (ctx.needsWchar)
		result ~= "import core.stdc.stddef: wchar_t;\n";

	if (ctx.needsInt128)
		result ~= "import core.int128;\n";

	if (ctx.needsCbool)
		result ~= "alias c_bool = int;\n";

	// white space leading up to the first AST element is not included in the AST, so add it
	result ~= source[0 .. root.start];
	result ~= root.output();
	return result.extractOutBuffer();
}

/// What the C macro is for
enum MacroType
{
	none, // und
	manifestConstant, // #define three 3
	inlineFunc, // #define SQR(x) (x*x)
	versionId, // #ifdef _WIN32_
	emptyFunc, // #define F(x)
	staticIf,
}

/// Variables for a `struct` / `union` / `enum` declaration
struct TypeScope
{
	Sym sym; // Sym.union_specifier, Sym.struct_specifier, Sym.enum_specifier
	int fieldIndex = 0; // counts up every declaration
}

/// Translation context, all 'global' state
package
struct CtodCtx
{
	/// input C  source code
	string source;
	/// C parser
	TSParser* parser;
	/// HasVersion(string) template is needed
	bool needsHasVersion = false;
	/// needs c_long types (long has no consistent .sizeof, 4 on 64-bit Windows, 8 on 64-bit Linux)
	bool needsClong = false;
	/// needs wchar_t type (wchar on Windows, dchar on Linux)
	bool needsWchar = false;
	/// needs `alias c_bool = int;`
	bool needsCbool = false;
	/// needs `Cent` type
	bool needsInt128 = false;

	/// global variables and function declarations
	Map!(string, Decl) symbolTable;
	/// for function local variables
	Map!(string, Decl) localSymbolTable;
	/// Table of all #define macros
	Map!(string, MacroType) macroTable;
	/// Set of macro func names, #define S(x, y) ... => [x: true, y: true]
	Map!(string, bool) macroFuncParams;
	/// Type of expression nodes
	Map!(ulong, CType) nodeTypes;
	/// Keeps track of all global functions with a body
	Map!(string, bool) functionDefinitions;

	/// collect structs, unions and enums definitions that were defined in expressions
	InlineType[] inlineTypes;
	/// name of the function we're currently in
	string inFunction = null;
	/// type of the declaration we're currently in
	CType inDeclType = CType.none;
	/// If we're in a parameter list (function types can be nested, the int is the nest level)
	int inParameterList = 0;
	/// stack of "struct" "enum" "union"
	private TypeScope[] typeScope = null;

nothrow:

	this(string source, TSParser* parser)
	{
		this.source = source;
		this.parser = parser;
		this.typeScope = [TypeScope(Sym.null_)];
	}

	void enterFunction(string functionName)
	{
		this.inFunction = functionName;
	}

	void leaveFunction() @trusted
	{
		this.inFunction = null;
		this.localSymbolTable.clear();
	}

	bool inMacroFunction()
	{
		return this.macroFuncParams.length > 0;
	}

	void pushTypeScope(Sym sym)
	{
		this.typeScope ~= TypeScope(sym);
	}

	void popTypeScope()
	{
		this.typeScope.length--;
	}

	/// Gives info what struct / union we're in
	ref TypeScope currentTypeScope() => this.typeScope[$ - 1];

	bool inUnion()
	{
		return currentTypeScope.sym == Sym.union_specifier;
	}

	CType expType(ref Node node)
	{
		if (auto type = node.id in nodeTypes)
		{
			return *type;
		}
		return CType.none;
	}

	void setExpType(ref Node node, CType type)
	{
		nodeTypes[node.id] = type;
	}

	Decl lookupDecl(string id)
	{
		if (auto local = id in localSymbolTable)
		{
			return *local;
		}
		else if (auto global = id in symbolTable)
		{
			return *global;
		}
		else
		{
			return Decl.none;
		}
	}

	void registerDecl(Decl decl)
	{
		if (decl.identifier)
		{
			if (inFunction)
			{
				localSymbolTable[decl.identifier] = decl;
			}
			else
			{
				symbolTable[decl.identifier] = decl;
			}
		}
		currentTypeScope.fieldIndex++;
	}

	string uniqueIdentifier(string suggestion)
	{
		static char toUpper(char c) => cast(char)(c - (c >= 'a' && c <= 'z') * ('a' - 'A'));
		if (suggestion.length > 0)
		{
			return "_" ~ toUpper(suggestion[0]) ~ suggestion[1 .. $];
		}
		else
		{
			assert(0);
		}
	}
}

void translateNode(ref CtodCtx ctx, ref Node node)
{
	if (node.isTranslated)
		return;
	scope (exit)
		node.isTranslated = true;

	if (ctodTryPreprocessor(ctx, node))
		return;

	if (ctodTryInitializer(ctx, node))
		return;

	if (ctodTryDeclaration(ctx, node))
		return;

	if (ctodTryTypedef(ctx, node))
		return;

	if (ctodExpression(ctx, node))
		return;

	if (ctodTryStatement(ctx, node))
		return;

	if (ctodMisc(ctx, node))
		return;

	foreach (ref c; node.children)
	{
		translateNode(ctx, c);
	}
}

/// Start looking for function definitions so redundant extern function declarations can be removed
/// during translation. (C requires forward function declarations, D doesn't)
void findFuncDecls(ref CtodCtx ctx, ref Node node)
{
	if (node.sym == Sym.function_definition)
	{
		if (auto declNode = node.childField(Field.declarator))
		{
			if (auto idNode = declNode.childField(Field.declarator))
				ctx.functionDefinitions[idNode.source] = true;
		}
	}
	else
	{
		foreach (ref c; node.children)
		{
			findFuncDecls(ctx, c);
		}
	}
}

/// Returns: whether the body of a switch statement `node` contains a default statement
bool hasDefaultStatement(ref Node node)
{
	foreach (ref c; node.children)
	{
		if (c.sym == Sym.anon_default)
		{
			return true;
		}
		if (c.sym == Sym.switch_statement)
		{
			// any default statement we find in here doesn't belong to the original switch anymore
			continue;
		}
		if (hasDefaultStatement(c))
		{
			return true;
		}
	}
	return false;
}

package bool ctodTryStatement(ref CtodCtx ctx, ref Node node)
{
	switch (node.sym)
	{
	case Sym.if_statement:
	case Sym.while_statement:
	case Sym.for_statement:
		// Assignment may not be used in if / loop conditions in D
		// if (x = 3)    => if ((x = 3) != 0)
		// if (!(x = 3)) => if ((x = 3) == 0)
		if (auto a = node.childField(Field.condition))
		{
			if (a.sym == Sym.parenthesized_expression)
			{
				a = getParenContent(a);
			}
			if (a.sym == Sym.assignment_expression)
			{
				a.prepend("(");
				a.append(") != 0");
			}
		}
		if (auto initializer = node.childField(Field.initializer))
		{
			if (auto decls = ctodTryDeclaration(ctx, *initializer))
			{
				// If there are multiple declarations with different types, need to wrap in {}
				CType prevType = CType.none;
				foreach (decl; decls)
				{
					if (!prevType)
					{
						prevType = decl.type;
					}
					else if (decl.type != prevType)
					{
						initializer.prepend("{");
						initializer.append("}");
						break;
					}
				}
			}
		}
		break;
	case Sym.switch_statement:
		// D mandates `default` case in `switch`
		// note: switch statements can have `case` statements in the weirdest places
		// we can be a bit conservative here and only check the common switch pattern
		if (auto bodyNode = node.childField(Field.body_))
		{
			if (bodyNode.sym != Sym.compound_statement)
				break;

			if (hasDefaultStatement(*bodyNode))
			{
				break;
			}

			bodyNode.children[$ - 1].prepend("default: break;");
		}
		break;
	default:
		break;
	}
	return false;
}

package bool ctodMisc(ref CtodCtx ctx, ref Node node)
{
	switch (node.sym)
	{
	case Sym.primitive_type:
		if (string s = ctodPrimitiveType(node.source))
		{
			node.replace(s);
		}
		return true;
	case Sym.anon_DASH_GT:
		return node.replace("."); // s->field => s.field
	case Sym.expression_statement:
		// ; as empty statement not allowed in D, for (;;); => for (;;) {}
		if (node.source == ";")
		{
			return node.replace("{}");
		}
		break;
	case Sym.struct_specifier:
	case Sym.union_specifier:
	case Sym.enum_specifier:
		if (auto bodyNode = node.childField(Field.body_))
		{
			// This comes up in sizeof(unsigned short), or possibly a macro if tree-sitter can parse it
			// TODO: better inlineTypes handling, in case of sizeof(struct {int x; int y;})
			InlineType[] inlineTypes;
			if (auto s = parseTypeNode(ctx, node, inlineTypes, /*keepOpaque*/ true))
			{
				// #twab: it was translating global struct definitions as inline types
				if (inlineTypes.length > 0)
				{
					if (auto n = inlineTypes[0].node)
					{
						node.append(enumMemberAliases(s, *n));
					}
				}
			}
		}
		else
		{
			// Trailing ; are children of the translation unit, and they are removed
			// However, opaque structs/unions still need them
			node.append(";");
		}
		break;
	case Sym.translation_unit:
		removeSemicolons(node);
		break;
	default:
		break;
	}
	return false;
}

/// In C there are trailing ; after union and struct definitions.
/// We don't want them in D
/// This should be called on a translation_unit, preproc_if, or preproc_ifdef node
package void removeSemicolons(ref Node node)
{
	foreach (ref c; node.children)
	{
		if (c.sym == Sym.anon_SEMI)
		{
			c.replace("");
		}
	}
}

package string mapLookup(const string[2][] map, string str, string orElse)
{
	// #optimization: use binary search
	foreach (p; map)
	{
		if (str == p[0])
		{
			return p[1];
		}
	}
	return orElse;
}

package string mapLookup(const string[] map, string str, string orElse)
{
	// #optimization: use binary search
	foreach (p; map)
	{
		if (str == p)
		{
			return p;
		}
	}
	return orElse;
}

/// Translate C number literal to D one
/// Params:
///   str = number literal
///   type = gets set to number type of the literal
string ctodNumberLiteral(string str, ref CType type)
{

	string typeName = "int";
	if (str.length < 2)
	{
		type = CType.named("int");
		return str;
	}

	// float must have digits after dot, 1.f => 1.0f
	if (str[$ - 1] == 'f' || str[$ - 1] == 'F')
	{
		if (str[$ - 2] == '.')
		{
			auto res = new char[str.length + 1];
			res[0 .. str.length] = str[];
			res[$ - 2] = '0';
			res[$ - 1] = str[$ - 1];
			type = CType.named("float");
			return (() @trusted => cast(immutable) res)();
		}
		type = CType.named("float");
		return str;
	}

	char[] cap = null;
	int longCount = 0;
	bool unsigned = false;
	foreach_reverse (i; 0 .. str.length)
	{
		if (str[i] == 'l')
		{
			if (!cap)
			{
				cap = str.dup;
			}
			cap[i] = 'L';
			longCount++;
		}
		if (str[i] == 'L')
		{
			longCount++;
		}
		if (str[i] == 'u' || str[i] == 'U')
		{
			unsigned = true;
		}
	}
	if (longCount > 1)
	{
		typeName = "long";
	}
	if (unsigned)
	{
		typeName = "u" ~ typeName;
	}
	type = CType.named(typeName);

	if (cap)
	{
		return (() @trusted => cast(immutable) cap)();
	}
	return str;
}

@"ctodNumberLiteral" unittest
{
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
