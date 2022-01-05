/**
Translate C types
*/
module ctod.ctype;

import dbg;
import ctod;
import tree_sitter.wrapper;

/// Declaration
struct Decl {
	string storageClasses;
	CType type = CType.none;
	string identifier = ""; /// name of variable / function
	string initializer = ""; /// expression that initializes the variable

	void toString(O)(ref O sink) const scope {
		import bops.tostring: toStringM, fmtRange;
		toStringM(sink, storageClasses);

		// D declarations are usually separated as [type] followed by [identifier], but there is one exception:
		// extern functions. (functions with bodies are handled separately, and function pointers have the name on the right
		if (type.tag == CType.Tag.funcDecl) {
			type.next[0].toString(sink);
			toStringM(sink, " ", identifier, "(", fmtRange(type.params, ", "), ")");
		} else {
			type.toString(sink);
			if (identifier.length > 0) {
				toStringM(sink, " ", identifier);
			}
			if (initializer.length > 0) {
				toStringM(sink, " = ", initializer);
			}
		}
	}
	///
	enum none = Decl.init;
	///
	bool opCast() const scope {return type != CType.none;}
}

unittest {
	import bops.test: assertToString;
	assertToString(Decl("inline ", CType.named("int"), "x", "3"), "inline int x = 3");
}

/// A type in the middle of an expression.
/// C allows to e.g. define a struct inside a parameter list.
struct InlineType {
	string keyword;
	string name = null;
	string body_;
	bool hasBody() const {return body_.length > 0;}
	string toString() const {
		return keyword ~ " " ~ name ~ (hasBody() ? " " ~ body_ : "");
	}
}

/// C declarations are declared this way:
/// First, a 'base type' which is a primitive type or identifier
/// Then, one or more expressions that should evaluate to a value of 'base type'
///
/// Note: the base-type can be an (anonymous) struct / union / enum, which is not allowed in D.
/// Therefor, the second return value is a type declaration that the primitive type depends on.
///
/// Returns: [primitive type, dependent type]
string parseTypeNode(ref TranslationContext ctu, ref Node node, ref InlineType[] inlineTypes) {

	// keyword = struct, union or enum
	string namedType(string keyword) {
		auto nameNode = node.childField("name");
		//import dbg; dprint(node.source);
		if (auto c = node.childField("body")) {
			translateNode(ctu, *c);
			string name = nameNode ? nameNode.source : null;
			inlineTypes ~= InlineType(keyword, name, c.output);
			return name;
		} else if (nameNode) {
			inlineTypes ~= InlineType(keyword, nameNode.source, ";");
			return nameNode.source;
		}
		return "@@err"~__LINE__.stringof;
	}

	switch(node.typeEnum) {
		case Sym.primitive_type:
			return replacePrimitiveType(node.source);
		case Sym.alias_type_identifier:
			if (node.source == "wchar_t") {
				ctu.needsWchar = true;
				return node.source;
			} else if (node.source == "bool") {
				ctu.needsCbool = true;
				return "c_bool";
			} else {
				// int8_t is recognized as a primitive type, but __u8 is a type identifier,
				// so also do replacePrimitiveType here.
				const replacement = replacePrimitiveType(node.source);
				if (replacement == node.source) {
					// no replacement to a D-type, so escape keywords (out => out_)
					return replaceIdentifier(node.source);
				} else {
					// replacement to a D-type , e.g. __u8 => ubyte, no escaping
					return replacement;
				}
			}
		case Sym.sized_type_specifier:
			bool signed = true;
			int longCount = 0;
			string primitive = "";
			foreach(ref c; node.children) {
				switch(c.typeEnum) {
					case Sym.comment: continue;
					case Sym.anon_unsigned:
						signed = false;
						break;
					case Sym.anon_long:
						longCount++;
						break;
					case Sym.primitive_type:
						primitive = replacePrimitiveType(c.source);
						break;
					case Sym.anon_short: // not a primitive_type apparently, but similar to `unsigned`
						primitive = "short";
						break;
					default: break;
				}
			}

			if (longCount > 0 && primitive == "double") {
				primitive = "real";
			} else if (longCount == 1 && primitive == "") {
				primitive = "c_long";
				ctu.needsClong = true;
			} else if (longCount == 2 && primitive == "") {
				primitive = "long";
			}

			if (!signed && primitive.length && primitive[0] != 'u') {
				if (primitive == "char") {
					primitive = "ubyte";
				} else if (primitive == "c_long") {
					primitive = "c_ulong";
				} else {
					primitive = "u" ~ primitive;
				}
			}
			return primitive;
		case Sym.struct_specifier: return namedType("struct");
		case Sym.union_specifier: return namedType("union");
		case Sym.enum_specifier: return namedType("enum");


		default: break;
	}
	return null;
}

/// Qualifiers for a C declaration
struct CQuals {
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

