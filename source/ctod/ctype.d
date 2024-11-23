/**
Translate C types
*/
module ctod.ctype;

nothrow @safe:

import ctod.tree_sitter;
import ctod.translate;
import ctod.cdeclaration;
import ctod.cexpr;
import ctod.util;

/// Declaration
struct Decl
{
	CQuals quals; /// qualifiers / storage classes
	CType type = CType.none;
	string identifier = ""; /// name of variable / function
	string initializerD = ""; /// expression that initializes the variable

pure nothrow:

	void toD(ref OutBuffer sink) const
	{
		quals.toD(sink);
		// D declarations are usually separated as [type] followed by [identifier], but there is one exception:
		// extern functions. (functions with bodies are handled separately, and function pointers have the name on the right
		if (type.tag == CType.Tag.funcDecl)
		{
			funcTypeToD(sink, type.next[0], identifier, type.params);
		}
		else
		{
			type.toD(sink);
			if (identifier.length > 0)
			{
				sink ~= " ";
				sink ~= identifier;
			}
			sink ~= initializerD;
		}
	}

	///
	enum none = Decl.init;
	///
	bool opCast(T : bool)() const => cast(bool) type;
}

/// Generate D function type syntax
private void funcTypeToD(ref OutBuffer sink, const CType retType, string name, const Decl[] params) pure
{
	retType.toD(sink);
	sink ~= " ";
	sink ~= name;
	sink ~= "(";
	foreach (i, par; params)
	{
		if (i > 0)
			sink ~= ", ";

		par.toD(sink);
	}
	sink ~= ")";
}

/// A type in the middle of an expression.
/// C allows to e.g. define a struct inside a parameter list.
struct InlineType
{
	string keyword;
	string name = null;
	string body_;
	Node node; // body node

pure nothrow:

	bool hasBody() const => body_.length > 0;

	void toD(ref OutBuffer sink) const
	{
		sink ~= keyword;
		sink ~= " ";
		sink ~= name;
		if (this.hasBody)
		{
			sink ~= " ";
			sink ~= body_;
		}
		else
		{
			sink ~= ";";
		}
	}
}

/// Generate alias declarations to put enum members into the global namespace
/// C enums don't have a scope for their members
string enumMemberAliases(string enumName, ref Node c)
{
	if (c.sym != Sym.enumerator_list)
	{
		return null;
	}
	string res = "\n";
	foreach (ref c2; c.children)
	{
		if (c2.sym == Sym.enumerator)
		{
			string mem = c2.childField(Field.name).sourceC;
			res ~= "alias " ~ mem ~ " = " ~ enumName ~ "." ~ mem ~ ";\n";
		}
	}
	return res;
}

private string typeSymToKeyword(Sym sym)
{
	switch (sym)
	{
	case Sym.struct_specifier:
		return "struct";
	case Sym.union_specifier:
		return "union";
	case Sym.enum_specifier:
		return "enum";
	default:
		return null;
	}
}

