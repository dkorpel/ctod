module ctod.tree_sitter;
@safe:
nothrow:

import tree_sitter.api;
import ctod.util;
import ctod.translate;
import ctod.ctype;

/// Returns: a concrete syntax tree for C source code
Node parseCtree(return scope ref CtodCtx ctx) @trusted
{
	scope TSTree* tree = ts_parser_parse_string(ctx.parser, null, ctx.sourceC.ptr, cast(uint) ctx.sourceC.length);
	if (ts_node_is_null(ts_tree_root_node(tree)))
	{
		return Node.none;
	}
	return Node(ts_tree_root_node(tree), &ctx);
}

struct Children
{
nothrow:
	private TSNode tsnode;
	CtodCtx* ctx;
	size_t length;
	bool named = false;
	size_t i = 0;

	this(return scope TSNode tsnode, const return scope CtodCtx* ctx, bool named) @trusted scope
	{
		this.ctx = cast(CtodCtx*) ctx;
		this.tsnode = tsnode;
		this.named = named;
		this.length = named ? ts_node_named_child_count(tsnode) : ts_node_child_count(tsnode);
	}

	alias opDollar = length;

	Node opIndex(size_t i) return scope @trusted
	{
		return Node(named ?
			ts_node_named_child(tsnode, cast(uint) i) :
			ts_node_child(tsnode, cast(uint) i), ctx);
	}

	bool empty() const scope => i >= length;
	void popFront() scope
	{
		i++;
	}

	Node front() return scope => this[i];
	Node back()  return scope => this[$ - 1];
}

struct TranslationData
{
	/// D code to replace source with for this node
	string replacement = null;
	string prefix = null;
	string suffix = null;
	bool isTranslated = false; /// if translation has already been done
	bool hasBeenReplaced = false;
	bool noLayout = false; // don't emit layout
	CType type;
}

/// Conrete syntax tree node
struct Node
{
nothrow:
	private TSNode tsnode; // 32 bytes
	private CtodCtx* ctx;

	/// Start index sourceC
	uint start() @trusted const scope => ts_node_start_byte(tsnode);
	/// End index in sourceC
	uint end() @trusted const scope => ts_node_end_byte(tsnode);

	/// Tag identifying the C AST node type
	Sym sym() @trusted const scope => cast(Sym) ts_node_symbol(tsnode);

	/// Source code of this node
	string sourceC() const return scope => this.ctx.sourceC[start .. end];

	bool isNone() @trusted const scope => ts_node_is_null(tsnode);
	enum none = Node();
	bool hasError() @trusted const scope => ts_node_has_error(tsnode);

	/// #twab: "Each node has unique source range, so we can use it as a key" yeah right, not true
	ulong id() const scope => cast(ulong) this.tsnode.id; // start | (cast(ulong) end << 32) | cast(ulong) sym << 24;

	bool opEquals(ref Node other) const => this.start == other.start && this.end == other.end;

	/// Returns: Range over this node's child nodes
	Children children() inout return scope => Children(tsnode, ctx, false);

	this(TSNode node, return scope CtodCtx* ctx)
	{
		assert(ctx);
		this.tsnode = node;
		this.ctx = ctx;
	}

	private ref TranslationData mutData() return scope
	{
		return ctx.getTranslationData(this.id);
	}

	private ref const(TranslationData) constData() return scope
	{
		return ctx.getTranslationData(this.id);
	}

	bool isTranslated() scope => constData.isTranslated;
	bool isTranslated(bool v) scope => mutData.isTranslated = v;

	CType type() scope => mutData.type;
	CType type(CType t) scope => mutData.type = t;

	/// Replace this entire subtree with a translation
	bool replace(string s) scope
	{
		auto translation = &this.mutData();
		translation.isTranslated = true;
		translation.hasBeenReplaced = true;
		translation.replacement = s;
		return true;
	}

	/// Returns: source line number
	uint lineNumber() @trusted => ts_node_start_point(tsnode).row;

	/// Prevent preceding whitespace / comments from being output
	void removeLayout() scope
	{
		this.mutData.noLayout = true;
	}

	/// For translation purposes, prepend/append `s` to this node's source, without modifying the node's source itself
	void prepend(string s) scope
	{
		this.mutData.prefix = s ~ this.mutData.prefix;
	}

	/// ditto
	void append(string s) scope
	{
		this.mutData.suffix ~= s;
	}

	/// Returns: first child node with `type`
	Node firstChildType(Sym type)
	{
		foreach (ref c; this.children)
			if (c.sym == type)
				return c;

		return Node.none;
	}

	/// `false` if this is null
	bool opCast(T : bool)() const scope => !isNone;

	bool opEquals(Node other) @trusted const scope => ts_node_eq(this.tsnode, other.tsnode);

	/// Returns: full translated D source code of this node after translation
	string translation() scope
	{
		OutBuffer appender;
		appendOutput(this, appender);
		return appender.extractOutBuffer;
	}

	Node childField(Field field) return scope @trusted
	{
		auto f = ts_node_child_by_field_id(tsnode, field);
		foreach (ref c; children)
			if (ts_node_eq(c.tsnode, f))
				return c;

		return Node.none;
	}
}

private static void appendOutput(O)(scope ref Node node, ref O result)
{
	const translation = node.constData;
	string fullSource = node.ctx.sourceC;
	result ~= translation.prefix;
	if (translation.hasBeenReplaced)
	{
		result ~= translation.replacement;
	}
	else if (node.children.length == 0)
	{
		result ~= node.sourceC;
	}
	else
	{
		size_t lc = node.start; // layout cursor
		foreach (ref c; node.children)
		{
			if (!c || c.constData.noLayout)
			{
				//dprint(node.sourceC);
			}
			else
			{
				const layout = fullSource[lc .. c.start];
				foreach (i; 0 .. layout.length)
					if (layout[i] != '\\') // #filter '\' from layout
						result ~= layout[i];
			}
			lc = c.end;
			appendOutput(c, result);

		}
		result ~= fullSource[lc .. node.end];
	}
	result ~= translation.suffix;
}

/// For accessing specific child nodes
enum Field : ubyte
{
	alternative = 1,
	argument = 2,
	arguments = 3,
	body_ = 4,
	condition = 5,
	consequence = 6,
	declarator = 7,
	designator = 8,
	directive = 9,
	field = 10,
	function_ = 11,
	index = 12,
	initializer = 13,
	label = 14,
	left = 15,
	name = 16,
	operator = 17,
	parameters = 18,
	path = 19,
	prefix = 20,
	right = 21,
	size = 22,
	type = 23,
	update = 24,
	value = 25,
}

/// Identifies a C tree-sitter node
enum Sym : ushort
{
	error = 0xFFFF,
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