	string toString() const {
		string result;
		if (inline) result ~= "pragma(inline, true) ";
		if (extern_) result ~= "extern ";
		// C's static meaning 'private to the translation unit' doesn't exist in D
		// The closest thing is `private extern(D)` which restricts access and
		// avoids name conflicts, but still emits a symbol
		// However, we don't do `extern(D)` since that changes abi as well
		if (staticGlobal) result ~= "private ";
		if (staticFunc) result ~= "static ";
		// Also: static can also mean 'array of length at least X'
		// D has transitive const unlike C
		// it must surround the primitive type, e.g. `const int*` => `const(int)*`
		// if (const_) result ~= "const ";
		if (auto_) result ~= "auto ";
		if (volatile_) result ~= "/*volatile*/ ";
		if (restrict) result ~= "/*restrict*/ ";
		if (atomic) result ~= "/*atomic*/ ";
		return result;
	}
}

/// Look for type qualifiers in this node, set the corresponding booleans
/// Unknown qualifiers are ignored, though the function is supposed to catch all of them.
/// Returns: `true` on success
bool tryParseTypeQual(ref TranslationContext ctu, ref Node node, ref CQuals quals) {
	if (node.typeEnum == Sym.type_qualifier || node.typeEnum == Sym.storage_class_specifier) {
		switch(node.children[0].typeEnum) {
			case Sym.anon_const: quals.const_ = true; return true;
			case Sym.anon_volatile: quals.volatile_ = true; return true;
			case Sym.anon_restrict: quals.restrict = true; return true;
			case Sym.anon__Atomic: quals.atomic = true; return true;
			case Sym.anon_extern: quals.extern_ = true; return true;
			case Sym.anon_static:
				if (ctu.inFunction) {
					quals.staticFunc = true;
				} else {
					quals.staticGlobal = true;
				}
				return true;
			case Sym.anon_auto: quals.auto_ = true; return true;
			case Sym.anon_register: quals.register = true; return true;
			case Sym.anon_inline: quals.inline = true; return true;
			default: break;
		}
	}
	return false;
}

/// Parse declarations
/// Often a node represents a single declaration, but in case of e.g. `int x, *y;` they are split up into two
/// declarations since in D you can't declare differently typed variables in one declaration
Decl[] parseDecls(ref TranslationContext ctu, ref Node node, ref InlineType[] inlineTypes) {
	if (auto typeNode = node.childField("type")) {
		const oldLen = inlineTypes.length;
		auto primitiveType = parseTypeNode(ctu, *typeNode, inlineTypes);

		// there may be multiple type_qualifier fields
		// if (auto qualNode = node.childField("type_qualifier"))
		CQuals quals;
		foreach(ref c; node.children) {
			cast(void) tryParseTypeQual(ctu, c, quals);
		}
		CType baseType = CType.named(primitiveType);
		baseType.setConst(quals.const_);
		Decl[] result;
		foreach(ref c; node.children) {
			if (&c == typeNode) {
				// the type field may pass as a declarator, resulting in e.g.
				// T* t; => T T; T* t;
				continue;
			}
			Decl decl = Decl(quals.toString(), baseType, "", "");
			if (parseCtype(ctu, c, decl, inlineTypes)) {
				if (primitiveType.length == 0 && inlineTypes.length > oldLen && inlineTypes[$-1].name.length == 0) {
					inlineTypes[$-1].name = ctu.uniqueIdentifier(decl.identifier);
					decl.type.setName(inlineTypes[$-1].name);
				}
				result ~= decl;
			}
		}

		// parameters can have no identifier, e.g. `foo(int named, float)`
		// if this is called for a parameter declaration, you still want to get an anonymous declaration back
		// the only exception is empty parameter lists, which in C are declared like `void main(void)`
		if (result.length == 0 && primitiveType != "void") {
			result = [Decl(quals.toString(), baseType, "", "")];
		}
		return result;
	}
	return null;
}

