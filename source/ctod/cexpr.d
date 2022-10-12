module ctod.cexpr;

import ctod.tree_sitter;
import ctod.translate;
import ctod.ctype;
import ctod.cdeclaration;

/// Given a (x) expression, get the node with x.
/// This is surprisingly non-trivial since the there is no field name for it in the C parser,
/// and there can be comments between the parens and the expression.
ref Node getParenExpression(return ref Node node) {
	if (node.typeEnum != Sym.parenthesized_expression) {
		return node;
	}
	foreach(i; 1..node.children.length + -1) {
		if (node.children[i].typeEnum != Sym.comment) {
			return node.children[i];
		}
	}
	return node;
}

/// Try translating C expressions
///
/// WIP: type check as well
/// Things to be done:
/// - implicit casts from int to short, char, etc. must be explicit in D
/// - pointer casts (other than void*) must be explicit in D
/// - pointer arithmetic on static arrays can only be done after .ptr
bool ctodExpression(ref TranslationContext ctu, ref Node node)
{
	void depthFirst() {
		foreach(ref c; node.children) {
			translateNode(ctu, c);
		}
	}

	switch (node.typeEnum)
	{
		case Sym.alias_field_identifier:
		case Sym.alias_type_identifier:
		case Sym.identifier:
			if (string s = translateIdentifier(node.source)) {
				node.replace(s);
			}
			if (Decl decl = ctu.lookupDecl(node.source)) {
				ctu.setExpType(node, decl.type);
			} else {
				ctu.setExpType(node, CType.unknown);
			}
			return true;
		case Sym.sizeof_expression:
			if (ctodSizeof(ctu, node)) {
				return true;
			}
			break;
		case Sym.parenthesized_expression:
			depthFirst();
			ctu.setExpType(node, ctu.expType(getParenExpression(node)));
			break;
		case Sym.assignment_expression:
			depthFirst();
			if (auto l = node.childField("left")) {

			}
			if (auto r = node.childField("right")) {

			}
			break;
		case Sym.binary_expression:
			depthFirst();
			if (auto l = node.childField("left")) {
				CType lType = ctu.expType(*l);
				if (lType.isStaticArray()) {
					l.append(".ptr");
				}
			}
			if (auto r = node.childField("right")) {
				CType rType = ctu.expType(*r);
				if (rType.isStaticArray()) {
					r.append(".ptr");
				}
			}
			break;
		case Sym.comma_expression:
			depthFirst();
			if (auto l = node.childField("left")) {
				//ctodExpression(ctu, *l, type);
			}
			if (auto r = node.childField("right")) {
				//ctodExpression(ctu, *r, type);
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
			if (auto arg = node.childField("argument")) {
				CType pType = ctu.expType(*arg);
				if (pType.isPointer()) {
					ctu.setExpType(node, pType.next[0]);
				} else {
					ctu.setExpType(node, CType.unknown);
				}
			}
			break;
		case Sym.unary_expression:
		case Sym.update_expression:
			depthFirst();
			if (auto r = node.childField("argument")) {

				// !(x = 3) => ((x = 3) != true)
				if (r.typeEnum == Sym.parenthesized_expression) {
					auto a = getParenExpression(*r);
					if (a.typeEnum == Sym.assignment_expression) {
						if (node.children[0].typeEnum == Sym.anon_BANG) {
							// enhancement: when parent is parenthesized (like in `while (!(x=5))`), don't add parens
							r.prepend("(");
							r.append(" == 0)");
							node.children[0].replace(""); // remove ! operator
						}
					}
				}
			}
			break;
		case Sym.number_literal:
			CType type;
			string s = ctodNumberLiteral(node.source, type);
			ctu.setExpType(node, type);
			return node.replace(s);
		case Sym.null_:
			ctu.setExpType(node, CType.pointer(CType.named("noreturn")));
			return node.replace("null");
		case Sym.concatenated_string:
			// "a" "b" "c" => "a"~"b"~"c"
			bool first = true;
			foreach(ref c; node.children) {
				if (c.typeEnum == Sym.string_literal) {
					if (first) {
						first = false;
					} else {
						c.prepend("~ ");
					}
				}
			}
			ctu.setExpType(node, CType.pointer(CType.named("char")));
			return true;
		case Sym.string_literal:
			ctu.setExpType(node, CType.pointer(CType.named("char")));
			return true;
		case Sym.cast_expression:
			if (auto c = node.firstChildType(Sym.anon_LPAREN)) {
				c.replace("cast(");
			}
			if (auto c = node.childField("type")) {
				InlineType[] inlineTypes;
				Decl[] decls = parseDecls(ctu, *c, inlineTypes); //todo: emit inline types?
				if (decls.length == 1) {
					c.replace(decls[0].toString());
					ctu.setExpType(node, decls[0].type);
				}
			}

			// if (auto r = node.childField("value")) {
			// 	ctodExpression(ctu, *r, type);
			// }
			// if (auto l = node.childField("type")) {
			// 	ctodExpression(ctu, *l, type);
			// }
			// break;
			return false;
		case Sym.field_expression:
			// TODO: find type of x->y
			ctu.setExpType(node, CType.unknown);
			break;
		case Sym.call_expression:
			if (auto funcNode = node.childField("function")) {
				CType fType = ctu.expType(*funcNode);
				if (fType.isFunction) {
					ctu.setExpType(node, fType.next[0]);
				}

				if (translateOffsetof(node, *funcNode)) {
					return true;
				}
			}
			if (auto argsNode = node.childField("arguments")) {
				if (argsNode.typeEnum != Sym.argument_list) {
					break;
				}
				foreach(ref c; argsNode.children) {
					if (c.typeEnum != Sym.identifier) {
						continue;
					}
					if (Decl decl = ctu.lookupDecl(c.source)) {
						if (decl.type.isStaticArray) {
							c.append(".ptr");
						} else if (decl.type.isFunction) {
							c.prepend("&");
						}
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

/// Translate the C offsetof() macro to D's .offsetof property
///
/// offsetof(S, x) => S.x.offsetof
bool translateOffsetof(ref Node node, ref Node funcNode) {
	if (funcNode.typeEnum == Sym.identifier && funcNode.source == "offsetof") {
		if (auto args = node.childField("arguments")) {
			if (args.hasError) {
				return false;
			}
			string[2] argNames;
			size_t i = 0;
			foreach(ref c; args.children) {
				if (c.typeEnum == Sym.identifier) {
					if (i >= 2) {
						i = 0; // too many arguments
						break;
					}
					argNames[i++] = c.source;
				}
			}
			if (i == 2) {
				return node.replace(argNames[0] ~ "." ~ argNames[1] ~ ".offsetof");
			}
		}
	}
	return false;
}

/// Translate C's `sizeof x` operator to D's `x.sizeof` property
bool ctodSizeof(ref TranslationContext ctu, ref Node node) {
	ctu.setExpType(node, CType.named("size_t"));
	if (auto typeNode = node.childField("type")) {
		// sizeof(short) => (short).sizeof
		translateNode(ctu, *typeNode);
		node.replace("" ~ typeNode.output ~ ".sizeof");
	} else if (auto valueNode = node.childField("value")) {
		translateNode(ctu, *valueNode);
		// `sizeof short` => `short.sizeof`
		if (valueNode.typeEnum == Sym.identifier || valueNode.typeEnum == Sym.number_literal) {
			node.replace(valueNode.output ~ ".sizeof");
		} else if (valueNode.typeEnum == Sym.parenthesized_expression) {
			// sizeof(3) => typeof(3).sizeof
			// sizeof(T) => T.sizeof
			if (auto parenValue = valueNode.firstChildType(Sym.identifier)) {
				valueNode = parenValue;
			}
			if (valueNode.typeEnum == Sym.identifier) {
				return node.replace(valueNode.output ~ ".sizeof");
			} else {
				return node.replace("typeof" ~ valueNode.output ~ ".sizeof");
			}
		} else if (valueNode.typeEnum == Sym.cast_expression) {
			// tree-sitter doesn't parse `sizeof(int) * 5;` correctly, so fix it
			if (auto t = valueNode.firstChildType(Sym.type_descriptor)) {
				if (auto p = valueNode.firstChildType(Sym.pointer_expression)) {
					return node.replace(t.output ~ ".sizeof " ~ p.output);
				}
			}
		}
	}
	return false;
}