/// C declarations are declared this way:
/// First, a 'base type' which is a primitive type or identifier
/// Then, one or more expressions that should evaluate to a value of 'base type'
///
/// Note: the base-type can be an (anonymous) struct / union / enum, which is not allowed in D.
/// These are stored in `inlineTypes`, and the caller should emit these
///
/// Returns: primitive type
string parseTypeNode(ref scope CtodCtx ctx, ref Node node, scope ref InlineType[] inlineTypes, bool keepOpaque)
{

	// keyword = struct, union or enum
	string namedType(Sym sym)
	{
		auto nameNode = node.childField(Field.name);
		if (auto c = node.childField(Field.body_))
		{
			ctx.pushTypeScope(sym);
			translateNode(ctx, c);
			ctx.popTypeScope();
			string name = nameNode ? nameNode.sourceC : null;
			inlineTypes ~= InlineType(typeSymToKeyword(sym), name, c.translation(), c);
			return name;
		}
		else if (nameNode)
		{
			if (keepOpaque)
			{
				return null;
			}
			// Don't emit bodyless types, assume they were defined before
			// inlineTypes ~= InlineType(keyword, nameNode.sourceC, /*body*/ "");
			return nameNode.sourceC;
		}
		return null;
	}

	switch (node.sym)
	{
	case Sym.type_descriptor:
		if (auto c = node.childField(Field.type))
		{
			return parseTypeNode(ctx, c, inlineTypes, keepOpaque);
		}
		break;
	case Sym.primitive_type:
		return ctodPrimitiveType(node.sourceC);
	case Sym.alias_type_identifier:
		if (node.sourceC == "wchar_t")
		{
			ctx.needsWchar = true;
			return node.sourceC;
		}
		if (node.sourceC == "bool")
		{
			ctx.needsCbool = true;
			return "c_bool";
		}
		if (node.sourceC == "__int128_t")
		{
			ctx.needsInt128 = true;
			return "Cent";
		}
		if (node.sourceC == "__uint128_t")
		{
			ctx.needsInt128 = true;
			return "Cent";
		}
		// int8_t is recognized as a primitive type, but __u8 is a type identifier,
		// so also do ctodPrimitiveType here.
		const replacement = ctodPrimitiveType(node.sourceC);
		if (replacement == node.sourceC)
		{
			// no replacement to a D-type, so escape keywords (out => out_)
			return translateIdentifier(node.sourceC);
		}
		// replacement to a D-type , e.g. __u8 => ubyte, no escaping
		return replacement;
	case Sym.sized_type_specifier:
		return ctodSizedTypeSpecifier(ctx, node);
	case Sym.struct_specifier:
	case Sym.union_specifier:
	case Sym.enum_specifier:
		return namedType(node.sym);
	default:
		break;
	}
	return null;
}

/// Translate built-in integral types (int, long, short, char, etc.)
string ctodSizedTypeSpecifier(ref scope CtodCtx ctx, ref Node node)
{
	bool signed = true;
	int longCount = 0;
	string primitive = "";
	foreach (ref c; node.children)
	{
		switch (c.sym)
		{
		case Sym.comment:
			continue;
		case Sym.anon_unsigned:
			signed = false;
			break;
		case Sym.anon_long:
			longCount++;
			break;
		case Sym.primitive_type:
			primitive = ctodPrimitiveType(c.sourceC);
			break;
		case Sym.anon_short: // not a primitive_type apparently, but similar to `unsigned`
			primitive = "short";
			break;
		default:
			break;
		}
	}

	if (longCount > 0 && primitive == "double")
	{
		primitive = "real";
	}
	else if (longCount == 1)
	{
		primitive = "c_long";
		ctx.needsClong = true;
	}
	else if (longCount == 2)
	{
		primitive = "long";
	}
	else if (!signed && primitive == "")
	{
		primitive = "int";
	}

	if (!signed && primitive.length > 0 && primitive[0] != 'u')
	{
		if (primitive == "char")
		{
			primitive = "ubyte";
		}
		else if (primitive == "c_long")
		{
			primitive = "c_ulong";
		}
		else
		{
			primitive = "u" ~ primitive;
		}
	}
	return primitive;
}

/// Qualifiers for a C declaration
struct CQuals
{
	bool const_;
	bool volatile_;
	bool restrict;
	bool atomic;

	bool staticFunc; /// static at function scope (meaning the variable is global)
	bool staticGlobal; /// static at global scope (meaning the symbol is private)
	bool extern_;
	bool auto_;
	bool inline;
	bool register;

	enum none = typeof(this).init;

pure nothrow:

