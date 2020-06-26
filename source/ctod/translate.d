module ctod.translate;

import ctod;
import tree_sitter.api, tree_sitter.wrapper;
import std.format;
import std.stdio;

private immutable moduleHeader = "/// Translated from C to D
module %s;

extern(C): @nogc: nothrow:
";

///
string translateFile(string source, string moduleName) {
	Node root = parseCtree(source);
	auto ctx = TranslationContext("foo.c", source);
	translateNode(ctx, root);
	return format(moduleHeader, moduleName) ~ root.output;
}

/// What the C macro is for
enum MacroType {
	none, // und
	manifestConstant, // #define three 3
	inlineFunc, // #define SQR(x) (x*x)
	versionId, // #ifdef _WIN32_
	staticIf,
}

/// A single .c file
package struct TranslationContext {

	string fileName;
	string source;

	string moduleName;

	// current macro type
	MacroType macroType;

	// context
	const(char)[] parentType = "";

	this(string fileName, string source) {
		this.fileName = fileName;
		this.source = source;
	}
}

void translateNode(ref TranslationContext ctu, ref Node node) {
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
	/+
	return "";
	//writefln("> %20s: %s", node.type, "..."); // nodeSource(node, )
	+/
}

bool tryTranslateMisc(ref TranslationContext ctu, ref Node node) {
	switch (node.type) {
		//case "sized_type_specifier":
		case "unsigned":
			return node.replace("");
		case "signed":
			return node.replace("");
		case "primitive_type":
			if (string s = replacePrimitiveType(node.source)) {
				node.replace(s);
				return true;
			}
			return false;
		case "null":
			return node.replace("null");
		case "typedef":
			return node.replace("alias");
		/+
		case "struct_specifier":

			// todo: the actual check should be whether you are in a type expression
			// struct Opaque; should be allowed
			if (auto bodyNode = node.childByField("body")) {

			} else {
				//replacements ~= Replacement(node.start, node.start + "struct".length, "");
			}
			break;
		case "struct":
			if (ctu.parentType == "TODO") {
				return "";
			} else {
				return nodeSource;
			}
		case "void":
			// remove void in e.g. int main(void);
			return ctu.parentType == "parameter_declaration" ? "" : nodeSource;
		case "sizeof_expression":
			// sizeof(x) => x.sizeof
			//if (auto typeNode = node.childByField("type")) {
				//replacements ~= Replacement(node.start, node.end, ctu.source[typeNode.start..typeNode.end] ~ ".sizeof");
			//}
			break;
		+/
		case "->":
			return node.replace(".");
		case "cast_expression":
			if (auto c = node.firstChildType("(")) {
				return c.replace("cast(");
			}
			return false;
		case "type_definition":
		case "translation_unit":
		case "initializer_list":
		default: break;
	}
	return false;
}
/+
package string translateNodeChildren(ref TranslationContext ctu, const Node node) {
	string result = "";
	size_t cursor = node.start;
	foreach(uint i; 0..node.numChildren) {
		Node child = node.child(i);
		result ~= ctu.source[cursor..child.start];
		result ~= translateNode(ctu, child); //ctu.source[child.start..child.end];
		cursor = child.end;
	}
	result ~= ctu.source[cursor..node.end];
	return result;
}

const(char)[] nodeType(TSNode node) {
	import core.stdc.string: strlen;
	const c = ts_node_type(node);
	return c[0..strlen(c)];
}
+/