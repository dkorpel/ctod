module ctod.cdeclaration;

import ctod.tree_sitter;
import ctod.translate;
import ctod.ctype;
// import bops.tostring: toGcString;

/// Returns: true if a declaration was matched and replaced
bool ctodTryDeclaration(ref TranslationContext ctu, ref Node node) {
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

	switch(node.typeEnum) {
		case Sym.function_definition:
			if (auto bodyNode = node.childField(Field.body_)) {
				ctu.enterFunction("???");
				translateNode(ctu, *bodyNode);
				ctu.leaveFunction();
				return translateDecl(" " ~ bodyNode.output());
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
				if (s.hasBody()) {
					result ~= s.toString();
				}
			}
			foreach(d; decls) {
				if (d.type == CType.named(d.identifier)) {
					// result ~= "/*alias " ~ d.toString() ~ ";*/";
				} else {
					result ~= "alias " ~ d.toString() ~ ";";
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
			if (auto designatorNode = node.childField(Field.designator)) {
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

/// Modify C identifiers that are keywords in D
string translateIdentifier(string s) {
	return mapLookup(keyWordMap, s, s);
}

/// C identifiers that are keywords in D
/// Does not include keywords that are in both C and D (if, switch, static)
/// or have similar meaning (null, true, assert)
private immutable string[2][] keyWordMap = [
	["abstract", "abstract_"],
	["alias", "alias_"],
	["align", "align_"],
	["asm", "asm_"],
	["auto", "auto_"],
	["bool", "bool_"],
	["byte", "byte_"],
	["cast", "cast_"],
	["catch", "catch_"],
	["cdouble", "cdouble_"],
	["cent", "cent_"],
	["cfloat", "cfloat_"],
	["char", "char_"],
	["class", "class_"],
	["creal", "creal_"],
	["dchar", "dchar_"],
	["debug", "debug_"],
	["delegate", "delegate_"],
	["deprecated", "deprecated_"],
	["export", "export_"],
	["final", "final_"],
	["finally", "finally_"],
	["foreach", "foreach_"],
	["foreach_reverse", "foreach_reverse_"],
	["function", "function_"],
	["idouble", "idouble_"],
	["ifloat", "ifloat_"],
	["immutable", "immutable_"],
	["import", "import_"],
	["in", "in_"],
	["inout", "inout_"],
	["interface", "interface_"],
	["invariant", "invariant_"],
	["ireal", "ireal_"],
	["is", "is_"],
	["lazy", "lazy_"],
	["macro", "macro_"],
	["mixin", "mixin_"],
	["module", "module_"],
	["new", "new_"],
	["nothrow", "nothrow_"],
	["out", "out_"],
	["override", "override_"],
	["package", "package_"],
	["pragma", "pragma_"],
	["private", "private_"],
	["protected", "protected_"],
	["public", "public_"],
	["pure", "pure_"],
	["real", "real_"],
	["ref", "ref_"],
	["scope", "scope_"],
	["shared", "shared_"],
	["super", "super_"],
	["synchronized", "synchronized_"],
	["template", "template_"],
	["this", "this_"],
	["throw", "throw_"],
	["try", "try_"],
	["typeid", "typeid_"],
	["typeof", "typeof_"],
	["ubyte", "ubyte_"],
	["ucent", "ucent_"],
	["uint", "uint_"],
	["ulong", "ulong_"],
	["unittest", "unittest_"],
	["ushort", "ushort_"],
	["version", "version_"],
	["wchar", "wchar_"],
	["with", "with_"],
];
