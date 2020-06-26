module tree_sitter.wrapper;

import tree_sitter;
import dbg;

/// Returns: a concrete syntax tree for C source code
Node parseCtree(string source) {
	scope TSParser *parser = ts_parser_new();
	scope(exit) ts_parser_delete(parser);
	TSLanguage* language = tree_sitter_c();
	assert(ts_parser_set_language(parser, language));
	scope TSTree* tree = ts_parser_parse_string(parser, null, source.ptr, cast(uint) source.length);
	scope(exit) ts_tree_delete(tree);
	return Node(ts_tree_root_node(tree), source, null);
}

/// Conrete syntax tree node
struct Node {
	TSNode tsnode;

	size_t start;
	size_t end;

	const(char)[] type;

	/// C source code
	string source;

	/// preceding characters
	/// whitespace characters between nodes
	string layout;

	/// D code to replace source with for this node
	string replacement;

	/// tree relations
	Node* parent;
	Node[] children;

	bool isNone = true;

	this(TSNode node, string source, Node* parent = null, size_t cursor = 0) {
		this.tsnode = node;
		this.parent = parent;
		isNone = ts_node_is_null(node);
		if (!isNone) {
			start = ts_node_start_byte(node);
			end = ts_node_end_byte(node);
			this.layout = source[cursor..start];
			this.source = source[start..end];
			this.replacement = this.source;

			import core.stdc.string: strlen;
			const tstr = ts_node_type(node);
			type = tstr[0..strlen(tstr)];

			children.length = ts_node_child_count(node);

			size_t child_cursor = cursor;
			foreach(i, ref c; children) {
				c = Node(ts_node_child(node, cast(uint) i), source, &this, child_cursor);
				child_cursor = c.end;
			}
		}
	}

	bool replace(string s) {
		replacement = s;
		return true;
	}

	bool prepend(string s) {
		replacement = s ~ replacement;
		return false;
	}

	Node* firstChildType(string type) {
		foreach(ref c; children) {
			if (c.type == type) {
				return &c;
			}
		}
		return null;
	}

	/// `false` if this is null
	bool opCast() const {return !isNone;}

	string output() const {
		string result = "";
		void append(const ref Node node) {
			if (node.children.length == 0) {
				//result ~= node.type;
				result ~= /+"[" ~+/ node.layout /+~ "]"+/;
				result ~= /+"{" ~+/ node.replacement /+~ "}"+/;
			} else {
				foreach(ref c; node.children) {
					append(c);
				}
			}
		}
		append(this);
		return result;
	}

	version(none):
	Node* childByField(string name) const {
		return Node(ts_node_child_by_field_name(node, name.ptr, cast(int) name.length));
	}

	/+
	int numChildren() const {return ts_node_child_count(node);}
	int numNamedChildren() const {return ts_node_named_child_count(node);}
	Node child(uint i) const {
		return Node(ts_node_child(node, i));
	}
	Node namedChild(uint i) const {
		return Node(ts_node_named_child(node, i));
	}
	+/
}