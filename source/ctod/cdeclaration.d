module ctod.cdeclaration;
@safe:
nothrow:

import ctod.tree_sitter;
import ctod.translate;
import ctod.ctype;
import ctod.util;

/// Returns: list of parsed declarations from `node`
Decl[] ctodTryDeclaration(ref scope CtodCtx ctx, ref Node node)
{
	InlineType[] inlinetypes;

	// cInit = if the variable gets initialized in D,
	//   which might differ from C which 0 initialized floats and void initializes parameters
	Decl[] translateDecl(string suffix, Sym sym)
	{
		string apiMacro;
		Decl[] decls = parseDecls(ctx, node, inlinetypes, &apiMacro);

		OutBuffer result;
		if (apiMacro.length > 0)
		{
			result ~= apiMacro ~ " ";
		}
		foreach (s; inlinetypes)
		{
			s.toD(result);
		}
		CType previousType = CType.none;
		size_t finalCount = 0;
		foreach (decl; decls)
		{
			bool cInit = sym == Sym.declaration || sym == Sym.field_declaration;
			if (cInit && decl.initializerD.length == 0)
			{
				if (ctx.inFunction && !decl.quals.staticFunc)
				{
					// void initialize function local variables
					decl.initializerD = " = void";
				}
				else if (!zeroInitInD(decl.type) && !(ctx.inUnion && ctx.currentTypeScope.fieldIndex > 0))
				{
					// `char x;` => `char x = 0;`
					decl.initializerD = " = 0";
				}
			}

			if (sym != Sym.function_definition && decl.type.isFunction
				&& decl.identifier in ctx.functionDefinitions)
				continue;

			// Try to combine `int* x; int* y;` into `int* x, y`
			// But: cannot combine function types: `void f(), g;` doesn't work in D (#twab)
			if (decl.type != previousType || decl.type.isFunction())
			{
				if (previousType != CType.none)
				{
					result ~= "; ";
				}
				decl.toD(result);
			}
			else
			{
				result ~= ", " ~ decl.identifier ~ decl.initializerD;
			}
			ctx.registerDecl(decl);
			previousType = decl.type;
			finalCount++;
		}
		if (finalCount > 0)
			result ~= suffix;

		node.replace(result.extractOutBuffer);
		return decls;
	}

	switch (node.sym)
	{
	case Sym.function_definition:
		if (auto bodyNode = node.childField(Field.body_))
		{
			auto declNode = node.childField(Field.declarator);
			assert(declNode);
			// Translation of function signautre is pretty destructive regarding layout,
			// but at least it's rare to have comments inside the parameter list
			// For now: add whitespace before bodyNode to preserve brace style and comments after the signature
			const layout = ctx.sourceC[declNode.end .. bodyNode.start];
			ctx.enterFunction("???");
			translateNode(ctx, bodyNode);
			ctx.leaveFunction();

			return translateDecl(layout ~ bodyNode.translation(), node.sym);
		}
		break;
	case Sym.parameter_declaration:
		return translateDecl("", node.sym);
	case Sym.field_declaration: // struct / union field
		if (auto bitNode = node.firstChildType(Sym.bitfield_clause))
		{
			translateNode(ctx, bitNode);
			node.append("/*" ~ bitNode.translation() ~ " !!*/");
		}
		return translateDecl(";", node.sym);
	case Sym.declaration: // global / local variable
		return translateDecl(";", node.sym);
	default:
		break;
	}
	return null;
}

bool ctodTryTypedef(ref scope CtodCtx ctx, ref Node node)
{
	InlineType[] inlinetypes;
	if (node.sym != Sym.type_definition)
	{
		return false;
	}
	Decl[] decls = parseDecls(ctx, node, inlinetypes);
	OutBuffer result;

	// It's very common to typedef an anonymous type with a single name:
	// `typedef struct {...} X`
	// No need to give temporary name `_X` and create `alias X = _X`,
	// just pretend the type was named `X` all along
	if (inlinetypes.length == 1 && decls.length == 1)
	{
		if (decls[0].type == CType.named(inlinetypes[0].name))
		{
			inlinetypes[0].name = decls[0].identifier;
			decls = null;
		}
	}

	foreach (s; inlinetypes)
	{
		s.toD(result);
		if (s.node)
		{
			// Put enum members into the global scope with aliases
			node.append(enumMemberAliases(s.name, s.node));
		}
	}
	bool first = true;
	foreach (d; decls)
	{
		if (d.type != CType.named(d.identifier))
		{
			if (first)
			{
				first = false;
			}
			else
			{
				result ~= "\n";
			}
			result ~= "alias " ~ d.identifier ~ " = ";
			d.type.toD(result);
			result ~= ";";
		}
	}
	node.replace(result.extractOutBuffer);
	return true;
}

