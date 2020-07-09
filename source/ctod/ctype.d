/**
Translate C types
*/
module ctod.ctype;

import std.stdio, std.range, std.algorithm;
import ctod;
import tree_sitter.wrapper;

/// Declaration
struct Decl {
	string storageClasses;
	CType type;
	string identifier = ""; /// name of variable / function
	string initializer = ""; /// expression that initializes the variable

	string toString() const {
		import std.string: format;
		string result = storageClasses;

		// D declarations are usually separated as [type] followed by [identifier], but there is one exception:
		// extern functions. (functions with bodies are handled separately, and function pointers have the name on the right
		if (type.tag == CType.Tag.funcDecl) {
			result ~= format("%s %s(%(%s, %))", type.next[0].toString(), identifier, type.params);
		} else {
			result ~= type.toString();
			if (identifier.length > 0) {
				result ~= " " ~ identifier;
			}
			if (initializer.length > 0) {
				result ~= " = " ~ initializer;
			}
		}
		return result;
	}
}

/// inline type
struct InlineType {
	string keyword;
	string name = null;
	string body_;
	string toString() const {
		return keyword ~ " " ~ name ~ " " ~ body_;
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
	switch(node.type) {
		case "primitive_type":
			return replacePrimitiveType(node.source);
		case "type_identifier":
			return replaceIdentifier(node.source);
		case "sized_type_specifier":
			bool signed = true;
			int longCount = 0;
			string primitive = "";
			foreach(ref c; node.children) {
				switch (c.type) {
					case "comment": continue;
					case "unsigned":
						signed = false;
						break;
					case "long":
						longCount++;
						break;
					case "primitive_type":
						primitive = replacePrimitiveType(c.source);
						break;
					case "short": // not a primitive_type apparently
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
				switch(primitive) {
					case "char": primitive = "ubyte";
					case "c_long": primitive = "c_ulong";
					default: primitive = "u" ~ primitive;
				}
			}
			return primitive;
		case "struct_specifier":
		case "union_specifier":
		case "enum_specifier":
			const string keyword = node.type[0..$-"_specifier".length].idup;
			auto nameNode = node.childField("name");
			//import dbg; dprint(node.source);
			if (auto c = node.childField("body")) {
				translateNode(ctu, *c);
				string name = nameNode ? nameNode.source : null; //ctu.uniqueIdentifier();
				inlineTypes ~= InlineType(keyword, name, c.output);
				return name;
			} else if (nameNode) {
				inlineTypes ~= InlineType(keyword, nameNode.source, ";");
				return nameNode.source;
			}
			return "@@err"~__LINE__.stringof;
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

	bool static_;
	bool extern_;
	bool auto_;
	bool inline;
	bool register;

	string toString() const {
		string result;
		if (inline) result ~= "pragma(inline, true) ";
		if (extern_) result ~= "extern ";
		if (static_) result ~= "static ";
		// D has transitive const unlike C
		// it must surround the primitive type, e.g. const int* => const(int)*
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
bool tryParseTypeQual(ref TranslationContext ctu, ref Node node, ref CQuals quals) {
	if (node.type == "type_qualifier") switch (node.source) {
		case "const": quals.const_ = true; return true;
		case "volatile": quals.volatile_ = true; return true;
		case "restrict": quals.restrict = true; return true;
		case "_Atomic": quals.atomic = true; return true;
		default: break;
	}
	if (node.type == "storage_class_specifier") switch (node.source) {
    	case "extern": quals.extern_ = true; return true;
    	case "static": quals.static_ = true; return true;
    	case "auto": quals.auto_ = true; return true;
    	case "register": quals.register = true; return true;
    	case "inline": quals.inline = true; return true;
		default: break;
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
	switch(node.type) {
		case "init_declarator":
			if (auto valueNode = node.childField("value")) {
				translateNode(ctu, *valueNode);
				decl.initializer = valueNode.output();
			}
			goto case;
		case "parenthesized_declarator":
			// (*(x));
			foreach(ref c; node.children) {
				if (c.type != "comment" && c.type != "(") {
					parseCtype(ctu, c, decl, inlineTypes);
					return true;
				}
			}
			break;
		case "abstract_function_declarator":
		case "function_declarator":
			Decl[] paramDecls = [];
			if (auto paramNode = node.childField("parameters")) {
				foreach(ref c; paramNode.children) {
					if (c.type == "parameter_declaration") {
						auto d = parseDecls(ctu, c, inlineTypes);
						paramDecls ~= d;
					}
				}
			}
			if (auto declNode = node.childField("declarator")) {
				decl.type = CType.funcDecl(decl.type, paramDecls);
				if (node.type == "abstract_function_declarator") {
					decl.type = CType.pointer(decl.type);
				}
				parseCtype(ctu, *declNode, decl, inlineTypes);
			}
			return true;
		case "field_identifier": // int x;
		case "type_identifier": // typedef X Y;
		case "identifier": // ??
			decl.identifier = replaceIdentifier(node.source);
			return true;
		// pointer/array declarators always have a declarator field.
		// abstract declarators maybe not, for example: void foo(float*, float[])
		// however, nested pointers/array (`float[][]` or `float**`) do have it until you reach the 'leaf'
		case "pointer_declarator":
		case "abstract_pointer_declarator":
			decl.type = CType.pointer(decl.type);
			if (auto c = node.firstChildType("type_qualifier")) {
				if (c.source == "const" && decl.type.next[0].isConst) {
					decl.type.setConst();
					decl.type.next[0].setConst(false); // D has transitive const, so no need for `const(const(int)*)`
				}
			}
			if (auto c = node.childField("declarator")) {
				parseCtype(ctu, *c, decl, inlineTypes);
			}
			return true;
		case "array_declarator":
		case "abstract_array_declarator":
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

	string toString() const {
		import std.string: format;
		with(Tag) switch(tag) {
			case pointer:
				if (next[0].tag == Tag.funcDecl) {
					return format("%s function(%(%s, %))", next[0].next[0], next[0].params);
				} else {
					return format(isConst ? "const(%s*)" : "%s*", next[0]);
				}
			case staticArray:
				return format("%s[%s]", next[0], countExpr);
			//case funcDef://				return
			case funcDecl:
				return format("%s FUNC(%(%s, %))", next[0], params);
			case named:
				return format(isConst ? "const(%s)" : "%s", name);
			case none:
				return "none";
			default: return "errType";
		}
	}
}

unittest {
	assert(CType.array(CType.array(CType.named("float"), "2"), "10").toString() == "float[2][10]");
	assert(CType.pointer(CType.pointer(CType.named("ab"))).toString() == "ab**");
}

/// replace C primitive types
string replacePrimitiveType(string original) {
	switch(original) {
		case "int8_t": return "byte";
		case "uint8_t": return "ubyte";
		case "int16_t": return "short";
		case "uint16_t": return "ushort";
		case "int32_t": return "int";
		case "uint32_t": return "uint";
		case "int64_t": return "long";
		case "uint64_t": return "ulong";

		case "char": return "char";
		case "short": return "short";
		case "int": return "int";

		default: return original;
	}
}