	void toD(ref OutBuffer sink) const
	{
		if (inline)
			sink ~= "pragma(inline, true) ";
		if (extern_)
			sink ~= "extern ";
		// C's static meaning 'private to the translation unit' doesn't exist in D
		// The closest thing is `private extern(D)` which restricts access and
		// avoids name conflicts, but still emits a symbol
		// However, we don't do `extern(D)` since that changes abi as well
		if (staticGlobal)
			sink ~= "private ";
		if (staticFunc)
			sink ~= "static ";
		// Also: static can also mean 'array of length at least X'

		// const_ is ignored
		//    sink ~= "const ";
		// D has transitive const unlike C
		// it must surround the primitive type, e.g. `const int*` => `const(int)*`

		if (auto_)
			sink ~= "auto ";
		if (volatile_)
			sink ~= "/*volatile*/ ";
		if (restrict)
			sink ~= "/*restrict*/ ";
		if (atomic)
			sink ~= "/*atomic*/ ";
	}
}

/// Look for type qualifiers in this node, set the corresponding booleans
/// Unknown qualifiers are ignored, though the function is supposed to catch all of them.
/// Returns: `true` on success
bool tryParseTypeQual(ref scope CtodCtx ctx, ref Node node, ref CQuals quals)
{
	if (node.sym == Sym.type_qualifier || node.sym == Sym.storage_class_specifier)
	{
		switch (node.children.front.sym)
		{
		case Sym.anon_const:
			quals.const_ = true;
			return true;
		case Sym.anon_volatile:
			quals.volatile_ = true;
			return true;
		case Sym.anon_restrict:
			quals.restrict = true;
			return true;
		case Sym.anon__Atomic:
			quals.atomic = true;
			return true;
		case Sym.anon_extern:
			quals.extern_ = true;
			return true;
		case Sym.anon_static:
			if (ctx.inFunction)
			{
				quals.staticFunc = true;
			}
			else
			{
				quals.staticGlobal = true;
			}
			return true;
		case Sym.anon_auto:
			quals.auto_ = true;
			return true;
		case Sym.anon_register:
			quals.register = true;
			return true;
		case Sym.anon_inline:
			quals.inline = true;
			return true;
		default:
			break;
		}
	}
	return false;
}

/// Parse declarations
/// Often a node represents a single declaration, but in case of e.g. `int x, *y;` they are split up into two
/// declarations since in D you can't declare differently typed variables in one declaration
Decl[] parseDecls(ref scope CtodCtx ctx, ref Node node, scope ref InlineType[] inlineTypes, scope string* apiMacro = null)
{
	auto typeNode = node.childField(Field.type);
	if (!typeNode)
		return null;

	const oldLen = inlineTypes.length;
	auto primitiveType = parseTypeNode(ctx, typeNode, inlineTypes, false);

	// This happens with API macros, which get parsed as a return type.
	if (apiMacro && node.children.length > 1 && node.children[1].sym == Sym.error)
	{
		*apiMacro = primitiveType;
		primitiveType = node.children[1].sourceC;
	}

	// there may be multiple type_qualifier fields
	// if (auto qualNode = node.childField(Field.type_qualifier))
	CQuals quals;
	foreach (ref c; node.children)
	{
		cast(void) tryParseTypeQual(ctx, c, quals);
	}
	CType baseType = CType.named(primitiveType);
	baseType.isConst = quals.const_;
	Decl[] result;
	foreach (ref c; node.children)
	{
		if (c == typeNode)
		{
			// the type field may pass as a declarator, resulting in e.g.
			// T* t; => T T; T* t;
			continue;
		}
		Decl decl = Decl(quals, baseType, "", "");
		if (parseCtype(ctx, c, decl, inlineTypes))
		{
			if (primitiveType.length == 0 && inlineTypes.length > oldLen && inlineTypes[$ - 1].name.length == 0)
			{
				inlineTypes[$ - 1].name = ctx.uniqueIdentifier(decl.identifier);
				decl.type.setName(inlineTypes[$ - 1].name);
			}
			if (decl.type.isCArray() && ctx.inParameterList)
			{
				// C array parameters decay into pointers
				decl.type = CType.pointer(decl.type.next[0]);
			}
			if (decl.type.isStaticArray() && ctx.inParameterList)
			{
				// static arrays in parameter lists are passed by reference
				decl.type.tag = CType.Tag.staticArrayParam;
			}
			result ~= decl;
		}
	}

	// parameters can have no identifier, e.g. `foo(int named, float)`
	// if this is called for a parameter declaration, you still want to get an anonymous declaration back
	// the only exception is empty parameter lists, which in C are declared like `void main(void)`
	if (result.length == 0 && primitiveType != "void")
	{
		result = [Decl(quals, baseType, "", "")];
	}
	return result;
}

