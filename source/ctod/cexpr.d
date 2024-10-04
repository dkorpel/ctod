module ctod.cexpr;

nothrow @safe:

import ctod.cdeclaration;
import ctod.ctype;
import ctod.translate;
import ctod.tree_sitter;
import ctod.util;

/// Given a (x) expression, get the node with x.
/// This is surprisingly non-trivial since the there is no field name for it in the C parser,
/// and there can be comments between the parens and the expression.
Node getParenContent(return scope Node node)
{
	if (node.sym != Sym.parenthesized_expression && node.sym != Sym.parenthesized_declarator)
		return node;

	foreach (i; 1 .. node.children.length + -1)
	{
		if (node.children[i].sym != Sym.comment)
			return node.children[i];
	}
	return node;
}

/// Try translating C expressions
///
/// WIP: type check as well
/// Things to be done:
/// - implicit casts from int to short, char, etc. must be explicit in D
/// - pointer arithmetic on static arrays can only be done after adding `.ptr`
bool ctodExpression(ref scope CtodCtx ctx, ref Node node)
{
	void depthFirst()
	{
		foreach (ref c; node.children)
		{
			translateNode(ctx, c);
		}
	}

	switch (node.sym)
	{
	case Sym.alias_field_identifier:
	case Sym.alias_type_identifier:
	case Sym.identifier:
		if (string s = translateIdentifier(node.sourceC))
		{
			node.replace(s);
		}
		if (string limit = mapLookup(limitMap, node.sourceC, null))
		{
			node.replace(limit);
		}
		if (node.sourceC in ctx.macroFuncParams)
		{
			node.prepend("` ~ ");
			node.append(" ~ `");
		}
		if (Decl decl = ctx.lookupDecl(node.sourceC))
			node.type = decl.type;
		else
			node.type = CType.unknown;

		return true;
	case Sym.sizeof_expression:
		if (ctodSizeof(ctx, node))
			return true;

		break;
	case Sym.parenthesized_expression:
		depthFirst();
		node.type = getParenContent(node).type;
		break;
	case Sym.assignment_expression:
		depthFirst();
		auto l = node.childField(Field.left);
		auto r = node.childField(Field.right);
		assert(l);
		assert(r);
		convertPointerTypes(ctx, l.type, r);
		break;
	case Sym.binary_expression:
		depthFirst();
		if (auto l = node.childField(Field.left))
		{
			CType lType = l.type;
			if (lType.isStaticArray())
			{
				l.append(".ptr");
			}
		}
		if (auto r = node.childField(Field.right))
		{
			CType rType = r.type;
			if (rType.isStaticArray())
			{
				r.append(".ptr");
			}
		}
		break;
	case Sym.comma_expression:
		depthFirst();
		if (auto l = node.childField(Field.left))
		{
			//ctodExpression(ctx, *l, type);
		}
		if (auto r = node.childField(Field.right))
		{
			//ctodExpression(ctx, *r, type);
		}
		break;
	case Sym.conditional_expression:
		depthFirst();
		// condition:
		// consequence:
		// alternative:
		break;
	case Sym.pointer_expression:
		depthFirst();
		if (auto arg = node.childField(Field.argument))
		{
			CType pType = arg.type;
			if (pType.isPointer())
			{
				node.type = pType.next[0];
			}
			else
			{
				node.type = CType.unknown;
			}
		}
		break;
	case Sym.unary_expression:
	case Sym.update_expression:
		depthFirst();
		if (auto r = node.childField(Field.argument))
		{

			// !(x = 3) => ((x = 3) != true)
			if (r.sym == Sym.parenthesized_expression)
			{
				auto a = getParenContent(r);
				if (a.sym == Sym.assignment_expression)
				{
					if (node.children.front.sym == Sym.anon_BANG)
					{
						// enhancement: when parent is parenthesized (like in `while (!(x=5))`), don't add parens
						r.prepend("(");
						r.append(" == 0)");
						node.children.front.replace(""); // remove ! operator
					}
				}
			}
		}
		break;
	case Sym.number_literal:
		CType type;
		string s = ctodNumberLiteral(node.sourceC, type);
		node.type = type;
		return node.replace(s);
	case Sym.null_:
		node.type = CType.pointer(CType.named("noreturn"));
		return node.replace("null");
	case Sym.concatenated_string:
		// "a" "b" "c" => "a"~"b"~"c"
		bool first = true;
		foreach (ref c; node.children)
		{
			if (c.sym == Sym.string_literal)
			{
				if (first)
				{
					first = false;
				}
				else
				{
					c.prepend("~ ");
				}
			}
		}
		node.type = CType.stringLiteral;
		return true;
	case Sym.char_literal:
		// Just remove u'x' U'x' u8'x' L'x' prefixes
		node.children[0].replace(`'`);
		switch (node.children[0].sym)
		{
		case Sym.anon_L_SQUOTE:
		case Sym.anon_u_SQUOTE:
			node.prepend("wchar(");
			node.append(")");
			break;
		case Sym.anon_u8_SQUOTE:
			node.prepend("char(");
			node.append(")");
			break;
		case Sym.anon_U_SQUOTE:
			node.prepend("dchar(");
			node.append(")");
			break;
		default:
			break;
		}
		break;
	case Sym.string_literal:

		node.children[0].replace(`"`);
		switch (node.children[0].sym)
		{
		case Sym.anon_L_DQUOTE:
		case Sym.anon_u_DQUOTE:
			node.append("w");
			break;
		case Sym.anon_u8_DQUOTE:
			node.append("c");
			break;
		case Sym.anon_U_DQUOTE:
			node.append("d");
			break;
		default:
			break;
		}
		node.type = CType.stringLiteral;
		return true;
	case Sym.cast_expression:
		if (auto c = node.firstChildType(Sym.anon_LPAREN))
		{
			c.replace("cast(");
		}
		if (auto c = node.childField(Field.type))
		{
			Decl[] decls = parseDecls(ctx, c, ctx.inlineTypes); //TODO: emit inline types?
			if (decls.length == 1)
			{
				OutBuffer sink;
				decls[0].toD(sink);
				c.replace(sink.extractOutBuffer);
				node.type = decls[0].type;
			}
		}
		return false;
	case Sym.field_expression:
		// TODO: find type of x->y
		node.type = CType.unknown;
		break;
	case Sym.call_expression:
		bool isMacroFunc = false;
		if (auto funcNode = node.childField(Field.function_))
		{
			CType fType = funcNode.type;
			if (fType.isFunction)
				node.type = fType.next[0];

			if (funcNode.sym == Sym.parenthesized_expression)
			{
				if (auto parenValue = getParenContent(funcNode))
				{
					if (parenValue.sym == Sym.identifier)
					{
						// So we have (X)(Y), which could be a cast to type X or a call to function X
						// Tree-sitter parses it like a call, but we assume that it's a cast,
						// since you wouldn't normally write a function call with parens
						funcNode.prepend("cast");
					}
				}
			}

			if (funcNode.sym == Sym.identifier)
			{
				const string funcName = funcNode.sourceC;
				if (funcName == "malloc" || funcName == "calloc" || funcName == "realloc")
				{
					node.type = CType.pointer(CType.named("void"));
				}
				if (translateSpecialFunction(node, funcNode))
					return true;

			}

			// SQR(...) => mixin(SQR!(...))
			if (auto mcro = funcNode.sourceC in ctx.macroTable)
			{
				if (*mcro == MacroType.inlineFunc)
				{
					funcNode.append("!");
					if (ctx.inMacroFunction)
					{
						node.prepend("` ~ ");
						node.append(" ~ `");
					}
					else
					{
						node.prepend("mixin(");
						node.append(")");
					}
					isMacroFunc = true;
				}
			}
		}
		if (auto argsNode = node.childField(Field.arguments))
		{
			if (argsNode.sym != Sym.argument_list)
			{
				break;
			}
			foreach (ref c; argsNode.children)
			{
				if (c.sym == Sym.anon_COMMA || c.sym == Sym.comment ||
					c.sym == Sym.anon_LPAREN || c.sym == Sym.anon_RPAREN)
				{
					continue;
				}
				if (isMacroFunc)
				{
					c.prepend("`");
					c.append("`");
					continue;
				}
				if (c.sym != Sym.identifier)
					continue;

				if (Decl decl = ctx.lookupDecl(c.sourceC))
				{
					if (decl.type.isStaticArray)
						c.append(".ptr");
					else if (decl.type.isFunction)
						c.prepend("&");
				}
			}
		}
		break;
	default:
		// unknown type
		break;
	}
	return false;
}

