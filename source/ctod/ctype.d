/**
Translate C types
*/
module ctod.ctype;

nothrow @safe:

import ctod.tree_sitter;
import ctod.translate;
import ctod.cdeclaration;
import ctod.cexpr;

/// Declaration
struct Decl {
	string storageClasses;
	CType type = CType.none;
	string identifier = ""; /// name of variable / function
	string initializer = ""; /// expression that initializes the variable

pure nothrow:

	string toString() const {
		string result = storageClasses;
		// D declarations are usually separated as [type] followed by [identifier], but there is one exception:
		// extern functions. (functions with bodies are handled separately, and function pointers have the name on the right
		if (type.tag == CType.Tag.funcDecl) {
			// result ~= format("%s %s(%(%s, %))", type.next[0].toString(), identifier, type.params);
			result ~= fmtFunction(type.next[0], identifier, type.params);
		} else {
			result ~= type.toString();
			if (identifier.length > 0) {
				result ~= " ";
				result ~= identifier;
			}
			result ~= this.initializerAssign();
		}
		return result;
	}

	string initializerAssign() const {
		if (initializer.length > 0) {
			return " = " ~ initializer;
		}
		return "";
	}

	bool opEquals(const Decl other) const scope {
		return storageClasses == other.storageClasses && type == other.type
			&& identifier == other.identifier && initializer == other.initializer;
	}

	///
	enum none = Decl.init;
	///
	bool opCast() const scope {return cast(bool) type;}
}

unittest {
	assert(Decl("inline ", CType.named("int"), "x", "3").toString() ==  "inline int x = 3");
}

/// Generate D function type syntax
private string fmtFunction(const CType retType, string name, const Decl[] params) pure {
	string result = retType.toString();
	result ~= " ";
	result ~= name;
	result ~= "(";
	foreach(i, par; params) {
		if (i > 0) {
			result ~= ", ";
		}
		result ~= par.toString();
	}
	result ~= ")";
	return result;
}

/// A type in the middle of an expression.
/// C allows to e.g. define a struct inside a parameter list.
struct InlineType {
	string keyword;
	string name = null;
	string body_;

pure nothrow:

	bool hasBody() const {return body_.length > 0;}
	string toString() const {
		return keyword ~ " " ~ name ~ (hasBody() ? " " ~ body_ : ";");
	}
}

/// Generate alias declarations to put enum members into the global namespace
/// C enums don't have a scope for their members
private string enumMemberAliases(string enumName, ref Node c) {
	string res = "\n";
	foreach(ref c2; c.children) {
		if (c2.typeEnum == Sym.enumerator) {
			string mem = c2.childField(Field.name).source;
			res ~= "alias " ~ mem ~ " = " ~ enumName ~ "." ~ mem ~ ";\n";
		}
	}
	return res;
}