/// Returns: number of elements in initializer_list
uint initializerLength(ref Node node, ref string firstElement)
{
	firstElement = null;
	uint commaCount = 0;
	foreach (ref e; node.children)
	{
		if (e.sym == Sym.comment || e.sym == Sym.anon_LBRACE || e.sym == Sym.anon_RBRACE)
			continue;

		if (e.sym == Sym.anon_COMMA)
			commaCount++;

		if (!firstElement)
			firstElement = e.sourceC;
	}
	return commaCount + (firstElement != null); // == 0 && firstElement == "0";
}

/// Simple int to string function to avoid `std.conv: text`, which is not yet available for WebAssembly
private string intToString(uint i)
{
	if (i < 10)
	{
		return [cast(char)('0' + i)];
	}
	else
	{
		return intToString(i / 10) ~ intToString(i % 10);
	}
}

unittest
{
	assert(intToString(0) == "0");
	assert(intToString(9) == "9");
	assert(intToString(4790) == "4790");
}

/// From a decl, parse the type and identifier
/// identifier: gets set to identifier of decl
/// Returns: whether a type was found and parsed in `node`
bool parseCtype(ref scope CtodCtx ctx, ref Node node, ref Decl decl, scope ref InlineType[] inlineTypes)
{
	switch (node.sym)
	{
	case Sym.init_declarator:
		if (auto declaratorNode = node.childField(Field.declarator))
		{
			decl.initializerD = "TMP";
			parseCtype(ctx, declaratorNode, decl, inlineTypes);
		}
		if (auto valueNode = node.childField(Field.value))
		{
			ctx.inDeclType = decl.type;
			translateNode(ctx, valueNode);
			ctx.inDeclType = CType.none;
			convertPointerTypes(ctx, decl.type, valueNode);
			if (valueNode.sym == Sym.initializer_list)
			{
				string firstElem;
				const len = initializerLength(valueNode, firstElem);
				// int x[4] = {0} => int[4] x = 0
				// Important because in function scope, all elements must be in [] initializer
				if (decl.type.isStaticArray())
				{
					if ((len == 1 && firstElem == "0") || len == 0)
					{
						valueNode.replace("0");
					}
				}
				// int x[] = {10, 20, 30} => int[3] x = [10, 20 30]
				// transform into static array with length inferred from initializer
				// Note: shouldn't be done in struct scope, but initializers are not valid in C there
				if (decl.type.isCArray())
				{
					decl.type = CType.array(decl.type.next[0], intToString(len));
				}
			}
			const stringSize = stringInitializerSize(valueNode);
			if (decl.type.isCArray() && stringSize >= 0)
			{
				decl.type = CType.array(decl.type.next[0], intToString(stringSize));
			}
			decl.initializerD = " = "  ~ valueNode.translation();
		}
		return true;
	case Sym.parenthesized_declarator:
		// (*(x));
		auto pc = getParenContent(node);
		return parseCtype(ctx, pc, decl, inlineTypes);
	case Sym.abstract_function_declarator:
	case Sym.function_declarator:
		Decl[] paramDecls = [];
		if (auto paramNode = node.childField(Field.parameters))
		{
			ctx.inParameterList++;
			foreach (ref c; paramNode.children)
			{
				if (c.sym == Sym.parameter_declaration)
				{
					auto d = parseDecls(ctx, c, inlineTypes);
					paramDecls ~= d;
				}
				else if (c.sym == Sym.variadic_parameter)
				{
					// variadic args
					paramDecls ~= Decl(CQuals.none, CType.named("..."), "", "");
				}
			}
			ctx.inParameterList--;
		}
		if (auto declNode = node.childField(Field.declarator))
		{
			decl.type = CType.funcDecl(decl.type, paramDecls);
			if (node.sym == Sym.abstract_function_declarator)
			{
				decl.type = CType.pointer(decl.type);
			}
			parseCtype(ctx, declNode, decl, inlineTypes);
		}
		return true;
	case Sym.alias_field_identifier: // int x;
	case Sym.alias_type_identifier: // typedef X Y;
	case Sym.identifier: // ??
		decl.identifier = translateIdentifier(node.sourceC);
		return true;
		// pointer/array declarators always have a declarator field.
		// abstract declarators maybe not, for example: void foo(float*, float[])
		// however, nested pointers/array (`float[][]` or `float**`) do have it until you reach the 'leaf'
	case Sym.pointer_declarator:
	case Sym.abstract_pointer_declarator:
		decl.type = CType.pointer(decl.type);
		if (auto c = node.firstChildType(Sym.type_qualifier))
		{
			if (c.sourceC == "const" && decl.type.next[0].isConst)
			{
				decl.type.isConst = true;
				decl.type.next[0].isConst = false; // D has transitive const, so no need for `const(const(int)*)`
			}
		}
		if (auto c = node.childField(Field.declarator))
		{
			parseCtype(ctx, c, decl, inlineTypes);
		}
		return true;
	case Sym.array_declarator:
	case Sym.abstract_array_declarator:
		// static array
		if (auto sizeNode = node.childField(Field.size))
		{
			translateNode(ctx, sizeNode);
			decl.type = CType.array(decl.type, sizeNode.translation());
			if (auto c1 = node.childField(Field.declarator))
			{
				parseCtype(ctx, c1, decl, inlineTypes);
			}
		}
		else
		{
			// unsized array, might become a static array at global scope `int x[] = {3, 4, 5}`
			if (auto c1 = node.childField(Field.declarator))
			{
				if (ctx.inParameterList || decl.initializerD.length > 0)
				{
					decl.type = CType.cArray(decl.type);
				}
				else
				{
					// C arrays without initializer are uncommon (raise a warning),
					// but defaults to 1 element
					decl.type = CType.array(decl.type, "1");
				}
				parseCtype(ctx, c1, decl, inlineTypes);
			}
		}
		return true;
	default:
		break;
	}
	return false;
}

