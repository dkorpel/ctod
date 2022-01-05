module ctod.cdeclaration;

import ctod;
import tree_sitter.wrapper;
import bops.tostring: toGcString;

/// Returns: true if a declaration was matched and replaced
bool tryTranslateDeclaration(ref TranslationContext ctu, ref Node node) {
	InlineType[] inlinetypes;

	bool translateDecl(string suffix) {
		Decl[] decls = parseDecls(ctu, node, inlinetypes);
		string result = "";
		foreach(s; inlinetypes) {
			if (s.hasBody()) {
				result ~= s.toGcString();
			}
		}
		foreach(d; decls) {
			result ~= d.toGcString() ~ suffix;
			ctu.registerDecl(d);
		}
		node.replace(result);
		return true;
	}

	switch(node.typeEnum) {
		case Sym.alias_field_identifier:
		case Sym.alias_type_identifier:
		case Sym.identifier:
			if (string s = replaceIdentifier(node.source)) {
				return node.replace(s);
			}
			return true;
		case Sym.function_definition:
			if (node.typeEnum == Sym.function_definition) {
				if (auto bodyNode = node.childField("body")) {
					ctu.enterFunction("???");
					translateNode(ctu, *bodyNode);
					ctu.leaveFunction();
					return translateDecl(" " ~ bodyNode.output());
				}
			}
			break;
		case Sym.parameter_declaration:
			return translateDecl("");
		case Sym.field_declaration: // struct / union field
			if (auto bitNode = node.firstChildType(Sym.bitfield_clause)) {
				translateNode(ctu, *bitNode);
				node.append("/*"~bitNode.output~" !!*/");
			}
			return translateDecl(";");
		case Sym.declaration: // global / local variable
			return translateDecl(";");
		case Sym.type_definition:
			Decl[] decls = parseDecls(ctu, node, inlinetypes);
			string result = ""; // todo: anonymous types
			foreach(s; inlinetypes) {
				result ~= s.toString();
			}
			foreach(d; decls) {
				if (d.type == CType.named(d.identifier)) {
					// result ~= "/*alias " ~ d.toString() ~ ";*/";
				} else {
					result ~= "alias " ~ d.toGcString() ~ ";";
				}
			}
			node.replace(result);
			return true;
		case Sym.initializer_list:
			// TODO: check if not struct initializer
			// Ideas: array literal has Sym.subscript_designator, struct has Sym.field_designator
			//
			if (true) {
				// LBRACE = {

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
			if (auto designatorNode = node.childField("designator")) {
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
			// [a] = b  =>  a: b, this removes the [] and adds :
			if (auto c = node.firstChildType(Sym.anon_LBRACK)) {
				c.replace("");
			}
			if (auto c = node.firstChildType(Sym.anon_RBRACK)) {
				c.replace("");
			}
			node.append(":");
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
		default: return s;
	}
}

/// C identifiers that are keywords in D
/// Does not include keywords that are in both C and D (static, if, switch) or have similar meaning (null, true, assert)
private immutable dKeywords = [
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