/// Fix assignment/initialization of node `r` to a node of type `lType`
///
/// C allows implicitly converting any T* -> U*, in D only T* -> `void*` gets that treatment
/// Try to fix this by adding explicit casts
/// C also allows converting numbers to pointers.
void convertPointerTypes(ref scope CtodCtx ctx, CType lType, ref Node r)
{
	CType rType = r.type;

	void castR()
	{
		OutBuffer sink;
		lType.toD(sink);
		const castStr = "cast(" ~ sink.extractOutBuffer ~ ") ";
		if (!mayNeedParens(r))
		{
			r.prepend(castStr);
		}
		else
		{
			r.prepend(castStr ~ "(");
			r.append(")");
		}
	}

	if (lType.isPointer && rType.isPointer)
	{
		if (lType.next[0] == rType.next[0])
			return;

		if (lType.next[0] == CType.named("void"))
			return; // D can implicitly convert to `void*`

		if (rType.next[0] == CType.named("noreturn"))
			return; // `null` can convert to any pointer type

		if (rType == CType.stringLiteral)
		{
			// This might be because of const mismatch,
			// we don't want to simply cast away const with D string literals
			return;
		}
		castR();
	}
	if (lType.isPointer && r.sym == Sym.number_literal)
	{
		if (r.sourceC == "0")
		{
			// int* x = 0; => int* x = null;
			r.replace("null");
		}
		else
		{
			// int* x = 3; => int* x = cast(int*) 3;
			castR();
		}
	}
}