/// Returns: sizeof string initializer, including zero terminator, or -1 if not a string initializer
int stringInitializerSize(ref Node node)
{
	if (node.sym == Sym.concatenated_string)
	{
		int stringSize = 0;
		foreach (ref c; node.children)
		{
			if (c.sym == Sym.string_literal)
			{
				const s = stringLiteralSize(c.sourceC);
				if (s < 0)
					return -1;

				stringSize += s;
			}
		}
		return stringSize + 1;
	}
	else if (node.sym == Sym.string_literal)
	{
		const s = stringLiteralSize(node.sourceC);
		if (s < 0)
			return -1;

		return s + 1;
	}
	else
	{
		return -1;
	}
}

/// Returns: sizeof a string literal, or -1 on error
///
/// Needed for initializing static char arrays.
/// Size excludes zero terminator, because concatenated string literals have only one of them
int stringLiteralSize(string s)
{
	int result = cast(int) s.length - 2; // -2 for quotes
	size_t p = 0;
	while (p + 1 < s.length)
	{
		// escape sequences usually take 2 bytes but only produce 1
		// exceptions are: \x32 \u0123 \U01234567
		if (s[p] == '\\')
		{
			p++;
			result -= 1;
			// TODO: \x can have more than 2 digits, and \u and \U can produce more than 1 code unit,
			// so these amounts are not right
			switch (s[p])
			{
			case 'x':
				result -= 2; // \xhh
				break;
			case 'u':
				result -= 4; // \uhhhh
				result += 1; // guess that the code point is 2 code unit
				break;
			case 'U':
				result -= 8; // \Uhhhhhhhh
				result += 3; // guess that the code point is 4 code units
				break;
			default:
				// \n \r \t etc.
				break;
			}
		}
		p++;
	}
	if (result < 0)
		return -1; // malformed string literal

	return cast(uint) result;
}

