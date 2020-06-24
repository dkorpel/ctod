import tree_sitter.api;
import core.stdc.stdio: printf;
import core.stdc.stdlib: free;
import core.stdc.string: strlen;

import std.stdio;

extern(C) TSLanguage* tree_sitter_c();

immutable source = `
#include<stdio.h>

#define X 3

// My nice struct
struct Test {
	unsigned int x;
	int *y;
}

int main() {

	while(x) {
		foo();
	}

	Test *t;

	t->x = 3;

	return 0;
}
`;

int main() {
	cToD(source);
	return 0;
}

string cToD(string input) {
	scope TSParser *parser = ts_parser_new();
	scope(exit) ts_parser_delete(parser);

	TSLanguage* language = tree_sitter_c();
	assert(ts_parser_set_language(parser, language));


	scope TSTree* tree = ts_parser_parse_string(parser, null, input.ptr, cast(uint) input.length);
	scope(exit) ts_tree_delete(tree);

	const rootNode = ts_tree_root_node(tree);

	Translator(input).translateNode(rootNode);

	scope const(char)* str = ts_node_string(rootNode);
	scope(exit) free(cast(void*) str);

	printf("Syntax tree: %s\n", str);
	return null;
}

void printFields(TSLanguage* language) {
	const count = cast(ushort) ts_language_field_count(language);
	foreach(ushort i; 0..count) {
		const char* str = ts_language_field_name_for_id(language, i);
		printf("%d: %s\n", i, str);
	}
}

struct Translator {
	string source;

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
			writefln("%20s: %s", nodeType(node), nodeSource(node));
		}

		return "";

	}

	string translateNodeCursor(TSNode node) {
		TSTreeCursor cursor = ts_tree_cursor_new(node);
		TSNode curr = ts_tree_cursor_current_node(&cursor);
		//ts_tree_cursor_delete(cursor);
		return "";

	}



}

