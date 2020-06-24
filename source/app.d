import tree_sitter.api;
import core.stdc.stdio: printf;
import core.stdc.stdlib: free;

extern(C) TSLanguage* tree_sitter_c();

int main() {
	// Create a parser.
	TSParser *parser = ts_parser_new();

	// Set the parser's language (JSON in this case).
	ts_parser_set_language(parser, tree_sitter_c());

	// Build a syntax tree based on source code stored in a string.
	string sourceCode = "#define TEST_CONST 3\n";
	TSTree *tree = ts_parser_parse_string(parser, null, sourceCode.ptr, cast(uint) sourceCode.length);

	// Get the root node of the syntax tree.
	TSNode root_node = ts_tree_root_node(tree);

	// Get some child nodes.
	TSNode array_node = ts_node_named_child(root_node, 0);
	TSNode number_node = ts_node_named_child(array_node, 0);

	// Print the syntax tree as an S-expression.
	char *str = ts_node_string(root_node);
	printf("Syntax tree: %s\n", str);

	// Free all of the heap-allocated memory.
	free(str);
	ts_tree_delete(tree);
	ts_parser_delete(parser);
	return 0;
}
