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
	string result = format(moduleHeader, moduleName);
	Replacement[] replacements = CTranslationUnit("foo.c", source).convertToD();

	import std.algorithm: sort;
	replacements.sort!((a, b) => a.start < b.start);
	// note: will be (close to) sorted already because tree traversal should (roughly) match source code order

	size_t cursor = 0;
	foreach(r; replacements) {
		result ~= source[cursor..r.start];
		result ~= r.replacement;
		cursor = r.end;
	}
	result ~= source[cursor..$];

	return result;
}

/// A single .c file
struct CTranslationUnit {

	string fileName;
	string source;

	private string moduleName;

	version(none) this(string fileName) {
		import std.file: read;
		const source = cast(string) read(fileName);
		this(fileName, source);
	}

	this(string fileName, string source) {
		this.fileName = fileName;
		this.source = source;
	}

	Replacement[] convertToD() {
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
		//printf("Syntax tree: %s\n", str);
		Replacement[] result;
		getReplacements(this, rootNode, result);

		return result;
	}
}

void getReplacements(ref CTranslationUnit ctu, const Node node, ref Replacement[] replacements) {
	const nodeSource = ctu.source[node.start..node.end];
	const count = node.numChildren;
	foreach(uint i; 0..count) {
		Node child = node.child(i);
		getReplacements(ctu, child, replacements);
	}
	if (preprocReplacements(ctu, node, replacements)) {
		return;
	}
	switch (node.type) {
		/+
		case "preproc_if":
			//replacements ~= Replacement(node.start, node.start + "#if".length, "static if");
			if (auto conditionNode = node.childByField("condition")) {
				replacements ~= Replacement(conditionNode.start, conditionNode.start, "(");
				replacements ~= Replacement(conditionNode.end, conditionNode.end, ") {");
			}
			//replacements ~= Replacement(node.end - "#endif".length, node.end, "}");
			break;
		case "#endif":
			replacements ~= Replacement(node.start, node.end, "}");
			break;
		case "#elif":
			replacements ~= Replacement(node.start, node.end, "else static if");
			break;
		case "#else":
			replacements ~= Replacement(node.start, node.end, "else");
			break;
		case "#if":
			replacements ~= Replacement(node.start, node.end, "static if");
			break;
		case "preproc_include":
			//replacements ~= Replacement(node.start, node.start + "#include".length, "import");
			break;
		case "#include":
			replacements ~= Replacement(node.start, node.end, "import");
			break;
		case "preproc_def":
			//TSNode valueNode = ts_node_child_by_field_name(node, "value".ptr, "value".length);
			if (auto valueNode = node.childByField("value")) {
				// todo
				replacements ~= Replacement(node.start, node.start, "enum x = 0;");
			} else {
				replacements ~= Replacement(node.start, node.start, "//");
			}
			break;
		case "system_lib_string":
			string lib = nodeSource[1..$-1]; // slice to strip off angle brackets in <stdio.h>
			if (string importName = translateSysLib(lib)) {
				replacements ~= Replacement(node.start, node.end, importName~";");
			} else {
				//assert(0, nodeSource);
			}
			break;
		+/

		//case "sized_type_specifier":
		case "unsigned":
			replacements ~= Replacement(node.start, node.end, "u");
			break;
		case "signed":
			replacements ~= Replacement(node.start, node.end, "");
			break;
		case "primitive_type":
			if (string s = replacePrimitiveType(nodeSource)) {
				replacements ~= Replacement(node.start, node.end, s);
			}
			break;
		case "null":
			// while the node name is 'null', NULL in C is capitalized
			replacements ~= Replacement(node.start, node.end, "null");
			break;
		case "initializer_list":
			replacements ~= Replacement(node.start, node.start+1, "[");
			replacements ~= Replacement(node.end-1, node.end, "]");
			break;
		case "type_definition":
			replacements ~= Replacement(node.start, node.start + "typedef".length, "alias");
			break;
		case "struct_specifier":
			// todo: the actual check should be whether you are in a type expression
			// struct Opaque; should be allowed
			if (auto bodyNode = node.childByField("body")) {

			} else {
				replacements ~= Replacement(node.start, node.start + "struct".length, "");
			}
			break;
		case "parameter_declaration":
			// e.g. int main(void);
			if (nodeSource == "void") {
				replacements ~= Replacement(node.start, node.end, "");
			}
			break;
		case "sizeof_expression":
			// sizeof(x) => x.sizeof
			if (auto typeNode = node.childByField("type")) {
				replacements ~= Replacement(node.start, node.end, ctu.source[typeNode.start..typeNode.end] ~ ".sizeof");
			}
			break;
		case "->":
			replacements ~= Replacement(node.start, node.end, ".");
			break;
		case "cast_expression":
			replacements ~= Replacement(node.start, node.start, "cast");
			break;
		default:
			break;
	}
	//writefln("> %20s: %s", node.type, "..."); // nodeSource(node, )
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
