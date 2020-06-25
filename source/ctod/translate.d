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
	return format(moduleHeader, moduleName) ~ TranslationContext("foo.c", source).convertToD();
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

	version(none) this(string fileName) {
		import std.file: read;
		const source = cast(string) read(fileName);
		this(fileName, source);
	}

	this(string fileName, string source) {
		this.fileName = fileName;
		this.source = source;
	}

	string convertToD() @system {
		// Init tree-sitter
		scope TSParser *parser = ts_parser_new();
		scope(exit) ts_parser_delete(parser);
		TSLanguage* language = tree_sitter_c();
		assert(ts_parser_set_language(parser, language));
		scope TSTree* tree = ts_parser_parse_string(parser, null, source.ptr, cast(uint) source.length);
		scope(exit) ts_tree_delete(tree);

		import core.stdc.stdio: fopen, FILE, fclose;
		FILE* file = fopen("test.dot", "w");
		ts_tree_print_dot_graph(tree, file);
		fclose(file);

		const rootNode = Node(ts_tree_root_node(tree));
		assert(rootNode);

		return translateNode(this, rootNode);
	}
}

string translateNode(ref TranslationContext ctu, const Node node) {
	const nodeSource = ctu.source[node.start..node.end];
	if (string s = tryTranslatePreprocessor(ctu, node)) {
		return s;
	}
	if (string s = tryTranslateDeclaration(ctu, node)) {
		return s;
	}

	switch (node.type) {
		//case "sized_type_specifier":
		case "identifier":
			if (string s = replaceIdentifier(nodeSource)) {
				return s;
			} else {
				return nodeSource;
			}
		case "unsigned":
			return ""; //replacements ~= Replacement(node.start, node.end, "u");
		case "signed":
			return "";
		case "primitive_type":
			if (string s = replacePrimitiveType(nodeSource)) {
				return s;
			}
			return nodeSource;
		case "null":
			// while the node name is 'null', NULL in C is capitalized
			return "null";
		case "typedef":
			return "alias";
		/+
		case "struct_specifier":

			// todo: the actual check should be whether you are in a type expression
			// struct Opaque; should be allowed
			if (auto bodyNode = node.childByField("body")) {

			} else {
				//replacements ~= Replacement(node.start, node.start + "struct".length, "");
			}
			break;
		+/
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
		case "->":
			return ".";
		case "cast_expression":
			return "cast"~translateNodeChildren(ctu, node);
		case "type_definition":
		case "translation_unit":
		case "initializer_list":
		default:
			return translateNodeChildren(ctu, node);
	}
	return "";
	//writefln("> %20s: %s", node.type, "..."); // nodeSource(node, )
}

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

/// A replacement of a piece of the C source to a new piece of equivalent D source
struct Replacement {
	/// start and end bytes
	size_t start;
	/// ditto
	size_t end;
	///
	string replacement;
}
