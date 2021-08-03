module ctod.cdeclaration;

import ctod;
import tree_sitter.wrapper;

/// Returns: true if a declaration was matched and replaced
bool tryTranslateDeclaration(ref TranslationContext ctu, ref Node node) {
	const nodeSource = ctu.source[node.start..node.end];

	InlineType[] inlinetypes;

	bool translateDecl(string suffix) {
		Decl[] decls = parseDecls(ctu, node, inlinetypes);
		string result = "";
		foreach(s; inlinetypes) {
			if (s.hasBody()) {
				result ~= s.toString();
			}
		}
		foreach(d; decls) {
			result ~= d.toString() ~ suffix;
			ctu.registerDecl(d);
		}
		node.replace(result);
		return true;
	}

	switch (node.type) {
		case "field_identifier":
		case "type_identifier":
		case "identifier":
			if (string s = replaceIdentifier(nodeSource)) {
				return node.replace(s);
			}
			return true;
		case "function_definition":
			if (node.type == "function_definition") {
				if (auto bodyNode = node.childField("body")) {
					ctu.enterFunction("???");
					translateNode(ctu, *bodyNode);
					ctu.leaveFunction();
					return translateDecl(" " ~ bodyNode.output());
				}
			}
			break;
		case "parameter_declaration":
			return translateDecl("");
		case "field_declaration": // struct / union field
			if (auto bitNode = node.firstChildType("bitfield_clause")) {
				translateNode(ctu, *bitNode);
				node.append("/+"~bitNode.output~" !!+/");
			}
			return translateDecl(";");
		case "declaration": // global / local variable
			return translateDecl(";");
		case "type_definition":
			Decl[] decls = parseDecls(ctu, node, inlinetypes);
			string result = ""; // todo: anonymous types
			foreach(s; inlinetypes) {
				result ~= s.toString();
			}
			foreach(d; decls) {
				if (d.type == CType.named(d.identifier)) {
					// result ~= "/+alias " ~ d.toString() ~ ";+/";
				} else {
					result ~= "alias " ~ d.toString() ~ ";";
				}
			}
			node.replace(result);
			return true;
		case "initializer_list":
			// TODO: check if not struct initializer
			if (true) {
				if (auto c = node.firstChildType("{")) {
					c.replace("[");
				}
				if (auto c = node.firstChildType("}")) {
					c.replace("]");
				}
			}
			break;
		default: break;
	}
	return false;
}

/// modify C identifiers that are keywords in D
string replaceIdentifier(string s) {
	switch(s) {
		static foreach(kw; dKeywords) {
			case kw: return kw ~ "_";
		}
		/+
		case "in": return "in_";
		case "out": return "out_";
		case "version": return "version_";
		case "debug": return "debug_";
		case "deprecated": return "deprecated_";

		// unlikely but possible
		case "scope": return "scope_";
		case "foreach": return "foreach_";
		case "pragma": return "pragma_";
		+/
		default: return s;
	}
}

// C identifiers that are keywords in D
// Does not include keywords that are in both C and D (static, if, switch) or have similar meaning (null, true, assert)
immutable dKeywords = [
	"abstract",
	"alias",
	"align",
	"asm",
	"auto",
	"bool",
	"byte",
	"cast",
	"catch",
	"cdouble",
	"cent",
	"cfloat",
	"char",
	"class",
	"creal",
	"dchar",
	"debug",
	"delegate",
	"deprecated",
	"export",
	"final",
	"finally",
	"foreach",
	"foreach_reverse",
	"function",
	"idouble",
	"ifloat",
	"immutable",
	"import",
	"in",
	"inout",
	"interface",
	"invariant",
	"ireal",
	"is",
	"lazy",
	"macro",
	"mixin",
	"module",
	"new",
	"nothrow",
	"out",
	"override",
	"package",
	"pragma",
	"private",
	"protected",
	"public",
	"pure",
	"real",
	"ref",
	"scope",
	"shared",
	"super",
	"synchronized",
	"template",
	"this",
	"throw",
	"try",
	"typeid",
	"typeof",
	"ubyte",
	"ucent",
	"uint",
	"ulong",
	"unittest",
	"ushort",
	"version",
	"wchar",
	"with",
];