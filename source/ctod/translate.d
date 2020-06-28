module ctod.translate;

import ctod;
import tree_sitter.api, tree_sitter.wrapper;
import std.format;
import std.stdio;

private immutable moduleHeader = "/// Translated from C to D
module %s;

extern(C): @nogc: nothrow:
";

private immutable hasVersion = q{
private template HasVersion(string versionId) {
	mixin("version("~versionId~") {enum HasVersion = true;} else {enum HasVersion = false;}");
}
};

///
string translateFile(string source, string moduleName) {
	Node* root = parseCtree(source);
	assert(root);
	auto ctx = TranslationContext("foo.c", source);
	translateNode(ctx, *root);
	string result = format(moduleHeader, moduleName);
	if (ctx.needsHasVersion) {
		result ~= hasVersion;
	}
	result ~=root.output;
	return result;
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

	bool needsHasVersion = false; // HasVersion(string) template is needed

	// context
	const(char)[] parentType = "";

	/// global variables and function declarations
	string[string] symbolTable;

	this(string fileName, string source) {
		this.fileName = fileName;
		this.source = source;
	}
}

///
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