/// Returns: `true` if attaching an operator to this `node` may introduce operator precedence issues,
///   `false` if it's an atomic primairy expression where surrounding it with parens is always redundant
private bool mayNeedParens(ref Node node)
{
	switch (node.sym)
	{
	case Sym.call_expression:
	case Sym.identifier:
	case Sym.null_:
	case Sym.number_literal:
	case Sym.parenthesized_expression:
	case Sym.string_literal:
		return false;
	default:
		return true;
	}
}

/// Translate special function calls
///
/// C's `offsetof()` macro becomes D's `.offsetof` property
/// offsetof(S, x) => S.x.offsetof
///
/// C's `va_arg` macro becomes D's template `va_arg!T`:
/// va_arg(v, int) => va_arg!int(v)
bool translateSpecialFunction(ref Node node, ref Node funcNode)
{
	if (funcNode.sym != Sym.identifier)
	{
		return false;
	}
	if (funcNode.sourceC == "offsetof" || funcNode.sourceC == "va_arg")
	{
		if (auto args = node.childField(Field.arguments))
		{
			if (args.hasError)
			{
				// unfortunately, tree-sitter considers `va_arg(x, int*)` an error
				return false;
			}
			string[2] argNames;
			size_t i = 0;
			foreach (ref c; args.children)
			{
				if (c.sym == Sym.identifier)
				{
					if (i >= 2)
					{
						i = 0; // too many arguments
						break;
					}
					argNames[i++] = c.sourceC;
				}
			}
			if (i == 2)
			{
				if (funcNode.sourceC == "va_arg")
				{
					return node.replace(funcNode.sourceC ~ "!" ~ argNames[1] ~ "(" ~ argNames[0] ~ ")");
				}
				else if (funcNode.sourceC == "offsetof")
				{
					return node.replace(argNames[0] ~ "." ~ argNames[1] ~ ".offsetof");
				}
			}
		}
	}
	return false;
}

private string toSizeof(scope string str)
{
	foreach (i; 0 .. str.length)
	{
		// A pointer / array needs brackets, can't have `int*.sizeof` or `int[].sizeof`
		if (str[i] == '*' || str[i] == ']')
		{
			return "(" ~ str ~ ").sizeof";
		}
	}
	return str ~ ".sizeof";
}

/// Translate C's `sizeof x` operator to D's `x.sizeof` property
private bool ctodSizeof(ref scope CtodCtx ctx, ref Node node)
{
	node.type = CType.named("size_t");
	if (auto typeNode = node.childField(Field.type))
	{
		// sizeof(short) => (short).sizeof
		Decl[] decls = parseDecls(ctx, typeNode, ctx.inlineTypes); //TODO: emit inline types?
		if (decls.length == 1)
		{
			OutBuffer sink;
			decls[0].toD(sink);
			return node.replace(toSizeof(sink.extractOutBuffer));
		}
	}
	else if (auto valueNode = node.childField(Field.value))
	{
		translateNode(ctx, valueNode);
		// `sizeof short` => `short.sizeof`
		if (valueNode.sym == Sym.identifier || valueNode.sym == Sym.number_literal)
		{
			node.replace(valueNode.translation() ~ ".sizeof");
		}
		else if (valueNode.sym == Sym.parenthesized_expression)
		{
			if (auto parenValue = getParenContent(valueNode))
			{
				if (parenValue.sym == Sym.identifier)
				{
					// sizeof(T) => T.sizeof
					return node.replace(parenValue.translation() ~ ".sizeof");
				}
				else if (parenValue.sym == Sym.string_literal)
				{
					// sizeof("abc") => ("abc".length + 1)
					return node.replace("(" ~ parenValue.translation() ~ ".length + 1)");
				}
				else
				{
					// sizeof(3) => typeof(3).sizeof
					return node.replace("typeof" ~ valueNode.translation() ~ ".sizeof");
				}
			}
		}
		else if (valueNode.sym == Sym.cast_expression)
		{
			// tree-sitter doesn't parse `sizeof(int) * 5;` correctly, so fix it
			if (auto t = valueNode.firstChildType(Sym.type_descriptor))
			{
				if (auto p = valueNode.firstChildType(Sym.pointer_expression))
				{
					return node.replace(toSizeof(t.translation()) ~ " " ~ p.translation());
				}
			}
		}
		else if (valueNode.sym == Sym.string_literal)
		{
			// sizeof "abc" => ("abc".length + 1)
			return node.replace("(" ~ valueNode.translation() ~ ".length + 1)");
		}
	}
	return false;
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
];