/// C declarations are declared this way:
/// First, a 'base type' which is a primitive type or identifier
/// Then, one or more expressions that should evaluate to a value of 'base type'
///
/// Note: the base-type can be an (anonymous) struct / union / enum, which is not allowed in D.
/// Therefor, the second return value is a type declaration that the primitive type depends on.
///
/// Returns: [primitive type, dependent type]
string parseTypeNode(ref CtodCtx ctx, ref Node node, ref InlineType[] inlineTypes, bool keepOpaque = false) {

	// keyword = struct, union or enum
	string namedType(string keyword) {
		auto nameNode = node.childField(Field.name);
		if (auto c = node.childField(Field.body_)) {
			translateNode(ctx, *c);
			string name = nameNode ? nameNode.source : null;

			// Put enum members into the global scope with aliases
			if (name && c.typeEnum == Sym.enumerator_list) {
				c.append(enumMemberAliases(name, *c));
			}

			inlineTypes ~= InlineType(keyword, name, c.output());
			return name;
		} else if (nameNode) {
			if (keepOpaque) {
				return null;
			}
			// Don't emit bodyless types, assume they were defined before
			// inlineTypes ~= InlineType(keyword, nameNode.source, /*body*/ "");
			return nameNode.source;
		}
		return null;
	}

	switch(node.typeEnum) {
		case Sym.type_descriptor:
			if (auto c = node.childField(Field.type)) {
				return parseTypeNode(ctx, *c, inlineTypes, keepOpaque);
			}
			break;
		case Sym.primitive_type:
			return ctodPrimitiveType(node.source);
		case Sym.alias_type_identifier:
			if (node.source == "wchar_t") {
				ctx.needsWchar = true;
				return node.source;
			} else if (node.source == "bool") {
				ctx.needsCbool = true;
				return "c_bool";
			} else {
				// int8_t is recognized as a primitive type, but __u8 is a type identifier,
				// so also do ctodPrimitiveType here.
				const replacement = ctodPrimitiveType(node.source);
				if (replacement == node.source) {
					// no replacement to a D-type, so escape keywords (out => out_)
					return translateIdentifier(node.source);
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
						primitive = ctodPrimitiveType(c.source);
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
				ctx.needsClong = true;
			} else if (longCount == 2 && primitive == "") {
				primitive = "long";
			} else if (!signed && primitive == "") {
				primitive = "int";
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

pure nothrow:

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
bool tryParseTypeQual(ref CtodCtx ctx, ref Node node, ref CQuals quals) {
	if (node.typeEnum == Sym.type_qualifier || node.typeEnum == Sym.storage_class_specifier) {
		switch(node.children[0].typeEnum) {
			case Sym.anon_const: quals.const_ = true; return true;
			case Sym.anon_volatile: quals.volatile_ = true; return true;
			case Sym.anon_restrict: quals.restrict = true; return true;
			case Sym.anon__Atomic: quals.atomic = true; return true;
			case Sym.anon_extern: quals.extern_ = true; return true;
			case Sym.anon_static:
				if (ctx.inFunction) {
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
Decl[] parseDecls(ref CtodCtx ctx, ref Node node, ref InlineType[] inlineTypes) {
	auto typeNode = node.childField(Field.type);
	if (!typeNode) {
		return null;
	}
	const oldLen = inlineTypes.length;
	auto primitiveType = parseTypeNode(ctx, *typeNode, inlineTypes);

	// there may be multiple type_qualifier fields
	// if (auto qualNode = node.childField(Field.type_qualifier))
	CQuals quals;
	foreach(ref c; node.children) {
		cast(void) tryParseTypeQual(ctx, c, quals);
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
		if (parseCtype(ctx, c, decl, inlineTypes)) {
			if (primitiveType.length == 0 && inlineTypes.length > oldLen && inlineTypes[$-1].name.length == 0) {
				inlineTypes[$-1].name = ctx.uniqueIdentifier(decl.identifier);
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

/// Returns: number of elements in initializer_list
uint initializerLength(ref Node node, ref string firstElement) {
	firstElement = null;
	uint commaCount = 0;
	foreach(ref e; node.children) {
		if (e.typeEnum == Sym.comment || e.typeEnum == Sym.anon_LBRACE || e.typeEnum == Sym.anon_RBRACE) {
			continue;
		}
		if (e.typeEnum == Sym.anon_COMMA) {
			commaCount++;
		}
		if (!firstElement) {
			firstElement = e.source;
		}
	}
	return commaCount + (firstElement != null); // == 0 && firstElement == "0";
}

/// Simple int to string function to avoid `std.conv: text`, which is not yet available for WebAssembly
private string intToString(uint i) {
	if (i < 10) {
		return [cast(char) ('0' + i)];
	} else {
		return intToString(i / 10) ~ intToString(i % 10);
	}
}

unittest {
	assert(intToString(0) == "0");
	assert(intToString(9) == "9");
	assert(intToString(4790) == "4790");
}

/// From a decl, parse the type and identifier
/// identifier: gets set to identifier of decl
bool parseCtype(ref CtodCtx ctx, ref Node node, ref Decl decl, ref InlineType[] inlineTypes) {
	switch(node.typeEnum) {
		case Sym.init_declarator:
			if (auto declaratorNode = node.childField(Field.declarator)) {
				parseCtype(ctx, *declaratorNode, decl, inlineTypes);
			}
			if (auto valueNode = node.childField(Field.value)) {
				ctx.inDeclType = decl.type;
				translateNode(ctx, *valueNode);
				ctx.inDeclType = CType.none;
				if (valueNode.typeEnum == Sym.initializer_list) {
					string firstElem;
					const len = initializerLength(*valueNode, firstElem);
					// int x[4] = {0} => int[4] x = 0
					// Important because in function scope, all elements must be in [] initializer
					if (decl.type.isStaticArray()) {
						if (firstElem == "0" || len == 0) {
							valueNode.replace("0");
						}
					}
					// int x[] = {10, 20, 30} => int[3] x = [10, 20 30]
					// transform into static array with length inferred from initializer
					// Note: shouldn't be done in struct scope, but initializers are not valid in C there
					if (decl.type.isCArray()) {
						decl.type = CType.array(decl.type.next[0], intToString(len));
					}
				}
				decl.initializer = valueNode.output();
			}
			return true;
		case Sym.parenthesized_declarator:
			// (*(x));
			auto pc = getParenContent(&node);
			if (pc != &node) { // should not happen, but avoid endless recursion at all costs
				return parseCtype(ctx, *pc, decl, inlineTypes);
			}
			break;
		case Sym.abstract_function_declarator:
		case Sym.function_declarator:
			Decl[] paramDecls = [];
			if (auto paramNode = node.childField(Field.parameters)) {
				foreach(ref c; paramNode.children) {
					if (c.typeEnum == Sym.parameter_declaration) {
						auto d = parseDecls(ctx, c, inlineTypes);
						paramDecls ~= d;
					} else if (c.typeEnum == Sym.variadic_parameter) {
						// variadic args
						paramDecls ~= Decl("", CType.named("..."), "", "");
					}
				}
			}
			if (auto declNode = node.childField(Field.declarator)) {
				decl.type = CType.funcDecl(decl.type, paramDecls);
				if (node.typeEnum == Sym.abstract_function_declarator) {
					decl.type = CType.pointer(decl.type);
				}
				parseCtype(ctx, *declNode, decl, inlineTypes);
			}
			return true;
		case Sym.alias_field_identifier: // int x;
		case Sym.alias_type_identifier: // typedef X Y;
		case Sym.identifier: // ??
			decl.identifier = translateIdentifier(node.source);
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
			if (auto c = node.childField(Field.declarator)) {
				parseCtype(ctx, *c, decl, inlineTypes);
			}
			return true;
		case Sym.array_declarator:
		case Sym.abstract_array_declarator:
			// static array
			if (auto sizeNode = node.childField(Field.size)) {
				translateNode(ctx, *sizeNode);
				decl.type = CType.array(decl.type, sizeNode.output());
				if (auto c1 = node.childField(Field.declarator)) {
					parseCtype(ctx, *c1, decl, inlineTypes);
				}
			} else {
				// unsized array, might become a static array at global scope `int x[] = {3, 4, 5}`
				if (auto c1 = node.childField(Field.declarator)) {
					decl.type = CType.cArray(decl.type);
					parseCtype(ctx, *c1, decl, inlineTypes);
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
		unknown,
		pointer,
		staticArray,
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
	enum unknown = CType.fromTag(Tag.unknown);

pure nothrow:

	bool opCast() const scope {return tag != Tag.none;}
	bool isFunction() const {return tag == Tag.funcDecl;}
	bool isStaticArray() const {return tag == Tag.staticArray;}
	bool isCArray() const {return tag == Tag.cArray;}
	bool isPointer() const {return tag == Tag.pointer;}

	bool opEquals(const CType other) const scope {
		if (other.tag != this.tag) {
			return false;
		}
		if (other.isConst != this.isConst) {
			return false;
		}
		final switch(tag) {
			case Tag.cArray:
			case Tag.pointer:
				return this.next[0] == other.next[0];
			case Tag.staticArray:
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

	static CType cArray(CType to) {
		CType result;
		result.next = [to];
		result.tag = Tag.cArray;
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

	private static CType fromTag(Tag tag) {
		CType result;
		result.tag = tag;
		return result;
	}

	string toString() const {
		final switch(tag) {
			case Tag.cArray:
			case Tag.pointer:
				if (next[0].isFunction) {
					return fmtFunction(next[0].next[0], "function", next[0].params);
				} else {
					//format(isConst ? "const(%s*)" : "%s*", next[0]);
					return isConst ? ("const("~next[0].toString()~"*)") : next[0].toString() ~ "*";
				}
			case Tag.staticArray:
				return next[0].toString() ~ "[" ~ countExpr ~ "]";
			case Tag.funcDecl:
				return null; // format("%s FUNC(%(%s, %))", next[0], params);
			case Tag.named:
				return isConst ? ("const("~name~")") : name;
			case Tag.unknown:
				return "unknown";
			case Tag.none:
				return "none";
		}
	}
}

unittest {
	assert(CType.array(CType.array(CType.named("float"), "2"), "10").toString() == "float[2][10]");
	assert(CType.pointer(CType.pointer(CType.named("ab"))).toString() == "ab**");
}

/// Returns: `true` if `t` would not be default initialized to all zero like in C, but e.g. `char.init` or NaN
bool noZeroInitInD(const CType t) {
	if (t.name == "float" || t.name == "char" || t.name == "double" || t.name == "real") {
		return true;
	}
	if (t.isStaticArray()) {
		return noZeroInitInD(t.next[0]);
	}
	return false;
}

unittest {
	assert(noZeroInitInD(CType.named("float")));
	assert(noZeroInitInD(CType.array(CType.array(CType.named("char"), "2"), "10")));
	assert(!noZeroInitInD(CType.pointer(CType.named("float"))));
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
string ctodPrimitiveType(string s) {
	return mapLookup(basicTypeMap, s, s);
}

unittest {
	assert(ctodPrimitiveType("int16_t") == "short");
	assert(ctodPrimitiveType("float") == "float");
}