/// Try translating variable initializers
/// Returns: true if translation is done, no need to translate children
bool ctodTryInitializer(ref scope CtodCtx ctx, ref Node node)
{
	switch (node.sym)
	{
	case Sym.compound_literal_expression:
		// (Rectangle){x, y, width, height} => Rectangle(x, y, width, height)
		foreach (ref c; node.children)
		{
			if (c.sym == Sym.anon_LPAREN)
			{
				c.replace("");
			}
			else if (c.sym == Sym.anon_RPAREN)
			{
				c.replace("");
			}
			else if (c.sym == Sym.initializer_list)
			{
				foreach (ref c2; c.children)
				{
					if (c2.sym == Sym.anon_LBRACE)
						c2.replace("(");
					else if (c2.sym == Sym.anon_RBRACE)
						c2.replace(")");
					else
						translateNode(ctx, c2);
				}
			}
		}
		return true;
	case Sym.initializer_list:
		auto t = ctx.inDeclType;
		bool arrayInit = false;
		if (t.isCArray || t.isStaticArray)
		{
			arrayInit = true;
			ctx.inDeclType = t.next[0];
		}
		// In D, the initializer braces depend on whether it's a struct {} or array []
		// The current type check is rather primitive, it doesn't look up type aliases and
		// doesn't consider nested types (e.g. struct of array of struct of ...)
		// So also inspect the literal itself to gain clues
		foreach (ref c; node.children)
		{
			// Array literal can have `[0] = 3`, struct can have `.field = 3`
			if (c.sym == Sym.initializer_pair)
			{
				if (auto c1 = c.childField(Field.designator))
				{
					if (c1.sym == Sym.field_designator)
					{
						arrayInit = false;
					}
					else if (c1.sym == Sym.subscript_designator)
					{
						arrayInit = true;
					}
				}
			}
			ctx.translateNode(c);
		}
		(() @trusted => ctx.inDeclType = t)(); // DIP1000 limitation with lifetimes

		if (arrayInit)
		{
			if (auto c = node.firstChildType(Sym.anon_LBRACE))
			{
				c.replace("[");
			}
			if (auto c = node.firstChildType(Sym.anon_RBRACE))
			{
				c.replace("]");
			}
		}
		break;
	case Sym.initializer_pair:
		// [a] = b  =>  a: b, this removes the =
		// {.entry = {}} => {entry: {}}
		if (auto designatorNode = node.childField(Field.designator))
		{
			// if (designatorNode.sym == Sym.subscript_designator)
			if (auto c = node.firstChildType(Sym.anon_EQ))
			{
				c.replace("");
				c.removeLayout();
			}
		}
		else
		{
			assert(0);
		}
		break;
	case Sym.field_designator:
		// .field = => field:
		node.replace(node.children[1].sourceC); // take source of child field_identifier to remove leading dot
		node.append(":");
		break;
	case Sym.subscript_designator:
		// [a] = b  =>  a: b
		if (auto c = node.firstChildType(Sym.anon_LBRACK))
		{
			c.replace("");
		}
		if (auto c = node.firstChildType(Sym.anon_RBRACK))
		{
			c.replace("");
		}
		node.append(":");
		break;
	default:
		break;
	}
	return false;
}

/// Modify C identifiers that are keywords in D
string translateIdentifier(string s)
{
	return mapLookup(keyWordMap, s, null) ? s ~ "_" : s;
}

/// C identifiers that are keywords in D
/// Does not include keywords that are in both C and D (if, switch, static)
/// or have similar meaning (null, true, assert)
private immutable string[] keyWordMap = [
	"abstract", "alias", "align", "asm", "auto", "bool", "byte", "cast", "catch", "cdouble",
	"cent", "cfloat", "char", "class", "creal", "dchar", "debug", "delegate", "deprecated",
	"export", "final", "finally", "foreach", "foreach_reverse", "function", "idouble", "ifloat",
	"immutable", "import", "in", "inout", "interface", "invariant", "ireal", "is", "lazy", "macro",
	"mixin", "module", "new", "nothrow", "out", "override", "package", "pragma", "private",
	"protected", "public", "pure", "real", "ref", "scope", "shared", "super", "synchronized",
	"template", "this", "throw", "try", "typeid", "typeof", "ubyte", "ucent", "uint", "ulong",
	`unittest`, "ushort", "version", "wchar", "with",
];
