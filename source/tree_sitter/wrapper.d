module tree_sitter.wrapper;

import tree_sitter;
import dbg;
import std.string: fromStringz;

/// Returns: a concrete syntax tree for C source code
Node* parseCtree(string source) {
	scope TSParser *parser = ts_parser_new();
	scope(exit) ts_parser_delete(parser);
	TSLanguage* language = tree_sitter_c();
	const success = ts_parser_set_language(parser, language);
	assert(success);
	scope TSTree* tree = ts_parser_parse_string(parser, null, source.ptr, cast(uint) source.length);
	//scope(exit) ts_tree_delete(tree);

	if (ts_node_is_null(ts_tree_root_node(tree))) {
		return null;
	}

	//return CtreeFromCursor(tree, source);
	return &new Node(ts_tree_root_node(tree), source, null, "").findChildren(source);
}

/// The idea is to use the cursor api to get field names
/// This is because a declaration node can have multiple declarator fields, but the node API
/// only allows retrieving the first one
/// It's incomplete though, the cursor api seems to generate a different tree than the node api
Node* cTreeFromCursor(const(TSTree)* tree, string source) {
	TSTreeCursor cursor = ts_tree_cursor_new(ts_tree_root_node(tree));
	scope(exit) ts_tree_cursor_delete(&cursor);
	Node* cursorParent = null;
	Node* cursorNode = &[Node.init][0];

	while (true) {
		const fieldName = fromStringz(ts_tree_cursor_current_field_name(&cursor));
		*cursorNode = Node(ts_tree_cursor_current_node(&cursor), source, cursorParent, fieldName);
		if (ts_tree_cursor_goto_first_child(&cursor)) {
			cursorParent = cursorNode;
			cursorNode = &cursorNode.children[0];
			continue;
		} else {
			cursorNode++; // ! not @safe, but if code is correct, should stay in bounds of `children` array
			while (!ts_tree_cursor_goto_next_sibling(&cursor)) {
				if (!ts_tree_cursor_goto_parent(&cursor)) {
					return cursorNode;
				}
				cursorNode = cursorParent;
				cursorParent = cursorParent.parent;
			}
		}
	}
}

/// Conrete syntax tree node
struct Node {
	TSNode tsnode;

	size_t start = 0;
	size_t end = 0;

	const(char)[] type;
	const(char)[] field;

	/// C source code
	string fullSource;

	string source() const {return fullSource[start..end];}

	/// D code to replace source with for this node
	string replacement = "<@>";
	string prefix;
	string suffix;

	/// tree relations
	Node* parent;
	Node[] children;

	bool isNone = true; /// whether this is a null value
	bool inFuncBody = false; /// whether we are under a function definition node
	bool isTranslated = false; /// if translation has already been done

	this(TSNode node, string fullSource, Node* parent = null, const(char)[] fieldName = "") {
		this.tsnode = node; //
		this.parent = parent;
		isNone = ts_node_is_null(tsnode);
		if (!isNone) {
			this.start = ts_node_start_byte(tsnode);
			this.end = ts_node_end_byte(tsnode);
			this.type = fromStringz(ts_node_type(tsnode));
			this.fullSource = fullSource;
			this.replacement = this.source;
			this.field = fieldName;
			children.length = ts_node_child_count(tsnode);
			//if (children.length == 0) dprint(this.source);
		}
	}

	ref Node findChildren(string source) return {
		foreach(i, ref c; children) {
			c = Node(ts_node_child(tsnode, cast(uint) i), source, &this).findChildren(source);
		}
		return this;
	}

	ref Node validate(const(char)[] diagnostic = "root") return {
		if (!this) {
			assert(0, diagnostic);
		}
		foreach(i, ref c; children) {
			c.validate(this.type);
		}
		return this;
	}

	bool replace(string s) {
		children.length = 0;
		isTranslated = true;
		replacement = s;
		return true;
	}

	bool prepend(string s) {
		prefix = s ~ prefix;
		return false;
	}

	bool append(string s) {
		suffix ~= s;
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
				result ~= node.prefix;
				result ~= node.replacement;
			} else {
				result ~= node.prefix;
				size_t lc = node.start; // layout cursor
				foreach(ref c; node.children) {
					if (!c) {
						//dprint(node.source);
					} else {
						result ~= fullSource[lc .. c.start]; // add layout
					}
					lc = c.end;
					append(c);

				}
			}
			result ~= node.suffix;
		}
		append(this);
		return result;
	}

	inout(Node)* childField(string name) inout {
		auto f = ts_node_child_by_field_name(tsnode, name.ptr, cast(int) name.length);
		foreach(ref c; children) {
			if (ts_node_eq(c.tsnode, f)) {
				return &c;
			}
		}
		return null;
		/+
		while (ts_node_is_null(curr)) {
			i++;
			auto prev = ts_node_prev_sibling(curr);
			curr = prev;
		}
		=?
		return (i == 0) ? null : &children[i-1];
		+/
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