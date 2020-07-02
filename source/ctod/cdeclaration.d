module ctod.cdeclaration;

import ctod;
import tree_sitter.wrapper;

bool tryTranslateDeclaration(ref TranslationContext ctu, ref Node node) {
	const nodeSource = ctu.source[node.start..node.end];
	switch (node.type) {
		case "field_identifier":
		case "identifier":
			if (string s = replaceIdentifier(nodeSource)) {
				return node.replace(s);
			}
			return true;
		//case "function_definition":
        case "parameter_declaration":
        case "field_declaration": // struct field
		case "declaration": // global / local variable
            Decl[] decls = parseDecls(ctu, node);
            string result = "";
            string suffix = node.type == "parameter_declaration" ? "" : ";";
            foreach(d; decls) {
                result ~= d.toString() ~ suffix;
            }
            node.replace(result);
            /+
			if (auto c = node.childField("type")) {
				if (auto s = parseTypeNode(ctu, *c)) {
					c.replace(s);
				}
			}
			foreach(ref c; node.children) {
				switch(c.type) {
					case "type_qualifier":
						break;
					default:
						break;
				}
			}
            +/
			break;
		case "storage_class_specifier":
			//"extern"
			//"static"
			//"auto"
			//"register"
			//"inline"
			if (!node.inFuncBody) {
				if (node.source == "static") {
					return node.replace("private");
				}
                if (node.source == "inline") {
					return node.replace("pragma(inline, true)");
				}
			}
			break;
		case "initializer_list":
			if (auto c = node.firstChildType("{")) {
				c.replace("[");
			}
			if (auto c = node.firstChildType("}")) {
				c.replace("]");
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