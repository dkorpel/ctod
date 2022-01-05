module ctod.translate;

import ctod;
import dbg;
import tree_sitter.api, tree_sitter.wrapper;

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
	auto ctx = TranslationContext("foo.c", source);
	ctx.stripComments = settings.stripComments;
	translateNode(ctx, *root);

	string result = "";

	if (settings.includeHeader) {
		result ~= "module "~moduleName~";\n";
		result ~= "extern(C): @nogc: nothrow: __gshared:\n";
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
	result ~= root.output;
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

package struct Scope {
	Scope* parent = null;
	Decl[string] table;
}

/// A single .c file
package struct TranslationContext {

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
	Decl[string] symbolTable;
	Decl[string] localSymbolTable;
	MacroType[string] macroTable;
	string inFunction = null;

	this(string fileName, string source) {
		this.fileName = fileName;
		this.source = source;
	}

	void enterFunction(string functionName) {
		inFunction = functionName;
	}

	void leaveFunction() {
		inFunction = null;
		localSymbolTable.clear();
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
	}

	int uniqueIdCounter = 0;
	string uniqueIdentifier(string suggestion) {
		import bops.string.lex: toUpper;
		if (suggestion.length > 0) {
			return "_" ~ suggestion[0].toUpper ~ suggestion[1..$];
		} else {
			assert(0);
		}
	}
}

///
void translateNode(ref TranslationContext ctu, ref Node node) {
	if (node.isTranslated) {
		return;
	}
	if (tryTranslatePreprocessor(ctu, node)) {
		return;
	}
	if (tryTranslateDeclaration(ctu, node)) {
		return;
	}
	if (tryTranslateMisc(ctu, node)) {
		return;
	}

	foreach(ref c; node.children) {
		translateNode(ctu, c);
	}
	node.isTranslated = true;
}

package bool tryTranslateMisc(ref TranslationContext ctu, ref Node node) {
	import bops.tostring: toGcString;
	switch(node.typeEnum) {
		case Sym.comment:
			// todo: maybe convert doxygen to Ddoc?
			if (ctu.stripComments) {
				node.replace("");
			}
			return true;
		case Sym.switch_statement:
			// D mandates `default` case in `switch`
			// note: switch statements can have `case` statements in the weirdest places
			// we can be a bit conservative here and only check the common switch pattern
			if (auto bodyNode = node.childField("body")) {
				if (bodyNode.typeEnum == Sym.compound_statement) {
					// TODO
					bodyNode.children[$-1].prepend("default: break;");
				}
			}
			break;
		case Sym.number_literal:
			import std.array: replace;
			// long specifier must be capitalized in D, 1llu => 1LLu
			// float must have digits after dot, 1.f => 1.0f
			return node.replace(node.source.replace("l", "L").replace(".f", ".0f").replace(".F", ".0F"));
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
			return true;
		case Sym.primitive_type:
			if (string s = replacePrimitiveType(node.source)) {
				node.replace(s);
				return true;
			}
			return false;
		case Sym.null_:
			return node.replace("null");

		case Sym.type_definition:
			// Decl[] decls = parseDecls(ctu, *c);
			auto typeField = node.childField("type");
			auto declaratorField = node.childField("declarator");
			if (!declaratorField || !typeField) {
				return true;
			}
			if (auto structId = typeField.childField("name")) {
				if (typeField.typeEnum == Sym.struct_specifier || typeField.typeEnum == Sym.union_specifier) {
					if (auto bodyNode = typeField.childField("body")) {
						translateNode(ctu, *bodyNode);
					} if (declaratorField.typeEnum == Sym.alias_type_identifier && declaratorField.source == structId.source) {
						// typedef struct X X; => uncomment, not applicable to D
						node.prepend("/*");
						node.append("*/");
						return true;
					}
				}
				if (typeField.typeEnum == Sym.enum_specifier) {
					if (auto bodyNode = typeField.childField("body")) {
						translateNode(ctu, *bodyNode);
					}
					if (auto nameNode = typeField.childField("name")) {

					}
				}
			}
			break;
		case Sym.anon_typedef:
			return node.replace("alias");
		case Sym.sizeof_expression:
			if (auto typeNode = node.childField("type")) {
				// sizeof(short) => (short).sizeof
				translateNode(ctu, *typeNode);
				node.replace("" ~ typeNode.output ~ ".sizeof");
			} else if (auto valueNode = node.childField("value")) {
				translateNode(ctu, *valueNode);
				// `sizeof short` => `short.sizeof`
				if (valueNode.typeEnum == Sym.identifier) {
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
				}
			}
			break;
		case Sym.anon_DASH_GT:
			return node.replace("."); // s->field => s.field
		case Sym.cast_expression:
			if (auto c = node.firstChildType(Sym.anon_LPAREN)) {
				c.replace("cast(");
			}
			if (auto c = node.childField("type")) {
				InlineType[] inlineTypes;
				Decl[] decls = parseDecls(ctu, *c, inlineTypes); //todo: emit inline types?
				if (decls.length == 1) {
					c.replace(decls[0].toGcString());
				}
			}
			return false;
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
			if (auto bodyNode = node.childField("body")) {
				//
			} else {
				node.append(";");
			}
			break;
		case Sym.translation_unit:
			// try to remove header guard
			// #ifdef NAME_H
			// #define NAME_H
			// ...actual code
			// #endif
			if (auto ifdefNode = node.firstChildType(Sym.preproc_ifdef)) {
				int commentCount = 0;
				string id = null;
			headerGuardSearch:
				foreach(i; 0..ifdefNode.children.length) {
					switch(ifdefNode.children[i].typeEnum) {
						case Sym.comment:
							commentCount++;
							continue;
						case Sym.preproc_def:
							// preproc can only be preceded by comments, or else it's no header guard
							// 2 for #ifdef and identifier tokens
							if (i > commentCount + 2) {
								break headerGuardSearch;
							}
							if (auto defIdNode = ifdefNode.children[i].childField("name")) {
								// #define matches the #ifndef
								if (defIdNode.source == id) {
									// put remaining children under translation unit instead of the ifdef
									foreach(j; 0..ifdefNode.children.length) {
										if (j <= i || j + 1 == ifdefNode.children.length) {
											ifdefNode.children[j].replace("");
										} else {
											translateNode(ctu, ifdefNode.children[j]);
										}
									}
									return true;
								}
							}
							break headerGuardSearch;
						case Sym.identifier:
							if (id == null) {
								id = ifdefNode.children[i].source;
							} else {
								break headerGuardSearch;
							}
							continue;
						default:
							break;
					}
				}
			}
			removeSemicolons(node);
			break;
		case Sym.assignment_expression:

			break;
		case Sym.call_expression:
			if (auto argsNode = node.childField("arguments")) {
				if (argsNode.typeEnum == Sym.argument_list) {
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
			}
			// TODO: append .ptr to array parameters
			// prepend & to functions converted to function pointers
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

/// Params:
///   str = macro from <float.h>
/// Returns: corresponding D type property, or `null` if no match
string translateLimit(string str) {
	switch(str) {
		static foreach(p; limitMap) {
			case p[0]: return p[1];
		}
		case "FIXME": return null; // remove string switch
		default: return null;
	}
}

unittest {
	assert(translateLimit("FLT_MAX") == "float.max");
}
