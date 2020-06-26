/**
Translate C types
*/
module ctod.ctype;

import std.stdio;
import ctod;
import tree_sitter.wrapper;

// int (*f[3][4])(void))
// int function()[3][4]
//case "function_definition":

struct Decl {
	CType type;
	string identifier;
}

/// C declarations are declared this way:
/// First, a 'base type' which is a primitive type or identifier
/// Then, one or more expressions that should evaluate to a value of 'base type'

string parseTypeNode(ref TranslationContext ctu, ref Node node) {
	switch(node.type) {
		case "primitive_type":
			return replacePrimitiveType(node.source);
			//baseType = CType.named(c.source);
			break;
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

Decl[] parseDecls(ref TranslationContext ctu, ref Node node) {
	CType baseType;
	if (auto c = node.childField("type")) {
		auto res = parseTypeNode(ctu, *c);
	}
	if (auto c = node.childField("type_qualifier")) {
		// const
	}

	if (auto c = node.childField("declarator")) {

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

CType parseCtype(ref TranslationContext ctu, ref Node node) {
	switch(node.type) {
		case "abstract_function_declarator":
		case "function_declarator":
			if (auto c = node.childField("type")) {
				CType ret = parseCtype(ctu, *c);
				if (auto d = node.childField("declarator")) {

					CType next = parseCtype(ctu, node);
				}
			}
			break;

		case "parameter_list":

			break;
		case "pointer_declarator":
			if (auto c = node.childField("declarator")) {
				CType next = parseCtype(ctu, node);
			}
			break;
		case "array_declarator":
			if (auto sizeNode = node.childField("size")) {
				translateNode(ctu, *sizeNode);
				CType next;
				if (auto c1 = node.childField("declarator")) {
					return CType.array(parseCtype(ctu, *c1), sizeNode.output);
				}
			}
			break;
		case "struct_specifier":
			if (auto c1 = node.childField("name")) {
				return CType.named(replaceIdentifier(c1.source));
			}
			break;
		default:
			break;
	}
	return CType.init;
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
	union {
		string name; // for identifier types
		string countExpr; // for static arrays. Note: not per se a number literal
	}
	Tag tag = Tag.none;

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

	static CType funcDecl(CType ret, CType[] args) {
		CType result;
		result.next = [ret] ~ args;
		result.tag = Tag.funcDecl;
		return result;
	}

	string toString() const {
		import std.string: format;
		with(Tag) switch(tag) {
			case pointer:
				if (next[0].tag == Tag.funcDecl) {
					return format("%s function(%(%s, %))", next[0].next[0], next[0].next[1..$]);
				} else {
					return format("%s*", next[0]);
				}
			case staticArray:
				return format("%s[%s]", next[0], countExpr);
			//case funcDef://				return
			case funcDecl:
				return format("%s FUNC(%(%s, %))", next[0], next[1..$]);
			case named:
				return name;
			default: return "errType";
		}
	}
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
