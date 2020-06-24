module ctod.dump;

/+


import core.stdc.stdlib: free;
import core.stdc.stdio: printf;
scope const(char)* str = ts_node_string(rootNode);
scope(exit) free(cast(void*) str);






version(none):

string cToD(string input) {
	scope TSParser *parser = ts_parser_new();
	scope(exit) ts_parser_delete(parser);

	TSLanguage* language = tree_sitter_c();
	assert(ts_parser_set_language(parser, language));

	//printFields(language);
	//printSymbols(language);

	scope TSTree* tree = ts_parser_parse_string(parser, null, input.ptr, cast(uint) input.length);
	scope(exit) ts_tree_delete(tree);

	import core.stdc.stdio: fopen, FILE;
	FILE* file = fopen("test.dot", "w");
	ts_tree_print_dot_graph(tree, file);
	fclose(file);

	const rootNode = ts_tree_root_node(tree);

	auto tr = Translator(input);
	tr.translateNode(rootNode);
	writeln(tr.result);

	scope const(char)* str = ts_node_string(rootNode);
	scope(exit) free(cast(void*) str);

	printf("Syntax tree: %s\n", str);
	return null;
}

struct Translator {

	string source;
	string result;

	this(string source) {
		this.source = source;

		//ts_language_field_id_for_name
	}

	string nodeSource(TSNode node) {
		const s = ts_node_start_byte(node);
		const e = ts_node_end_byte(node);
		return source[s..e];
	}

	const(char)[] nodeType(TSNode node) {
		const c = ts_node_type(node);
		return c[0..strlen(c)];
	}

	string translateNode(TSNode node) {
		// ts_node_named_child_count
		const count = ts_node_child_count(node);
		foreach(uint i; 0..count) {
			TSNode child = ts_node_child(node, i);
			translateNode(child);
		}

		if (count == 0) {
			result ~= nodeSource(node);
		}
		writefln("> %20s: %s", nodeType(node), nodeSource(node));
		return "";
	}

	string translateNodeCursor(TSNode node) {
		TSTreeCursor cursor = ts_tree_cursor_new(node);
		TSNode curr = ts_tree_cursor_current_node(&cursor);
		//ts_tree_cursor_delete(cursor);
		return "";

	}
}







+/