/// From a decl, parse the type and identifier
/// identifier: gets set to identifier of decl
bool parseCtype(ref TranslationContext ctu, ref Node node, ref Decl decl, ref InlineType[] inlineTypes) {
	switch(node.typeEnum) {
		case Sym.init_declarator:
			if (auto valueNode = node.childField("value")) {
				translateNode(ctu, *valueNode);
				decl.initializer = valueNode.output();
			}
			goto case;
		case Sym.parenthesized_declarator:
			// (*(x));
			foreach(ref c; node.children) {
				if (c.typeEnum != Sym.comment && c.typeEnum != Sym.anon_LPAREN) {
					parseCtype(ctu, c, decl, inlineTypes);
					return true;
				}
			}
			break;
		case Sym.abstract_function_declarator:
		case Sym.function_declarator:
			Decl[] paramDecls = [];
			if (auto paramNode = node.childField("parameters")) {
				foreach(ref c; paramNode.children) {
					if (c.typeEnum == Sym.parameter_declaration) {
						auto d = parseDecls(ctu, c, inlineTypes);
						paramDecls ~= d;
					} else if (c.typeEnum == Sym.variadic_parameter) {
						// variadic args
						paramDecls ~= Decl("", CType.named("..."), "", "");
					}
					//import dbg; dprint(c.source);
				}
			}
			if (auto declNode = node.childField("declarator")) {
				decl.type = CType.funcDecl(decl.type, paramDecls);
				if (node.typeEnum == Sym.abstract_function_declarator) {
					decl.type = CType.pointer(decl.type);
				}
				parseCtype(ctu, *declNode, decl, inlineTypes);
			}
			return true;
		case Sym.alias_field_identifier: // int x;
		case Sym.alias_type_identifier: // typedef X Y;
		case Sym.identifier: // ??
			decl.identifier = replaceIdentifier(node.source);
			return true;
		// pointer/array declarators always have a declarator field.
		// abstract declarators maybe not, for example: void foo(float*, float[])
		// however, nested pointers/array (`float[][]` or `float**`) do have it until you reach the 'leaf'
		case Sym.pointer_declarator:
		case Sym.abstract_pointer_declarator:
			decl.type = CType.pointer(decl.type);
			if (auto c = node.firstChildType(Sym.type_qualifier)) {
				if (c.source == "const" && decl.type.next[0].isConst) {
					decl.type.setConst();
					decl.type.next[0].setConst(false); // D has transitive const, so no need for `const(const(int)*)`
				}
			}
			if (auto c = node.childField("declarator")) {
				parseCtype(ctu, *c, decl, inlineTypes);
			}
			return true;
		case Sym.array_declarator:
		case Sym.abstract_array_declarator:
			// static array
			if (auto sizeNode = node.childField("size")) {
				translateNode(ctu, *sizeNode);
				decl.type = CType.array(decl.type, sizeNode.output);
				if (auto c1 = node.childField("declarator")) {
					parseCtype(ctu, *c1, decl, inlineTypes);
				}
			} else {
				// unsized array is simply a pointer
				if (auto c1 = node.childField("declarator")) {
					decl.type = CType.pointer(decl.type);
					parseCtype(ctu, *c1, decl, inlineTypes);
				}
			}
			return true;
		default:
			break;
	}
	return false;
}

package
struct CType {
	enum Tag {
		none,
		pointer,
		staticArray,
		funcDecl,
		named,
	}
	/// For a pointer / array, the element type.
	/// For a function, the return type.
	/// Always length 1.
	CType[] next = [];
	Decl[] params; // parameter declarations
	union {
		string name; // name of decl for parameters
		string countExpr; // for static arrays. Note: need not be a number literal
	}
	Tag tag = Tag.none;
	bool isConst = false;
	enum none = CType.init;
	bool opCast() const {
		return tag != Tag.none;
	}
	bool isFunction() const {return tag == Tag.funcDecl;}
	bool isStaticArray() const {return tag == Tag.staticArray;}

	void setConst(bool value = true) {
		isConst = value;
	}

	// replace the eventual name of this type
	// used for giving anonymous structs/unions/enums a name afterwards, based on variable names
	void setName(string name) {
		if (tag == Tag.named) {
			this.name = name;
		} else if (next.length > 0) {
			next[0].setName(name);
		} else {

		}
	}

	static CType pointer(CType to) {
		CType result;
		result.next = [to];
		result.tag = Tag.pointer;
		return result;
	}

	static CType array(CType elem, string count) {
		CType result;
		result.next = [elem];
		result.countExpr = count;
		result.tag = Tag.staticArray;
		return result;
	}

	static CType named(string name) {
		CType result;
		result.name = name;
		result.tag = Tag.named;
		return result;
	}

	static CType funcDecl(CType ret, Decl[] params) {
		CType result;
		result.next = [ret];
		result.params = params;
		result.tag = Tag.funcDecl;
		return result;
	}

	void toString(O)(ref O sink) const scope {
		import bops.tostring: toStringM, fmtRange;
		switch(tag) {
			case Tag.pointer:
				if (next[0].tag == Tag.funcDecl) {
					toStringM(sink, next[0].next[0], " function(", fmtRange(next[0].params, ", "), ")");
				} else {
					if (isConst) {
						toStringM(sink, "const(", next[0], "*)");
					} else {
						toStringM(sink, next[0], "*");
					}
				}
				break;
			case Tag.staticArray:
				toStringM(sink, next[0], "[", countExpr, "]");
				break;
			case Tag.funcDecl:
				toStringM(sink, next[0], "(", params, ")");
				break;
			case Tag.named:
				if (isConst) {
					toStringM(sink, "const(", name, ")");
				} else {
					toStringM(sink, name);
				}
				break;
			case Tag.none:
				toStringM(sink, "none");
				break;
			default:
				break; // return "errType";
		}
	}
}

unittest {
	import bops.test: assertToString;
	assertToString(CType.array(CType.array(CType.named("float"), "2"), "10"), "float[2][10]");
	assertToString(CType.pointer(CType.pointer(CType.named("ab"))), "ab**");
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
string replacePrimitiveType(return scope string original) {
	switch(original) {
		static foreach(p; basicTypeMap) {
			case p[0]: return p[1];
		}
		case "FIXME": return null; // remove string switch
		default: return original;
	}
}

unittest {
	assert(replacePrimitiveType("int16_t") == "short");
}