unittest
{
	assert(stringLiteralSize(`"abc"`) == 3);
	assert(stringLiteralSize(`"\x22\n"`) == 2);
	assert(stringLiteralSize(`"\U"`) == -1); // malformed
	assert(stringLiteralSize(``) == -1); // malformed
}

package
struct CType
{
	enum Tag
	{
		none,
		unknown,
		pointer,
		staticArray,
		staticArrayParam, // passed by ref
		cArray,
		funcDecl,
		named,
	}
	/// For a pointer / array, the element type.
	/// For a function, the return type.
	/// Always has length 1.
	CType[] next;
	Decl[] params; // parameter declarations
	string name; // name of decl for parameters

	alias countExpr = name; // for static arrays. Note: need not be a number literal
	// not a union with `name` because that makes access `@system`

	Tag tag = Tag.none;
	bool isConst = false;

	enum none = CType.init;
	enum unknown = CType(tag: Tag.unknown);

pure nothrow:

	/// Returns: type of string literal
	static CType stringLiteral()
	{
		auto cc = CType.named("char");
		cc.isConst = true;
		auto result = CType.pointer(cc);
		return result;
	}

	bool opCast(T : bool)() const scope => tag != Tag.none;
	bool isFunction() const scope => tag == Tag.funcDecl;
	bool isStaticArray() const scope => tag == Tag.staticArray;
	bool isCArray() const scope => tag == Tag.cArray;
	bool isPointer() const scope => tag == Tag.pointer;

	bool opEquals(const CType other) const scope
	{
		if (other.tag != this.tag)
			return false;

		if (other.isConst != this.isConst)
			return false;

		final switch (tag)
		{
		case Tag.cArray:
		case Tag.pointer:
			return this.next[0] == other.next[0];
		case Tag.staticArray:
		case Tag.staticArrayParam:
			return this.countExpr == other.countExpr && this.next[0] == other.next[0];
		case Tag.funcDecl:
			return this.next[0] == other.next[0] && this.params == other.params;
		case Tag.named:
			return other.name == this.name;
		case Tag.unknown:
		case Tag.none:
			return true;
		}
	}

	// replace the eventual name of this type
	// used for giving anonymous structs/unions/enums a name afterwards, based on variable names
	void setName(string name) scope
	{
		if (tag == Tag.named)
		{
			this.name = name;
		}
		else if (next.length > 0)
		{
			next[0].setName(name);
		}
		else
		{

		}
	}

	static CType pointer(CType to)
	{
		CType result;
		result.next = [to];
		result.tag = Tag.pointer;
		return result;
	}

	static CType cArray(CType to)
	{
		CType result;
		result.next = [to];
		result.tag = Tag.cArray;
		return result;
	}

	static CType array(CType elem, string count)
	{
		CType result;
		result.next = [elem];
		result.countExpr = count;
		result.tag = Tag.staticArray;
		return result;
	}

	static CType named(string name)
	{
		CType result;
		result.name = name;
		result.tag = Tag.named;
		return result;
	}

	static CType funcDecl(CType ret, Decl[] params)
	{
		CType result;
		result.next = [ret];
		result.params = params;
		result.tag = Tag.funcDecl;
		return result;
	}

