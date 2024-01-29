module ctod.cdeclaration;

nothrow @safe:

import ctod.tree_sitter;
import ctod.translate;
import ctod.ctype;

/// Returns: true if a declaration was matched and replaced
Decl[] ctodTryDeclaration(ref CtodCtx ctx, ref Node node) {
	InlineType[] inlinetypes;

	Decl[] translateDecl(string suffix, bool cInit) {
		string apiMacro;
		Decl[] decls = parseDecls(ctx, node, inlinetypes, &apiMacro);

		string result = "";
		if (apiMacro.length > 0) {
			result ~= apiMacro ~ " ";
		}
		foreach (s; inlinetypes) {
			result ~= s.toString();
		}
		CType previousType = CType.none;
		foreach (d; decls) {
			if (cInit && d.initializer.length == 0) {
				if (ctx.inFunction && !d.quals.staticFunc) {
					// void initialize function local variables
					d.initializer = "void";
				} else if (noZeroInitInD(d.type) && !(ctx.inUnion && ctx.currentTypeScope().fieldIndex > 0)) {
					// `char x;` => `char x = 0;`
					d.initializer = "0";
				}
			}

			if (d.type != previousType) {
				if (previousType != CType.none) {
					result ~= "; ";
				}
				result ~= d.toString();
			} else {
				result ~= ", " ~ d.identifier ~ d.initializerAssign;
			}
			ctx.registerDecl(d);
			previousType = d.type;
		}
		result ~= suffix;
		node.replace(result);
		node.isTranslated = true;
		return decls;
	}

	switch (node.typeEnum) {
		case Sym.function_definition:
			if (auto bodyNode = node.childField(Field.body_)) {
				auto declNode = node.childField(Field.declarator);
				assert(declNode);
				// Translation of function signautre is pretty destructive regarding layout,
				// but at least it's rare to have comments inside the parameter list
				// For now: add whitespace before bodyNode to preserve brace style and comments after the signature
				const layout = node.fullSource[declNode.end .. bodyNode.start];
				ctx.enterFunction("???");
				translateNode(ctx, *bodyNode);
				ctx.leaveFunction();
				return translateDecl(layout ~ bodyNode.output(), false);
			}
			break;
		case Sym.parameter_declaration:
			return translateDecl("", false);
		case Sym.field_declaration: // struct / union field
			if (auto bitNode = node.firstChildType(Sym.bitfield_clause)) {
				translateNode(ctx, *bitNode);
				node.append("/*"~bitNode.output~" !!*/");
			}
			return translateDecl(";", true);
		case Sym.declaration: // global / local variable
			return translateDecl(";", true);
		default:
			break;
	}
	return null;
}

bool ctodTryTypedef(ref CtodCtx ctx, ref Node node) {
	InlineType[] inlinetypes;
	if (node.typeEnum != Sym.type_definition) {
		return false;
	}
	Decl[] decls = parseDecls(ctx, node, inlinetypes);
	string result = "";

	// It's very common to typedef an anonymous type with a single name:
	// `typedef struct {...} X`
	// No need to give temporary name `_X` and create `alias X = _X`,
	// just pretend the type was named `X` all along
	if (inlinetypes.length == 1 && decls.length == 1) {
		if (decls[0].type == CType.named(inlinetypes[0].name)) {
			inlinetypes[0].name = decls[0].identifier;
			decls = null;
		}
	}

	foreach (s; inlinetypes) {
		result ~= s.toString();
		if (s.node) {
			// Put enum members into the global scope with aliases
			node.append(enumMemberAliases(s.name, *s.node));
		}
	}
	bool first = true;
	foreach (d; decls) {
		if (d.type == CType.named(d.identifier)) {
			// result ~= "/*alias " ~ d.toString() ~ ";*/";
		} else {
			if (first) {
				first = false;
			} else {
				result ~= "\n";
			}
			result ~= "alias " ~ d.identifier ~ " = " ~ d.type.toString() ~ ";";
		}
	}
	node.replace(result);
	return true;
}

/// Try translating variable initializers
/// Returns: true if translation is done, no need to translate children
bool ctodTryInitializer(ref CtodCtx ctx, ref Node node) {
	switch (node.typeEnum) {
		case Sym.compound_literal_expression:
			// (Rectangle){x, y, width, height} => Rectangle(x, y, width, height)
			foreach (ref c; node.children) {
				if (c.typeEnum == Sym.anon_LPAREN) {
					c.replace("");
				} else if (c.typeEnum == Sym.anon_RPAREN) {
					c.replace("");
				} else if (c.typeEnum == Sym.initializer_list) {
					foreach (ref c2; c.children) {
						if (c2.typeEnum == Sym.anon_LBRACE) {
							c2.replace("(");
						} else if (c2.typeEnum == Sym.anon_RBRACE) {
							c2.replace(")");
						} else {
							translateNode(ctx, c2);
						}
					}
				}
			}
			return true;
		case Sym.initializer_list:
			auto t = ctx.inDeclType;
			bool arrayInit = t.isCArray || t.isStaticArray;

			// In D, the initializer braces depend on whether it's a struct {} or array []
			// The current type check is rather primitive, it doesn't look up type aliases and
			// doesn't consider nested types (e.g. struct of array of struct of ...)
			// So also inspect the literal itself to gain clues
			foreach (ref c; node.children) {
				// Array literal can have `[0] = 3`, struct can have `.field = 3`
				if (c.typeEnum == Sym.initializer_pair) {
					if (auto c1 = c.childField(Field.designator)) {
						if (c1.typeEnum == Sym.field_designator) {
							arrayInit = false;
						} else if (c1.typeEnum == Sym.subscript_designator) {
							arrayInit = true;
						}
					}
				}
			}

			if (arrayInit) {
				if (auto c = node.firstChildType(Sym.anon_LBRACE)) {
					c.replace("[");
				}
				if (auto c = node.firstChildType(Sym.anon_RBRACE)) {
					c.replace("]");
				}
			}
			break;
		case Sym.initializer_pair:
			// [a] = b  =>  a: b, this removes the =
			// {.entry = {}} => {entry: {}}
			if (auto designatorNode = node.childField(Field.designator)) {
				// if (designatorNode.typeEnum == Sym.subscript_designator)
				if (auto c = node.firstChildType(Sym.anon_EQ)) {
					c.replace("");
					c.removeLayout();
				}
			} else {
				assert(0);
			}
			break;
		case Sym.field_designator:
			// .field = => field:
			node.replace(node.children[1].source); // take source of child field_identifier to remove leading dot
			node.append(":");
			break;
		case Sym.subscript_designator:
			// [a] = b  =>  a: b
			if (auto c = node.firstChildType(Sym.anon_LBRACK)) {
				c.replace("");
			}
			if (auto c = node.firstChildType(Sym.anon_RBRACK)) {
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
string translateIdentifier(string s) {
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
	"unittest", "ushort", "version", "wchar", "with",
];
