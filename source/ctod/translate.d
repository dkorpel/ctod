module ctod.translate;

import ctod;
import tree_sitter.api;
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

	this(string fileName) {
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

		const rootNode = ts_tree_root_node(tree);
		//printf("Syntax tree: %s\n", str);
		Replacement[] result;
		getReplacements(rootNode, result);

		return result;
	}

	void getReplacements(TSNode node, ref Replacement[] replacements) {
		const nodeStart = ts_node_start_byte(node);
		const nodeEnd = ts_node_end_byte(node);
		const nodeSource = source[nodeStart..nodeEnd];
		const count = ts_node_child_count(node);
		foreach(uint i; 0..count) {
			TSNode child = ts_node_child(node, i);
			getReplacements(child, replacements);
		}

		const type = nodeType(node);

		switch (type) {
			case "->":
				replacements ~= Replacement(nodeStart, nodeEnd, ".");
				break;
			case "cast_expression":
				replacements ~= Replacement(nodeStart, nodeStart, "cast");
				break;
			case "preproc_if":
				replacements ~= Replacement(nodeStart, nodeStart + "#if".length, "static if (");
				replacements ~= Replacement(nodeEnd - "#endif".length, nodeEnd, "}");
				break;
			case "preproc_include":
				replacements ~= Replacement(nodeStart, nodeStart + "#include".length, "import");
				replacements ~= Replacement(nodeEnd, nodeEnd, ";");
				break;
			case "preproc_def":

				TSNode valueNode = ts_node_child_by_field_name(node, "value".ptr, "value".length);
				if (ts_node_is_null(valueNode)) {
					replacements ~= Replacement(nodeStart, nodeStart, "//");
				} else {
					// todo
					replacements ~= Replacement(nodeStart, nodeStart, "enum x = 0;");
				}
				break;
			case "system_lib_string":
				string lib = nodeSource[1..$-1]; // slice to strip off angle brackets in <stdio.h>
				if (string importName = translateSysLib(lib)) {
					replacements ~= Replacement(nodeStart, nodeEnd, importName);
				} else {
					//assert(0, nodeSource);
				}
				break;
			case "sized_type_specifier":
				replacements ~= Replacement(nodeStart, nodeEnd, "u");
				break;
			default:
				break;
		}

		if (count == 0) {
			//writefln("> %20s: %s", nodeType(node), "..."); // nodeSource(node, )
		}
	}
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