	void toD(ref OutBuffer sink) const scope
	{
		final switch (tag)
		{
		case Tag.cArray:
			next[0].toD(sink);
			sink ~= "[$]";
			break;
		case Tag.staticArrayParam:
			// Possible to translate as `ref` parameter, but we also translate passing `sa` to `sa.ptr`
			// So translating as pointer makes this more consistent
			// sink ~= "ref "
			goto case;
		case Tag.pointer:
			if (next[0].isFunction)
			{
				funcTypeToD(sink, next[0].next[0], "function", next[0].params);
			}
			else if (isConst)
			{
				//format(isConst ? "const(%s*)" : "%s*", next[0]);
				sink ~= "const(";
				next[0].toD(sink);
				sink ~= "*)";
			}
			else
			{
				next[0].toD(sink);
				sink ~= "*";
			}
			break;
		case Tag.staticArray:
			next[0].toD(sink);
			sink ~= "[";
			sink ~= countExpr;
			sink ~= "]";
			break;
		case Tag.funcDecl:
			return; // format("%s FUNC(%(%s, %))", next[0], params);
		case Tag.named:
			if (isConst)
			{
				sink ~= "const(";
				sink ~= name;
				sink ~= ")";
			}
			else
			{
				sink ~= name;
			}
			break;
		case Tag.unknown:
		case Tag.none:
			break;
		}
	}
}

/// Returns: `true` if `t` would not be default initialized to all zero like in C, but e.g. `char.init` or NaN
bool zeroInitInD(const CType t)
{
	if (t.name == "float" || t.name == "char" || t.name == "double" || t.name == "real")
	{
		return false;
	}
	if (t.isStaticArray())
	{
		return zeroInitInD(t.next[0]);
	}
	return true;
}

unittest
{
	assert(!zeroInitInD(CType.named("float")));
	assert(!zeroInitInD(CType.array(CType.array(CType.named("char"), "2"), "10")));
	assert(zeroInitInD(CType.pointer(CType.named("float"))));
}

// `int8_t` etc. are from stdint.h
// `__u8` etc. are used in v4l2 (video 4 linux)
// `__int8` etc. are used by Microsoft, see:
// https://docs.microsoft.com/en-us/cpp/cpp/int8-int16-int32-int64?view=msvc-160
private immutable string[2][] basicTypeMap = [
	["__int16",  "short"  ],
	["__int32",  "int"    ],
	["__int64",  "long"   ],
	["__int8",   "byte"   ],
	["__s16",    "short"  ],
	["__s32",    "int"    ],
	["__s64",    "long"   ],
	["__s8",     "byte"   ],
	["__u16",    "ushort" ],
	["__u32",    "uint"   ],
	["__u64",    "ulong"  ],
	["__u8",     "ubyte"  ],
	["char16_t", "wchar"  ],
	["char32_t", "dchar"  ],
	["int16_t",  "short"  ],
	["int16",    "short"  ],
	["int32_t",  "int"    ],
	["int32",    "int"    ],
	["int64_t",  "long"   ],
	["int64",    "long"   ],
	["int8_t",   "byte"   ],
	["int8",     "byte"   ],
	["uint16_t", "ushort" ],
	["uint16",   "ushort" ],
	["uint32_t", "uint"   ],
	["uint32",   "uint"   ],
	["uint64_t", "ulong"  ],
	["uint64",   "ulong"  ],
	["uint8_t",  "ubyte"  ],
	["uint8",    "ubyte"  ],
];

/// Replace known C primitive types to D-types
///
/// C code often used macros for integer types of standard sizes, which is not needed for D
string ctodPrimitiveType(string s)
{
	return mapLookup(basicTypeMap, s, s);
}

unittest
{
	assert(ctodPrimitiveType("int16_t") == "short");
	assert(ctodPrimitiveType("float") == "float");
}
