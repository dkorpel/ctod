module tree_sitter.wrapper;

import tree_sitter.api;

import dbg;

struct Node {
	TSNode node;

	bool isNone;
	size_t start;
	size_t end;
	const(char)[] type;

	this(TSNode node) {
		this.node = node;
		isNone = ts_node_is_null(node);
		if (!isNone) {
			start = ts_node_start_byte(node);
			end = ts_node_end_byte(node);

			import core.stdc.string: strlen;
			const c = ts_node_type(node);
			type = c[0..strlen(c)];
		}
	}

	Node parent() const {
		return Node(ts_node_parent(node));
	}

	int numChildren() const {return ts_node_child_count(node);}
	int numNamedChildren() const {return ts_node_named_child_count(node);}
	Node child(uint i) const {
		return Node(ts_node_child(node, i));
	}
	Node namedChild(uint i) const {
		return Node(ts_node_named_child(node, i));
	}
	Node childByField(string name) const {
		return Node(ts_node_child_by_field_name(node, name.ptr, cast(int) name.length));
	}

	bool opCast() const {return !isNone;}
}