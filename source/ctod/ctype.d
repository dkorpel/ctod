/**
Translate C types
*/
module ctod.ctype;

import std.stdio, std.range, std.algorithm;
import ctod;
import tree_sitter.wrapper;

// int (*f[3][4])(void))
// int function()[3][4]

/// Declaration
struct Decl {
	string storageClasses;
	CType type;
	string identifier = "";
	string initializer = "";

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

/// C declarations are declared this way:
/// First, a 'base type' which is a primitive type or identifier
/// Then, one or more expressions that should evaluate to a value of 'base type'

string parseTypeNode(ref TranslationContext ctu, ref Node node) {
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
					default: break;
				}
			}
			if (longCount > 0 && primitive == "double") {
				return "real";
			}
			if (longCount == 1 && primitive == "") {
				primitive = "int";
			}
			if (longCount == 2 && primitive == "") {
				primitive = "long";
			}
			if (!signed && primitive.length && primitive[0] != 'u') {
				primitive = "u" ~ primitive;
			}
			return primitive;
		case "struct_specifier":
			if (auto c = node.childField("name")) {
				return c.source;
			}
			return "@@errstruct";
		default: break;
	}
	return null;
}

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
		if (auto_) result ~= "pragma(inline, true) ";
		if (volatile_) result ~= "/*volatile*/ ";
		if (restrict) result ~= "/*restrict*/ ";
		if (atomic) result ~= "/*atomic*/ ";
		return result;
	}
}

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
Decl[] parseDecls(ref TranslationContext ctu, ref Node node) {
	if (auto typeNode = node.childField("type")) {
		auto primitiveType = parseTypeNode(ctu, *typeNode);

		// there may be multiple type_qualifier fields
		// if (auto qualNode = node.childField("type_qualifier"))
		CQuals quals;
		foreach(ref c; node.children) {
			cast(void) tryParseTypeQual(ctu, c, quals);
		}
		if (quals.const_) {
			primitiveType = "const(" ~ primitiveType ~ ")";
		}
		CType baseType = CType.named(primitiveType);
		Decl[] result;
		foreach(ref c; node.children) {
			Decl decl = Decl(quals.toString(), baseType, "", "");
			if (parseCtype(ctu, c, decl)) {
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
	} else {
		import dbg; dprint(node.source, "has no type field");
	}
	return null;
}

/// parse parameter list node, turn into decls
Decl[] parseParameters(ref TranslationContext ctu, ref Node node) {
	assert(node.type == "parameter_list");
	Decl[] result;
	foreach(ref c; node.children) {
		if (c.type == "parameter_declaration") {
			result ~= parseDecls(ctu, c);
		}
	}
	return result;
}

/// From a decl, parse the type and identifier
/// identifier: gets set to identifier of decl
bool parseCtype(ref TranslationContext ctu, ref Node node, ref Decl decl) {
	switch(node.type) {
		// (*(x));
		case "init_declarator":
			if (auto valueNode = node.childField("value")) {
				translateNode(ctu, *valueNode);
				decl.initializer = valueNode.output();
			}
			goto case;
		case "parenthesized_declarator":
			foreach(ref c; node.children) {
				if (c.type != "comment" && c.type != "(") {
					parseCtype(ctu, c, decl);
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
						paramDecls ~= parseDecls(ctu, c);
					}
				}
			}
			if (auto declNode = node.childField("declarator")) {
				decl.type = CType.funcDecl(decl.type, paramDecls);
				if (node.type == "abstract_function_declarator") {
					decl.type = CType.pointer(decl.type);
				}
				parseCtype(ctu, *declNode, decl);
			}
			return true;
		case "field_identifier":
		case "identifier":
			decl.identifier = replaceIdentifier(node.source);
			return true;
		case "parameter_list":
			// TODO
			break;
		case "pointer_declarator":
			if (auto c = node.childField("declarator")) {
				decl.type = CType.pointer(decl.type);
				parseCtype(ctu, *c, decl);
				return true;
			}
			break;
		case "abstract_array_declarator":
		case "abstract_pointer_declarator":
			// void foo(float*, float[])
			decl.type = CType.pointer(decl.type);
			return true;
		case "array_declarator":
			// static array
			if (auto sizeNode = node.childField("size")) {
				translateNode(ctu, *sizeNode);
				if (auto c1 = node.childField("declarator")) {
					decl.type = CType.array(decl.type, sizeNode.output);
					parseCtype(ctu, *c1, decl);
					return true;
				}
			} else {
				// unsized array is simply a pointer
				if (auto c1 = node.childField("declarator")) {
					decl.type = CType.pointer(decl.type);
					parseCtype(ctu, *c1, decl);
					return true;
				}
			}
			break;
		/+case "struct_specifier":
			if (auto c1 = node.childField("name")) {
				return CType.named(replaceIdentifier(c1.source));
			}
			break;
		+/
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
	CType[] next = [];
	Decl[] params; // parameter declarations
	union {
		string name; // name of decl for parameters
		string countExpr; // for static arrays. Note: not per se a number literal
	}
	Tag tag = Tag.none;
	enum none = CType.init;
	bool opCast() const {
		return tag != Tag.none;
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
					return format("%s*", next[0]);
				}
			case staticArray:
				return format("%s[%s]", next[0], countExpr);
			//case funcDef://				return
			case funcDecl:
				return format("%s FUNC(%(%s, %))", next[0], params);
			case named:
				return name;
			case none:
				return "none";
			default: return "errType";
		}
	}
}

unittest {
	assert(CType.array(CType.array(CType.named("float"), "2"), "10").toString() == "float[2][10]");
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
