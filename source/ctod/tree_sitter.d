module ctod.tree_sitter;

import tree_sitter.api;
import std.string: fromStringz;

/// Returns: C language parser for tree-sitter
extern(C) TSLanguage* tree_sitter_c();

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
	nothrow:
	private TSNode tsnode;

	private size_t start = 0;
	private size_t end = 0;

	/// Tag identifying the C AST node type
	TSSymbol typeEnum;
	private const(char)[] field;

	/// C source code
	string fullSource;

	/// Source code of this node
	string source() const {return fullSource[start..end];}

	/// D code to replace source with for this node
	string replacement = "<@>";

	private string prefix;
	private string suffix;
	private bool noLayout = false; // don't emit layout

	/// Tree relations
	Node* parent;
	/// Child nodes
	Node[] children;

	bool isNone = true; /// whether this is a null value
	bool inFuncBody = false; /// whether we are under a function definition node
	bool isTranslated = false; /// if translation has already been done

	//@disable this(this); need to emplace in findChildren

	this(TSNode node, string fullSource, Node* parent = null, const(char)[] fieldName = "") {
		this.tsnode = node; //
		this.parent = parent;
		isNone = ts_node_is_null(tsnode);
		if (!isNone) {
			this.start = ts_node_start_byte(tsnode);
			this.end = ts_node_end_byte(tsnode);
			this.typeEnum = ts_node_symbol(tsnode);
			this.fullSource = fullSource;
			this.replacement = this.source;
			this.field = fieldName;
			children.length = ts_node_child_count(tsnode);
			//if (children.length == 0) dprint(this.source);
		}
	}

	private ref Node findChildren(string source) return {
		import core.lifetime: moveEmplace;
		foreach(i, ref c; children) {
			c = Node(ts_node_child(tsnode, cast(uint) i), source, &this).findChildren(source);
		}
		return this;
	}

	private ref Node validate(const(char)[] diagnostic = "root") return {
		if (!this) {
			assert(0, diagnostic);
		}
		foreach(i, ref c; children) {
			c.validate("?");
		}
		return this;
	}

	/// Replace this entire subtree with a translation
	bool replace(string s) {
		children.length = 0;
		isTranslated = true;
		replacement = s;
		return true;
	}

	/// Prevent preceding whitespace / comments from being output
	void removeLayout() {
		noLayout = true;
	}

	/// For translation purposes, prepend/append `s` to this node's source, without modifying the node's source itself
	bool prepend(string s) {
		prefix = s ~ prefix;
		return false;
	}

	/// ditto
	bool append(string s) {
		suffix ~= s;
		return false;
	}

	/// Returns: first child node with `type`
	Node* firstChildType(TSSymbol type) {
		foreach(ref c; children) {
			if (c.typeEnum == type) {
				return &c;
			}
		}
		return null;
	}

	/// `false` if this is null
	bool opCast() const {return !isNone;}

	/// Returns: full translated D source code of this node after translation
	string output() const {
		string result = "";
		void append(const ref Node node) {
			result ~= node.prefix;
			if (node.children.length == 0) {
				result ~= node.replacement;
			} else {
				size_t lc = node.start; // layout cursor
				foreach(ref c; node.children) {
					if (!c || c.noLayout) {
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

	/// Returns: Child node identified by field name
	inout(Node)* childField(string name) inout {
		auto f = ts_node_child_by_field_name(tsnode, name.ptr, cast(int) name.length);
		// ts_node_child_by_field_id(tsnode, id);
		foreach(ref c; children) {
			if (ts_node_eq(c.tsnode, f)) {
				return &c;
			}
		}
		return null;
		/*
		while (ts_node_is_null(curr)) {
			i++;
			auto prev = ts_node_prev_sibling(curr);
			curr = prev;
		}
		=?
		return (i == 0) ? null : &children[i-1];
		*/
	}

	/*
	int numChildren() const {return ts_node_child_count(node);}
	int numNamedChildren() const {return ts_node_named_child_count(node);}
	Node child(uint i) const {
		return Node(ts_node_child(node, i));
	}
	Node namedChild(uint i) const {
		return Node(ts_node_named_child(node, i));
	}
	*/
}

/// Identifies a C tree-sitter node
enum Sym : ushort {
	identifier = 1,
	aux_preproc_include_token1 = 2,
	anon_LF = 3,
	aux_preproc_def_token1 = 4,
	anon_LPAREN = 5,
	anon_DOT_DOT_DOT = 6,
	anon_COMMA = 7,
	anon_RPAREN = 8,
	aux_preproc_if_token1 = 9,
	aux_preproc_if_token2 = 10,
	aux_preproc_ifdef_token1 = 11,
	aux_preproc_ifdef_token2 = 12,
	aux_preproc_else_token1 = 13,
	aux_preproc_elif_token1 = 14,
	preproc_directive = 15,
	preproc_arg = 16,
	anon_LPAREN2 = 17,
	anon_defined = 18,
	anon_BANG = 19,
	anon_TILDE = 20,
	anon_DASH = 21,
	anon_PLUS = 22,
	anon_STAR = 23,
	anon_SLASH = 24,
	anon_PERCENT = 25,
	anon_PIPE_PIPE = 26,
	anon_AMP_AMP = 27,
	anon_PIPE = 28,
	anon_CARET = 29,
	anon_AMP = 30,
	anon_EQ_EQ = 31,
	anon_BANG_EQ = 32,
	anon_GT = 33,
	anon_GT_EQ = 34,
	anon_LT_EQ = 35,
	anon_LT = 36,
	anon_LT_LT = 37,
	anon_GT_GT = 38,
	anon_SEMI = 39,
	anon_typedef = 40,
	anon_extern = 41,
	anon___attribute__ = 42,
	anon_COLON_COLON = 43,
	anon_LBRACK_LBRACK = 44,
	anon_RBRACK_RBRACK = 45,
	anon___declspec = 46,
	anon___based = 47,
	anon___cdecl = 48,
	anon___clrcall = 49,
	anon___stdcall = 50,
	anon___fastcall = 51,
	anon___thiscall = 52,
	anon___vectorcall = 53,
	ms_restrict_modifier = 54,
	ms_unsigned_ptr_modifier = 55,
	ms_signed_ptr_modifier = 56,
	anon__unaligned = 57,
	anon___unaligned = 58,
	anon_LBRACE = 59,
	anon_RBRACE = 60,
	anon_LBRACK = 61,
	anon_RBRACK = 62,
	anon_EQ = 63,
	anon_static = 64,
	anon_auto = 65,
	anon_register = 66,
	anon_inline = 67,
	anon_const = 68,
	anon_volatile = 69,
	anon_restrict = 70,
	anon__Atomic = 71,
	anon_signed = 72,
	anon_unsigned = 73,
	anon_long = 74,
	anon_short = 75,
	primitive_type = 76,
	anon_enum = 77,
	anon_struct = 78,
	anon_union = 79,
	anon_COLON = 80,
	anon_if = 81,
	anon_else = 82,
	anon_switch = 83,
	anon_case = 84,
	anon_default = 85,
	anon_while = 86,
	anon_do = 87,
	anon_for = 88,
	anon_return = 89,
	anon_break = 90,
	anon_continue = 91,
	anon_goto = 92,
	anon_QMARK = 93,
	anon_STAR_EQ = 94,
	anon_SLASH_EQ = 95,
	anon_PERCENT_EQ = 96,
	anon_PLUS_EQ = 97,
	anon_DASH_EQ = 98,
	anon_LT_LT_EQ = 99,
	anon_GT_GT_EQ = 100,
	anon_AMP_EQ = 101,
	anon_CARET_EQ = 102,
	anon_PIPE_EQ = 103,
	anon_DASH_DASH = 104,
	anon_PLUS_PLUS = 105,
	anon_sizeof = 106,
	anon_DOT = 107,
	anon_DASH_GT = 108,
	number_literal = 109,
	anon_L_SQUOTE = 110,
	anon_u_SQUOTE = 111,
	anon_U_SQUOTE = 112,
	anon_u8_SQUOTE = 113,
	anon_SQUOTE = 114,
	aux_char_literal_token1 = 115,
	anon_L_DQUOTE = 116,
	anon_u_DQUOTE = 117,
	anon_U_DQUOTE = 118,
	anon_u8_DQUOTE = 119,
	anon_DQUOTE = 120,
	aux_string_literal_token1 = 121,
	escape_sequence = 122,
	system_lib_string = 123,
	true_ = 124,
	false_ = 125,
	null_ = 126,
	comment = 127,
	translation_unit = 128,
	preproc_include = 129,
	preproc_def = 130,
	preproc_function_def = 131,
	preproc_params = 132,
	preproc_call = 133,
	preproc_if = 134,
	preproc_ifdef = 135,
	preproc_else = 136,
	preproc_elif = 137,
	preproc_if_in_field_declaration_list = 138,
	preproc_ifdef_in_field_declaration_list = 139,
	preproc_else_in_field_declaration_list = 140,
	preproc_elif_in_field_declaration_list = 141,
	_preproc_expression = 142,
	preproc_parenthesized_expression = 143,
	preproc_defined = 144,
	preproc_unary_expression = 145,
	preproc_call_expression = 146,
	preproc_argument_list = 147,
	preproc_binary_expression = 148,
	function_definition = 149,
	declaration = 150,
	type_definition = 151,
	_declaration_modifiers = 152,
	_declaration_specifiers = 153,
	linkage_specification = 154,
	attribute_specifier = 155,
	attribute = 156,
	attribute_declaration = 157,
	ms_declspec_modifier = 158,
	ms_based_modifier = 159,
	ms_call_modifier = 160,
	ms_unaligned_ptr_modifier = 161,
	ms_pointer_modifier = 162,
	declaration_list = 163,
	_declarator = 164,
	_field_declarator = 165,
	_type_declarator = 166,
	_abstract_declarator = 167,
	parenthesized_declarator = 168,
	parenthesized_field_declarator = 169,
	parenthesized_type_declarator = 170,
	abstract_parenthesized_declarator = 171,
	attributed_declarator = 172,
	attributed_field_declarator = 173,
	attributed_type_declarator = 174,
	pointer_declarator = 175,
	pointer_field_declarator = 176,
	pointer_type_declarator = 177,
	abstract_pointer_declarator = 178,
	function_declarator = 179,
	function_field_declarator = 180,
	function_type_declarator = 181,
	abstract_function_declarator = 182,
	array_declarator = 183,
	array_field_declarator = 184,
	array_type_declarator = 185,
	abstract_array_declarator = 186,
	init_declarator = 187,
	compound_statement = 188,
	storage_class_specifier = 189,
	type_qualifier = 190,
	_type_specifier = 191,
	sized_type_specifier = 192,
	enum_specifier = 193,
	enumerator_list = 194,
	struct_specifier = 195,
	union_specifier = 196,
	field_declaration_list = 197,
	_field_declaration_list_item = 198,
	field_declaration = 199,
	bitfield_clause = 200,
	enumerator = 201,
	variadic_parameter = 202,
	parameter_list = 203,
	parameter_declaration = 204,
	attributed_statement = 205,
	attributed_non_case_statement = 206,
	labeled_statement = 207,
	expression_statement = 208,
	if_statement = 209,
	switch_statement = 210,
	case_statement = 211,
	while_statement = 212,
	do_statement = 213,
	for_statement = 214,
	return_statement = 215,
	break_statement = 216,
	continue_statement = 217,
	goto_statement = 218,
	_expression = 219,
	comma_expression = 220,
	conditional_expression = 221,
	assignment_expression = 222,
	pointer_expression = 223,
	unary_expression = 224,
	binary_expression = 225,
	update_expression = 226,
	cast_expression = 227,
	type_descriptor = 228,
	sizeof_expression = 229,
	subscript_expression = 230,
	call_expression = 231,
	argument_list = 232,
	field_expression = 233,
	compound_literal_expression = 234,
	parenthesized_expression = 235,
	initializer_list = 236,
	initializer_pair = 237,
	subscript_designator = 238,
	field_designator = 239,
	char_literal = 240,
	concatenated_string = 241,
	string_literal = 242,
	_empty_declaration = 243,
	macro_type_specifier = 244,
	aux_translation_unit_repeat1 = 245,
	aux_preproc_params_repeat1 = 246,
	aux_preproc_if_in_field_declaration_list_repeat1 = 247,
	aux_preproc_argument_list_repeat1 = 248,
	aux_declaration_repeat1 = 249,
	aux_type_definition_repeat1 = 250,
	aux_type_definition_repeat2 = 251,
	aux__declaration_specifiers_repeat1 = 252,
	aux_attribute_declaration_repeat1 = 253,
	aux_attributed_declarator_repeat1 = 254,
	aux_pointer_declarator_repeat1 = 255,
	aux_function_declarator_repeat1 = 256,
	aux_sized_type_specifier_repeat1 = 257,
	aux_enumerator_list_repeat1 = 258,
	aux_field_declaration_repeat1 = 259,
	aux_parameter_list_repeat1 = 260,
	aux_case_statement_repeat1 = 261,
	aux_argument_list_repeat1 = 262,
	aux_initializer_list_repeat1 = 263,
	aux_initializer_pair_repeat1 = 264,
	aux_concatenated_string_repeat1 = 265,
	aux_string_literal_repeat1 = 266,
	alias_field_identifier = 267,
	alias_statement_identifier = 268,
	alias_type_identifier = 269,
}
